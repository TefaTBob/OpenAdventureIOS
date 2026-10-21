/*
 * Stand-in for libedit's <editline/readline.h>.
 *
 * iOS has no libedit and no terminal. The upstream engine only uses
 * readline() and add_history(); both are implemented in advent_bridge.c,
 * where readline() blocks the engine thread until the app submits a line.
 */
#ifndef ADVENT_SHIM_READLINE_H
#define ADVENT_SHIM_READLINE_H

char *readline(const char *prompt);
int add_history(const char *line);

#endif
