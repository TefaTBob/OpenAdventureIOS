/*
 * bridge_harness.c — drives advent_bridge the same way the iOS app does
 * (output callback, prompt callback, advent_submit from another thread),
 * feeding lines from an upstream test log. Its stdout can be diffed against
 * the upstream .chk files to prove the bridge changes nothing.
 *
 *   usage: bridge_harness test.log [restore.adv]
 */
#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "advent_bridge.h"

static pthread_mutex_t m = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t c = PTHREAD_COND_INITIALIZER;
static int prompts_pending;
static bool ended;

static void on_output(void *ctx, const char *text, long len) {
	(void)ctx;
	fwrite(text, 1, (size_t)len, stdout);
}

static void on_prompt(void *ctx, const char *prompt,
                      const advent_snapshot_t *s) {
	(void)ctx;
	(void)prompt;
	/* LOCLOG=1: trace where the player is at each prompt (map checks). */
	if (getenv("LOCLOG"))
		fprintf(stderr, "LOC %d %d\n", s->location, s->dark);
	/* INVLOG=1: what the snapshot says you're carrying. */
	if (getenv("INVLOG")) {
		fprintf(stderr, "INV");
		for (int i = 0; i < s->carried_count; i++)
			fprintf(stderr, " [%s]", advent_object_inventory(s->carried[i]));
		fprintf(stderr, s->bear_following ? " +bear\n" : "\n");
	}
	pthread_mutex_lock(&m);
	prompts_pending++;
	pthread_cond_signal(&c);
	pthread_mutex_unlock(&m);
}

static void on_ended(void *ctx, int status) {
	(void)ctx;
	(void)status;
	pthread_mutex_lock(&m);
	ended = true;
	pthread_cond_signal(&c);
	pthread_mutex_unlock(&m);
}

int main(int argc, char **argv) {
	if (argc < 2) {
		fprintf(stderr, "usage: %s test.log [restore.adv]\n", argv[0]);
		return 2;
	}
	FILE *log = fopen(argv[1], "r");
	if (!log) {
		perror(argv[1]);
		return 2;
	}
	advent_set_callbacks(NULL, on_output, on_prompt, on_ended);
	advent_start(argc > 2 ? argv[2] : NULL);

	char line[2048];
	for (;;) {
		pthread_mutex_lock(&m);
		while (prompts_pending == 0 && !ended) {
			pthread_cond_wait(&c, &m);
		}
		if (ended) {
			pthread_mutex_unlock(&m);
			break;
		}
		prompts_pending--;
		pthread_mutex_unlock(&m);

		char *got;
		while ((got = fgets(line, sizeof line, log)) && line[0] == '#') {
			/* the engine ignores comment lines; don't echo them */
		}
		if (got) {
			line[strcspn(line, "\n")] = 0;
			advent_submit(line);
		} else {
			advent_submit(NULL); /* EOF, like ^D */
		}
	}
	advent_stop();
	fflush(stdout);
	return 0;
}
