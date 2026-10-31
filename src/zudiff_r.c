/* zudiff_r.c -- the R entry points.

   Every call into Goose goes through goose_host_call(), from Goose's own
   runtime built with -DGS_HOSTED (src/goose_runtime.c). A Goose runtime
   failure, a data stack overflow included, then comes back here as a
   message, after the runtime has rewound the data stacks, and only then is
   anything done with R's API. Nothing in a body function may raise an R
   error: it would jump over the rewind and leave Goose's fault handler
   installed. The one call into R during a run is the interrupt poll, which
   runs R_CheckUserInterrupt() inside R_ToplevelExec(), so it cannot jump.

   Each entry point returns its value on success and, on failure, the
   message as a string, which R raises as a zudiff_runtime_error
   (R/core.R). No entry point returns a string on success, so the two
   cannot be confused, and success allocates nothing beyond the value. */

#include <signal.h>
#include <stdint.h>
#include <string.h>

#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include <R_ext/Visibility.h>

#include "goose_version.h"
#include "zudiff_goose.h"

#define STR_(x) #x
#define STR(x) STR_(x)

/* A failed run's message, which goose_host_call() returns. */
static SEXP failure(const uint8_t *msg, int64_t len) {
  return Rf_ScalarString(Rf_mkCharLenCE((const char *) msg, (int) len, CE_UTF8));
}

/* A Ctrl-C the poll saw. R_ToplevelExec() has consumed it, so the failure
   carries an attribute, and core_value() raises the interrupt in R
   (R/core.R). */
static SEXP interrupted(const uint8_t *msg, int64_t len) {
  SEXP out = PROTECT(failure(msg, len));
  Rf_setAttrib(out, Rf_install("zudiff_interrupt"), Rf_ScalarLogical(1));
  UNPROTECT(1);
  return out;
}

static SEXP run_failed(int failed, const uint8_t *msg, int64_t len) {
  return failed == 2 ? interrupted(msg, len) : failure(msg, len);
}

/* --- interrupts ----------------------------------------------------------- */

/* Test hook: the n-th poll of the next run raises SIGINT, which R's own
   handler catches. On Windows the poll reports the interrupt itself, as a
   Ctrl-C would make R_CheckUserInterrupt() do. */
static long raise_after;

static void check_interrupt(void *unused) {
  (void) unused;
  R_CheckUserInterrupt();
}

/* Called by the Goose core every 1024 search steps (goose_host_poll). */
static int poll_interrupt(void) {
  if (raise_after > 0 && --raise_after == 0) {
#ifdef _WIN32
    return 1;
#else
    raise(SIGINT);
#endif
  }
  return !R_ToplevelExec(check_interrupt, NULL);
}

/* --- diffs ---------------------------------------------------------------- */

typedef struct {
  int bytes;
  sl_i32 ia, ib;
  sl_u8 ba, bb;
  int32_t algorithm;
  int64_t max_cost, n;
  const uint8_t *out;
} diff_call;

static void diff_body(void *p) {
  diff_call *c = p;
  if (c->bytes)
    c->out = zudiff_diff_bytes(c->ba, c->bb, c->algorithm, c->max_cost, &c->n);
  else
    c->out = zudiff_diff_ids(c->ia, c->ib, c->algorithm, c->max_cost, &c->n);
}

/* a and b are both integer or both raw vectors, checked in R, each shorter
   than 2^31. They are borrowed, not copied. The packed script is copied
   into a raw vector after the run, since Goose reuses its memory. */
SEXP zudiff_c_diff(SEXP a, SEXP b, SEXP algorithm, SEXP max_cost) {
  diff_call c;
  memset(&c, 0, sizeof c);
  c.bytes = TYPEOF(a) == RAWSXP;
  if (c.bytes) {
    c.ba.data = RAW(a);
    c.ba.len = (int64_t) XLENGTH(a);
    c.bb.data = RAW(b);
    c.bb.len = (int64_t) XLENGTH(b);
  } else {
    c.ia.data = INTEGER(a);
    c.ia.len = (int64_t) XLENGTH(a);
    c.ib.data = INTEGER(b);
    c.ib.len = (int64_t) XLENGTH(b);
  }
  c.algorithm = (int32_t) Rf_asInteger(algorithm);
  /* Inf, NaN or anything past int64's range means no limit; converting
     such a double to int64_t directly is undefined behaviour. A negative
     value asks for the default limit. */
  double mc = Rf_asReal(max_cost);
  c.max_cost = (ISNAN(mc) || mc >= 9223372036854775807.0) ? INT64_MAX
               : mc < 0 ? -1 : (int64_t) mc;
  const uint8_t *msg;
  int64_t len;
  int failed = goose_host_call(diff_body, &c, &msg, &len);
  raise_after = 0;
  if (failed) return run_failed(failed, msg, len);
  SEXP out = Rf_allocVector(RAWSXP, (R_xlen_t) c.n);
  if (c.n > 0) memcpy(RAW(out), c.out, (size_t) c.n);
  return out;
}

/* --- test hooks ----------------------------------------------------------- */

typedef struct {
  int64_t i, v;
} probe_index_call;

static void probe_index_body(void *p) {
  probe_index_call *c = p;
  c->v = zudiff_probe_index(c->i);
}

SEXP zudiff_c_probe_index(SEXP i) {
  probe_index_call c = {(int64_t) Rf_asInteger(i), 0};
  const uint8_t *msg;
  int64_t len;
  int failed = goose_host_call(probe_index_body, &c, &msg, &len);
  if (failed) return run_failed(failed, msg, len);
  return Rf_ScalarReal((double) c.v);
}

typedef struct {
  sl_i32 a;
  int64_t v;
} probe_sum_call;

static void probe_sum_body(void *p) {
  probe_sum_call *c = p;
  c->v = zudiff_probe_sum(c->a);
}

/* x is an integer vector, checked in R. It is borrowed, not copied. */
SEXP zudiff_c_probe_sum(SEXP x) {
  probe_sum_call c = {{INTEGER(x), (int64_t) XLENGTH(x)}, 0};
  const uint8_t *msg;
  int64_t len;
  int failed = goose_host_call(probe_sum_body, &c, &msg, &len);
  if (failed) return run_failed(failed, msg, len);
  return Rf_ScalarReal((double) c.v);
}

typedef struct {
  int64_t n, v;
  uint8_t fail;
} probe_stack_call;

static void probe_stack_body(void *p) {
  probe_stack_call *c = p;
  c->v = zudiff_probe_stack(c->n, c->fail);
}

SEXP zudiff_c_probe_stack(SEXP n, SEXP fail) {
  probe_stack_call c = {(int64_t) Rf_asInteger(n), 0,
                        (uint8_t) Rf_asLogical(fail)};
  const uint8_t *msg;
  int64_t len;
  int failed = goose_host_call(probe_stack_body, &c, &msg, &len);
  if (failed) return run_failed(failed, msg, len);
  return Rf_ScalarReal((double) c.v);
}

/* A write to the first data stack's guard gap, as an overflow makes: it
   must come back as a failure, not end R. */
static void touch_gap_body(void *p) {
  *(volatile uint8_t *) p = 1;
}

SEXP zudiff_c_test_touch_gap(void) {
  const uint8_t *msg;
  int64_t len;
  int failed = goose_host_call(touch_gap_body, goose_host_test_gap(), &msg, &len);
  if (failed) return run_failed(failed, msg, len);
  return R_NilValue;
}

SEXP zudiff_c_test_raise_after(SEXP n) {
  raise_after = (long) Rf_asInteger(n);
  return R_NilValue;
}

SEXP zudiff_c_stack_used(void) {
  return Rf_ScalarReal((double) goose_host_stack_used());
}

/* --- information ---------------------------------------------------------- */

SEXP zudiff_c_goose_info(void) {
  SEXP out = PROTECT(Rf_allocVector(STRSXP, 2));
  SET_STRING_ELT(out, 0, Rf_mkChar(ZUDIFF_GOOSE_COMMIT));
  SET_STRING_ELT(out, 1, Rf_mkChar(STR(GS_RUNTIME_VERSION)));
  UNPROTECT(1);
  return out;
}

/* --- registration --------------------------------------------------------- */

static void init_body(void *unused) {
  static char name[] = "zudiff";
  static char *argv[] = {name, NULL};
  (void) unused;
  goose_init(1, argv);
}

static const R_CallMethodDef call_methods[] = {
    {"zudiff_c_diff", (DL_FUNC) &zudiff_c_diff, 4},
    {"zudiff_c_probe_index", (DL_FUNC) &zudiff_c_probe_index, 1},
    {"zudiff_c_probe_sum", (DL_FUNC) &zudiff_c_probe_sum, 1},
    {"zudiff_c_probe_stack", (DL_FUNC) &zudiff_c_probe_stack, 2},
    {"zudiff_c_stack_used", (DL_FUNC) &zudiff_c_stack_used, 0},
    {"zudiff_c_test_raise_after", (DL_FUNC) &zudiff_c_test_raise_after, 1},
    {"zudiff_c_test_touch_gap", (DL_FUNC) &zudiff_c_test_touch_gap, 0},
    {"zudiff_c_goose_info", (DL_FUNC) &zudiff_c_goose_info, 0},
    {NULL, NULL, 0}};

void attribute_visible R_unload_zudiff(DllInfo *dll) {
  (void) dll;
  goose_host_unload();
}

void attribute_visible R_init_zudiff(DllInfo *dll) {
  goose_host h = {NULL, poll_interrupt};
  const uint8_t *msg;
  int64_t len;
  goose_host_set(&h);
  if (goose_host_call(init_body, NULL, &msg, &len))
    Rf_error("zudiff: cannot start the Goose runtime: %.*s", (int) len, (const char *) msg);
  R_registerRoutines(dll, NULL, call_methods, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
  R_forceSymbols(dll, TRUE);
}
