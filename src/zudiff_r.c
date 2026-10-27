/* zudiff_r.c -- the R entry points.

   Every call into Goose goes through goose_r_run(). A Goose runtime
   failure then comes back here as a message, after the data stacks have
   been rewound, and only then is anything done with R's API. Nothing in a
   body function may call R: an R error raised inside goose_r_run() would
   jump over the stack rewind and leave Goose's fault handler installed.

   Each entry point returns list(value, error): error is NULL on success
   and the failure message otherwise, which R raises as a
   zudiff_runtime_error (R/core.R). */

#include <stdint.h>

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

static SEXP result(SEXP value, const char *err) {
  SEXP out = PROTECT(Rf_allocVector(VECSXP, 2));
  if (value != R_NilValue) SET_VECTOR_ELT(out, 0, value);
  if (err) SET_VECTOR_ELT(out, 1, Rf_mkString(err));
  UNPROTECT(1);
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
    return result(R_NilValue, err);
  return result(Rf_ScalarReal((double) c.v), NULL);
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
    return result(R_NilValue, err);
  return result(Rf_ScalarReal((double) c.v), NULL);
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
    {"zudiff_c_probe_index", (DL_FUNC) &zudiff_c_probe_index, 1},
    {"zudiff_c_probe_sum", (DL_FUNC) &zudiff_c_probe_sum, 1},
    {"zudiff_c_goose_info", (DL_FUNC) &zudiff_c_goose_info, 0},
    {NULL, NULL, 0}};

void attribute_visible R_init_zudiff(DllInfo *dll) {
  char err[ERRLEN];
  if (goose_r_run(init_body, NULL, err, sizeof err))
    Rf_error("zudiff: cannot start the Goose runtime: %s", err);
  R_registerRoutines(dll, NULL, call_methods, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
  R_forceSymbols(dll, TRUE);
}
