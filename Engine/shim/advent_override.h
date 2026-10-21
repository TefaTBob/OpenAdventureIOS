/*
 * Included first by each Engine/wrap/<name>_ios.c file, ahead of the unmodified
 * upstream source it wraps.
 *
 * It pulls in a few system headers first, so their declarations are untouched,
 * then redirects the handful of process-level calls that make no sense
 * inside an iOS app:
 *
 *   main()      -> advent_main(), started on a dedicated engine thread
 *   exit()      -> advent_exit(), which ends only the engine thread
 *   isatty()    -> always "interactive", so input is not echoed twice
 *   stdout, printf, vprintf -> the bridge's output stream (to the UI)
 *   signal()    -> no-op
 *
 * Upstream files are never edited; this header is the whole patch.
 */
#ifndef ADVENT_OVERRIDE_H
#define ADVENT_OVERRIDE_H

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>

FILE *advent_output_stream(void);
_Noreturn void advent_exit(int status);
int advent_isatty(int fd);

/* Upstream's Makefile passes this on the command line. */
#ifndef VERSION
#define VERSION "1.22"
#endif

#define main advent_main
#define exit advent_exit
#define isatty advent_isatty

#undef stdout
#undef printf
#undef vprintf
#define stdout (advent_output_stream())
#define printf(...) fprintf(advent_output_stream(), __VA_ARGS__)
#define vprintf(fmt, ap) vfprintf(advent_output_stream(), fmt, ap)

#define signal(sig, handler) ((void)(sig), (void)(handler))

#endif /* ADVENT_OVERRIDE_H */
