/*
 * advent_bridge.h — the C API the Swift app uses to run Open Adventure.
 *
 * The engine is the unmodified upstream C code. It runs on its own thread
 * and blocks whenever it wants a line of input. The app:
 *
 *   1. registers callbacks with advent_set_callbacks()
 *   2. calls advent_start() (optionally restoring a save file)
 *   3. receives text through the output callback
 *   4. receives a prompt callback each time the engine waits for input,
 *      with a snapshot of the player's position and the rooms they have seen
 *   5. answers with advent_submit()
 *
 * Callbacks are invoked on the engine thread. Copy what you need and hop to
 * the main thread; never call advent_submit() synchronously from inside a
 * callback.
 */
#ifndef ADVENT_BRIDGE_H
#define ADVENT_BRIDGE_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#define ADVENT_MAX_LOCATIONS 256

typedef struct {
	int location;          /* current room index (LOC_*) */
	int location_count;    /* number of rooms in the dungeon */
	bool dark;             /* is the player in darkness right now? */
	bool asking_filename;  /* engine prompt is the in-game "File name:" */
	int score;             /* points so far (same formula as SCORE) */
	int max_score;         /* 430 (Adventure 2.5) */
	int turns;
	unsigned char seen[ADVENT_MAX_LOCATIONS]; /* 1 = room has been seen lit */
} advent_snapshot_t;

typedef void (*advent_output_cb)(void *ctx, const char *text, long length);
typedef void (*advent_prompt_cb)(void *ctx, const char *prompt,
                                 const advent_snapshot_t *snapshot);
typedef void (*advent_ended_cb)(void *ctx, int status);

void advent_set_callbacks(void *ctx, advent_output_cb output,
                          advent_prompt_cb prompt, advent_ended_cb ended);

/*
 * Directory the in-game SAVE/RESUME commands read and write. The engine
 * opens bare file names, so relative names are resolved against this.
 */
void advent_set_save_directory(const char *path);

/*
 * Start a fresh game, or restore one when restore_path is non-NULL.
 * Returns false if a game is already running.
 */
bool advent_start(const char *restore_path);

/* Answer the pending prompt. NULL means end-of-input (the engine quits). */
void advent_submit(const char *line);

/* True while a game thread exists (running or waiting for input). */
bool advent_is_running(void);

/*
 * Write the current game to path in the engine's native save format.
 * Only succeeds while the engine is waiting for input. Unlike the in-game
 * SAVE command, this neither charges points nor ends the game.
 */
bool advent_save(const char *path);

/*
 * Stop the running game (if any) and wait for its thread to finish.
 * Safe to call at any time; used before New Game / Load.
 */
void advent_stop(void);

#ifdef __cplusplus
}
#endif

#endif /* ADVENT_BRIDGE_H */
