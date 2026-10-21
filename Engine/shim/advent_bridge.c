/*
 * advent_bridge.c — runs the upstream Open Adventure engine on a thread and
 * connects its terminal I/O to the app. See advent_bridge.h for the API.
 *
 * Locking model: the engine thread holds `lock` whenever it is executing game
 * code. It releases the lock only while blocked in readline() waiting for the
 * next line. That makes the "waiting for input" window the one moment when
 * other threads may safely read or save the global game state.
 */
#if defined(__linux__) && !defined(_GNU_SOURCE)
#define _GNU_SOURCE /* fopencookie */
#endif

#include "advent_bridge.h"

#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "advent.h"

extern int advent_main(int argc, char *argv[]);

/* ---------------------------------------------------------------- state */

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t cond = PTHREAD_COND_INITIALIZER;

static void *cb_ctx;
static advent_output_cb cb_output;
static advent_prompt_cb cb_prompt;
static advent_ended_cb cb_ended;

static pthread_t engine_thread;
static bool thread_exists;   /* created and not yet joined */
static bool running;         /* engine thread alive */
static bool waiting;         /* blocked in readline() */
static bool stop_requested;
static bool line_ready;
static char *pending_line;   /* NULL with line_ready = EOF */

static char save_dir[1024];
static char restore_path[1024];
static bool have_restore;

static struct game_t pristine_game;
static struct settings_t pristine_settings;
static bool pristine_captured;

/* --------------------------------------------------------------- output */

#if defined(__APPLE__) || defined(__FreeBSD__)
static int stream_write(void *cookie, const char *buf, int len) {
	(void)cookie;
	if (cb_output && len > 0) {
		cb_output(cb_ctx, buf, len);
	}
	return len;
}
#else
static ssize_t stream_write(void *cookie, const char *buf, size_t len) {
	(void)cookie;
	if (cb_output && len > 0) {
		cb_output(cb_ctx, buf, (long)len);
	}
	return (ssize_t)len;
}
#endif

static FILE *out_stream;
static pthread_once_t out_once = PTHREAD_ONCE_INIT;

static void make_stream(void) {
#if defined(__APPLE__) || defined(__FreeBSD__)
	out_stream = funopen(NULL, NULL, stream_write, NULL, NULL);
#else
	cookie_io_functions_t fns = {.write = stream_write};
	out_stream = fopencookie(NULL, "w", fns);
#endif
	if (out_stream) {
		setvbuf(out_stream, NULL, _IONBF, 0);
	} else {
		out_stream = stderr; /* never expected; keeps the engine alive */
	}
}

FILE *advent_output_stream(void) {
	pthread_once(&out_once, make_stream);
	return out_stream;
}

static void emit(const char *text) {
	if (cb_output && text && *text) {
		cb_output(cb_ctx, text, (long)strlen(text));
	}
}

int advent_isatty(int fd) {
	(void)fd;
	return 1;
}

/* -------------------------------------------------------------- engine end */

static _Noreturn void finish_thread(int status) {
	/* Called on the engine thread, which holds `lock`. */
	running = false;
	waiting = false;
	advent_ended_cb ended = cb_ended;
	void *ctx = cb_ctx;
	pthread_cond_broadcast(&cond);
	pthread_mutex_unlock(&lock);
	if (ended) {
		ended(ctx, status);
	}
	pthread_exit(NULL);
}

_Noreturn void advent_exit(int status) {
	finish_thread(status);
}

/* ----------------------------------------------------------------- input */

static void fill_snapshot(advent_snapshot_t *s) {
	memset(s, 0, sizeof *s);
	s->location = game.loc;
	s->location_count = NLOCATIONS < ADVENT_MAX_LOCATIONS
	                        ? NLOCATIONS
	                        : ADVENT_MAX_LOCATIONS;
	s->dark = IS_DARK_HERE();
	for (int i = 0; i < s->location_count; i++) {
		s->seen[i] = game.locs[i].abbrev > 0;
	}
	if (!s->dark && game.loc > 0 && game.loc < s->location_count) {
		s->seen[game.loc] = 1;
	}
	s->score = score(quitgame); /* silent in this mode */
	s->max_score = 430; /* Adventure 2.5 total; see score.c */
	s->turns = game.turns;
	/* What you're carrying, the way the INVENTORY command reports it. */
	for (obj_t i = 1; i < NOBJECTS && s->carried_count < ADVENT_MAX_CARRIED; i++) {
		if (i == BEAR || !TOTING(i)) {
			continue;
		}
		const char *name = objects[i].inventory;
		if (name == NULL || name[0] == '*' || name[0] == '\0') {
			continue;
		}
		s->carried[s->carried_count++] = i;
	}
	s->bear_following = TOTING(BEAR);
}

const char *advent_object_inventory(int obj) {
	if (obj <= 0 || obj >= NOBJECTS) {
		return NULL;
	}
	return objects[obj].inventory;
}

char *readline(const char *prompt) {
	/* Called on the engine thread with `lock` held. */
	const char *p = prompt ? prompt : "";
	while (*p == '\n') { /* leading newlines belong to the transcript */
		emit("\n");
		p++;
	}

	static advent_snapshot_t snap;
	fill_snapshot(&snap);
	snap.asking_filename = strstr(p, "File name") != NULL;

	line_ready = false;
	pending_line = NULL;
	waiting = true;
	if (cb_prompt) {
		cb_prompt(cb_ctx, p, &snap);
	}
	while (!line_ready && !stop_requested) {
		pthread_cond_wait(&cond, &lock);
	}
	waiting = false;

	if (stop_requested) {
		free(pending_line);
		pending_line = NULL;
		finish_thread(-1);
	}

	char *line = pending_line;
	pending_line = NULL;
	if (line) {
		/* Echo like a terminal would: prompt, what was typed, newline. */
		emit(p);
		emit(line);
		emit("\n");
	}
	return line;
}

int add_history(const char *line) {
	(void)line;
	return 0;
}

void advent_submit(const char *line) {
	pthread_mutex_lock(&lock);
	if (running && waiting && !line_ready) {
		pending_line = line ? strdup(line) : NULL;
		line_ready = true;
		pthread_cond_broadcast(&cond);
	}
	pthread_mutex_unlock(&lock);
}

/* ------------------------------------------------------------ lifecycle */

void advent_set_callbacks(void *ctx, advent_output_cb output,
                          advent_prompt_cb prompt, advent_ended_cb ended) {
	pthread_mutex_lock(&lock);
	cb_ctx = ctx;
	cb_output = output;
	cb_prompt = prompt;
	cb_ended = ended;
	pthread_mutex_unlock(&lock);
}

void advent_set_save_directory(const char *path) {
	pthread_mutex_lock(&lock);
	snprintf(save_dir, sizeof save_dir, "%s", path ? path : "");
	pthread_mutex_unlock(&lock);
}

static void *engine_main(void *arg) {
	(void)arg;
	pthread_mutex_lock(&lock);

	if (save_dir[0]) {
		/* In-game SAVE/RESUME open bare file names. */
		if (chdir(save_dir) != 0) {
			emit("(Could not open the save folder.)\n");
		}
	}

	/* Every game starts from the engine's pristine globals. */
	game = pristine_game;
	settings = pristine_settings;
	optind = 1;
#if defined(__APPLE__) || defined(__FreeBSD__)
	optreset = 1;
#endif

	static char arg0[] = "advent";
	static char arg_r[] = "-r";
	static char arg_path[sizeof restore_path];
	char *argv[4] = {arg0, NULL, NULL, NULL};
	int argc = 1;
	if (have_restore) {
		snprintf(arg_path, sizeof arg_path, "%s", restore_path);
		argv[1] = arg_r;
		argv[2] = arg_path;
		argc = 3;
	}

	int status = advent_main(argc, argv);
	finish_thread(status); /* advent_main normally exits via terminate() */
}

bool advent_start(const char *restore) {
	pthread_mutex_lock(&lock);
	if (running) {
		pthread_mutex_unlock(&lock);
		return false;
	}
	pthread_mutex_unlock(&lock);

	if (thread_exists) { /* reap a game that ended on its own */
		pthread_join(engine_thread, NULL);
		thread_exists = false;
	}

	pthread_mutex_lock(&lock);
	if (!pristine_captured) {
		pristine_game = game;
		pristine_settings = settings;
		pristine_captured = true;
	}
	have_restore = restore != NULL && restore[0] != '\0';
	if (have_restore) {
		snprintf(restore_path, sizeof restore_path, "%s", restore);
	}
	stop_requested = false;
	line_ready = false;
	waiting = false;
	running = true;

	pthread_attr_t attr;
	pthread_attr_init(&attr);
	pthread_attr_setstacksize(&attr, 8u << 20);
	int rc = pthread_create(&engine_thread, &attr, engine_main, NULL);
	pthread_attr_destroy(&attr);
	if (rc != 0) {
		running = false;
		pthread_mutex_unlock(&lock);
		return false;
	}
	thread_exists = true;
	pthread_mutex_unlock(&lock);
	return true;
}

bool advent_is_running(void) {
	pthread_mutex_lock(&lock);
	bool r = running;
	pthread_mutex_unlock(&lock);
	return r;
}

void advent_stop(void) {
	pthread_mutex_lock(&lock);
	if (running) {
		stop_requested = true;
		pthread_cond_broadcast(&cond);
		/* A game mid-turn reaches readline() within milliseconds. */
	}
	pthread_mutex_unlock(&lock);
	if (thread_exists) {
		pthread_join(engine_thread, NULL);
		thread_exists = false;
	}
}

bool advent_save(const char *path) {
	bool ok = false;
	pthread_mutex_lock(&lock);
	if (running && waiting && path) {
		FILE *fp = fopen(path, "wb");
		if (fp) {
			savefile(fp);
			ok = fflush(fp) == 0;
			ok = (fclose(fp) == 0) && ok;
		}
	}
	pthread_mutex_unlock(&lock);
	return ok;
}
