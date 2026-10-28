/* Exercises goose_r_runtime.c's Windows half without R: start-up, a diff,
   a failure that must rewind the stacks, growth through many committed
   chunks, and a reported Ctrl-C. */
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <stdint.h>
#include <string.h>
#include "goose_r_runtime.h"
#include "zudiff_goose.h"

void Rf_error(const char *fmt, ...) {
    va_list ap; va_start(ap, fmt); vfprintf(stderr, fmt, ap); va_end(ap);
    fputc('\n', stderr); exit(2);
}

uint8_t *goose_r_test_gap(void);
static void gap_body(void *p) { volatile uint8_t *g = p; *g = 1; }

static int fails;
#define CHECK(c, what) do { if (c) printf("ok   %s\n", what); else { printf("FAIL %s\n", what); fails++; } } while (0)

static void init_body(void *p) { static char n[] = "x"; static char *argv[] = {n, NULL}; (void)p; goose_init(1, argv); }
typedef struct { int64_t i, v; } idx_call;
static void idx_body(void *p) { idx_call *c = p; c->v = zudiff_probe_index(c->i); }
typedef struct { int64_t n, v; uint8_t fail; } stack_call;
static void stack_body(void *p) { stack_call *c = p; c->v = zudiff_probe_stack(c->n, c->fail); }
typedef struct { sl_i32 a, b; int64_t n; const uint8_t *out; } diff_call;
static void diff_body(void *p) { diff_call *c = p; c->out = zudiff_diff_ids(c->a, c->b, 0, -1, &c->n); }

int main(void) {
    char err[512];
    CHECK(goose_r_run(init_body, NULL, err, sizeof err) == 0, "goose_init inside a run");

    int32_t a[] = {1, 2, 3, 4}, b[] = {1, 5, 3, 4};
    diff_call d = {{a, 4}, {b, 4}, 0, NULL};
    CHECK(goose_r_run(diff_body, &d, err, sizeof err) == 0 && d.n == 16 + 16 * 4, "a diff runs and returns its script");

    size_t base = goose_r_stack_used();
    idx_call ic = {1, 0};
    CHECK(goose_r_run(idx_body, &ic, err, sizeof err) == 0 && ic.v == 20, "probe_index(1)");
    for (int k = 0; k < 1000; k++) { ic.i = 7; goose_r_run(idx_body, &ic, err, sizeof err); }
    CHECK(strstr(err, "out of bounds") != NULL, "a bounds failure comes back as a message");

    stack_call sc = {100000, 0, 1};
    for (int k = 0; k < 10; k++) goose_r_run(stack_body, &sc, err, sizeof err);
    CHECK(goose_r_stack_used() == base, "failures rewind the data stacks");

    /* 16 million i64 = 128 MB: over a hundred 1 MB commits by the handler. */
    stack_call big = {16 * 1024 * 1024, 0, 0};
    CHECK(goose_r_run(stack_body, &big, err, sizeof err) == 0 && big.v == big.n - 1, "growth past many commit chunks");
    CHECK(goose_r_stack_used() == base, "and the stack is back afterwards");

    int32_t *x = malloc(sizeof(int32_t) * 200000), *y = malloc(sizeof(int32_t) * 200000);
    srand(1);
    for (int i = 0; i < 200000; i++) { x[i] = 1 + rand() % 3; y[i] = 1 + rand() % 3; }
    diff_call longd = {{x, 200000}, {y, 200000}, 0, NULL};
    goose_r_test_raise_after(3);
    int r = goose_r_run_interruptible(diff_body, &longd, err, sizeof err);
    CHECK(r == 2 && strstr(err, "interrupted"), "a Ctrl-C fails an interruptible run with 2");
    CHECK(goose_r_stack_used() == base, "and rewinds");
    CHECK(goose_r_run(diff_body, &d, err, sizeof err) == 0, "the next call works");

    uint8_t *gap = goose_r_test_gap();
    for (int k = 0; k < 3; k++) {
        r = goose_r_run(gap_body, gap, err, sizeof err);
        CHECK(r == 1 && strstr(err, "data stack overflow"), "a write into the guard gap is a failure, not a crash");
    }
    CHECK(goose_r_stack_used() == base, "and rewinds");
    CHECK(goose_r_run(diff_body, &d, err, sizeof err) == 0 && d.n == 16 + 16 * 4, "a diff after the overflow works");

    goose_r_unload();
    printf("%s\n", fails ? "SOME FAILED" : "ALL PASSED");
    return fails != 0;
}
