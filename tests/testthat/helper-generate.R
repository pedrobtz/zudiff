# Random sequence pairs for the property tests. Small alphabets make
# matches common, so the scripts mix equal, delete and insert runs.

random_values <- function(type, n, alphabet = 4L) {
  pick <- sample.int(alphabet, n, replace = TRUE)
  switch(
    type,
    logical = c(TRUE, FALSE, NA, TRUE)[pick],
    integer = c(1L, -2L, NA, 7L)[pick],
    double = c(0, 1.5, NA, NaN)[pick],
    complex = c(1i, 1 + 0i, NA, 0i)[pick],
    character = c("a", "b", NA, "ba")[pick],
    factor = factor(c("x", "y", "z", NA)[pick], levels = c("x", "y", "z")),
    raw = as.raw(c(0, 1, 255, 10))[pick]
  )
}

random_pair <- function(type, max_len = 30L) {
  list(
    old = random_values(type, sample.int(max_len + 1L, 1L) - 1L),
    new = random_values(type, sample.int(max_len + 1L, 1L) - 1L)
  )
}

supported_types <- c(
  "logical",
  "integer",
  "double",
  "complex",
  "character",
  "factor",
  "raw"
)

# The large property sweeps run where ZUDIFF_EXHAUSTIVE=true: the R CMD
# check legs, not gctorture or valgrind, whose cost they multiply while
# telling them nothing about memory safety.
exhaustive <- function() identical(Sys.getenv("ZUDIFF_EXHAUSTIVE"), "true")
