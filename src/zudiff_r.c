/* zudiff_r.c -- the R entry points.

   Every call into Goose goes through goose_r_run(). A Goose runtime
   failure then comes back here as a message, after the data stacks have
   been rewound, and only then is anything done with R's API. Nothing in a
   body function may call R: an R error raised inside goose_r_run() would
   jump over the stack rewind and leave Goose's fault handler installed.

   Each entry point returns its value on success and, on failure, the
   message as a string, which R raises as a zudiff_runtime_error
   (R/core.R). No entry point returns a string on success, so the two
   cannot be confused, and success allocates nothing beyond the value. */

#include <stdint.h>
#include <string.h>

#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include <R_ext/Visibility.h>

#include "goose_r_runtime.h"
#include "goose_version.h"
#include "zudiff_goose.h"

#define ERRLEN 512
#define STR_(x) #x
#define STR(x) STR_(x)

static SEXP failure(const char *err) { return Rf_mkString(err); }

/* A Ctrl-C the Goose code reported. On POSIX the signal has gone on to R's
   handler, and R_CheckUserInterrupt() acts on it. On Windows R never saw
   it: the failure carries an attribute, and core_value() raises the
   interrupt in R (R/core.R). */
static SEXP interrupted(const char *err) {
#ifndef _WIN32
  R_CheckUserInterrupt();
#endif
  SEXP out = PROTECT(failure(err));
  Rf_setAttrib(out, Rf_install("zudiff_interrupt"), Rf_ScalarLogical(1));
  UNPROTECT(1);
  return out;
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
  char err[ERRLEN];
  /* Short diffs finish too soon to need Ctrl-C caught inside them (R acts
     on one after the call returns), so only long ones pay for it. */
  int64_t size = c.bytes ? c.ba.len + c.bb.len : c.ia.len + c.ib.len;
  int failed = size >= 4096
                   ? goose_r_run_interruptible(diff_body, &c, err, sizeof err)
                   : goose_r_run(diff_body, &c, err, sizeof err);
  if (failed == 2) return interrupted(err);
  if (failed) return failure(err);
  SEXP out = Rf_allocVector(RAWSXP, (R_xlen_t) c.n);
  if (c.n > 0) memcpy(RAW(out), c.out, (size_t) c.n);
  return out;
}

/* --- test hooks --------------------------------------------------------- */

typedef struct {
  int64_t i, v;
} probe_index_call;

static void probe_index_body(void *p) {
  probe_index_call *c = p;
  c->v = zudiff_probe_index(c->i);
}

SEXP zudiff_c_probe_index(SEXP i) {
  probe_index_call c = {(int64_t) Rf_asInteger(i), 0};
  char err[ERRLEN];
  if (goose_r_run(probe_index_body, &c, err, sizeof err))
    return failure(err);
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
  char err[ERRLEN];
  if (goose_r_run(probe_sum_body, &c, err, sizeof err))
    return failure(err);
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
  char err[ERRLEN];
  if (goose_r_run(probe_stack_body, &c, err, sizeof err))
    return failure(err);
  return Rf_ScalarReal((double) c.v);
}

SEXP zudiff_c_test_raise_after(SEXP n) {
  goose_r_test_raise_after((long) Rf_asInteger(n));
  return R_NilValue;
}

SEXP zudiff_c_stack_used(void) {
  return Rf_ScalarReal((double) goose_r_stack_used());
}

/* --- information -------------------------------------------------------- */

SEXP zudiff_c_goose_info(void) {
  SEXP out = PROTECT(Rf_allocVector(STRSXP, 2));
  SET_STRING_ELT(out, 0, Rf_mkChar(ZUDIFF_GOOSE_COMMIT));
  SET_STRING_ELT(out, 1, Rf_mkChar(STR(GS_RUNTIME_VERSION)));
  UNPROTECT(1);
  return out;
}

/* --- registration ------------------------------------------------------- */

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
    {"zudiff_c_goose_info", (DL_FUNC) &zudiff_c_goose_info, 0},
    {NULL, NULL, 0}};

void attribute_visible R_unload_zudiff(DllInfo *dll) {
  (void) dll;
  goose_r_unload();
}

void attribute_visible R_init_zudiff(DllInfo *dll) {
  char err[ERRLEN];
  if (goose_r_run(init_body, NULL, err, sizeof err))
    Rf_error("zudiff: cannot start the Goose runtime: %s", err);
  R_registerRoutines(dll, NULL, call_methods, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
  R_forceSymbols(dll, TRUE);
}
