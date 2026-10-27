# The shared object exports R's entry point and nothing else, so the Goose
# runtime's gs_* symbols cannot clash with another package's copy.

test_that("the shared object exports R_init_zudiff only", {
  skip_on_cran()
  skip_on_os("windows")
  nm <- Sys.which("nm")
  skip_if(!nzchar(nm), "nm is not available")
  so <- getLoadedDLLs()[["zudiff"]][["path"]]
  args <- if (Sys.info()[["sysname"]] == "Darwin") {
    c("-gU", so)
  } else {
    c("-gD", "--defined-only", so)
  }
  out <- system2(nm, args, stdout = TRUE)
  syms <- sub("^_", "", sub(".* ", "", out[nzchar(out)]))
  expect_identical(syms, "R_init_zudiff")
})
