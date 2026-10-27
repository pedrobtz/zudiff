# GNU patch and git apply as oracles for diff_unified() (design §9). Each
# applies a unified diff to old, written to a file byte for byte, and
# returns the result as one string, or NULL when the tool is missing.

gnu_patch_available <- function() {
  if (!nzchar(Sys.which("patch"))) {
    return(FALSE)
  }
  out <- suppressWarnings(system2(
    "patch",
    "--version",
    stdout = TRUE,
    stderr = TRUE
  ))
  any(grepl("GNU patch", out, fixed = TRUE))
}

write_bytes <- function(text, path) {
  writeBin(charToRaw(enc2utf8(text)), path)
}

read_bytes <- function(path) {
  rawToChar(readBin(path, "raw", file.size(path)))
}

apply_with_gnu_patch <- function(old, patch) {
  dir <- withr::local_tempdir()
  f <- file.path(dir, "f")
  p <- file.path(dir, "f.patch")
  write_bytes(old, f)
  write_bytes(patch, p)
  status <- system2(
    "patch",
    c("-s", "-N", "-i", shQuote(p), shQuote(f)),
    stdout = FALSE,
    stderr = FALSE
  )
  if (status != 0) {
    return(NA_character_)
  }
  read_bytes(f)
}

apply_with_git <- function(old, patch) {
  dir <- withr::local_tempdir()
  write_bytes(old, file.path(dir, "f"))
  write_bytes(patch, file.path(dir, "f.patch"))
  status <- withr::with_dir(
    dir,
    system2(
      "git",
      c("apply", "--unidiff-zero", "f.patch"),
      stdout = FALSE,
      stderr = FALSE
    )
  )
  if (status != 0) {
    return(NA_character_)
  }
  read_bytes(file.path(dir, "f"))
}

# Text pairs for the interop tests: random line files, plus the cases the
# format has special rules for.
text_fixtures <- function(n = 60L) {
  lines <- function(k) {
    paste0(
      paste0("l", sample.int(8L, k, replace = TRUE), collapse = "\n"),
      "\n"
    )
  }
  random <- lapply(seq_len(n), function(i) {
    list(old = lines(sample(1:40, 1)), new = lines(sample(1:40, 1)))
  })
  special <- list(
    list(old = "a\nb", new = "a\nb\n"),
    list(old = "a\nb\n", new = "a\nb"),
    list(old = "a\nb", new = "a\nc"),
    list(old = "x\ny\nz", new = "w\ny\nz"),
    list(old = "", new = "a\nb\n"),
    list(old = "a\nb\n", new = ""),
    list(old = "a\r\nb\r\n", new = "a\r\nc\r\n"),
    list(old = "a\nb\n", new = "a\r\nb\r\n"),
    list(old = "café\n", new = "cafés\n")
  )
  c(special, random)
}
