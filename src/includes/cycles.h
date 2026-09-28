#ifndef __CYCLES_H_
#define __CYCLES_H_

/* Unhalted core cycles of the calling thread (user mode only) via perf_event_open.
 * cycles_init() returns 0 if the counter is unavailable; cycles_stop() then returns -1. */
extern int cycles_init(void);
extern void cycles_start(void);
extern long long cycles_stop(void);

#endif
