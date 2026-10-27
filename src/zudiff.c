#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>

/* Placeholder until Stage 1 replaces this file with the Goose glue. */
void R_init_zudiff(DllInfo *dll) {
  R_registerRoutines(dll, NULL, NULL, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
  R_forceSymbols(dll, TRUE);
}
