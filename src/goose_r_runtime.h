/* goose_r_runtime.h -- running Goose-generated C inside an R process. */
#ifndef GOOSE_R_RUNTIME_H
#define GOOSE_R_RUNTIME_H

#include <stddef.h>

/* Runs body(data) with Goose's guard-page handler installed. Returns 0 on
   success. On a Goose runtime failure (bounds check, abort, data stack
   overflow) it restores every data stack to where it was before the call,
   copies the message into err and returns 1. body must not call R's API:
   an R error raised inside it would skip the restore. */
int goose_r_run(void (*body)(void *), void *data, char *err, size_t errlen);

/* goose_r_run(), also catching SIGINT while body runs: a Ctrl-C the Goose
   code notices through zudiff_check_interrupt() fails the call, which then
   returns 2, and the signal is passed on to R's handler afterwards. For
   calls long enough to need it; it costs two more sigaction() calls. */
int goose_r_run_interruptible(void (*body)(void *), void *data, char *err, size_t errlen);

/* Bytes in use across all data stacks. Call outside goose_r_run(). */
size_t goose_r_stack_used(void);

/* Test hook: the n-th interrupt poll of the next run raises SIGINT. */
void goose_r_test_raise_after(long n);

#endif
