# The boundary with the Goose core. Every .Call entry point returns
# list(value, error) (src/zudiff_r.c); a non-NULL error is a Goose runtime
# failure, raised here after the C side has rewound Goose's data stacks.

core_value <- function(res) {
  if (!is.null(res[[2]])) {
    zudiff_abort("runtime", res[[2]])
  }
  res[[1]]
}

zudiff_abort <- function(kind, message, call = NULL) {
  stop(structure(
    class = c(
      paste0("zudiff_", kind, "_error"),
      "zudiff_error",
      "error",
      "condition"
    ),
    list(message = message, call = call)
  ))
}

# Test hooks into the core (tests/testthat/test-runtime.R).

probe_index <- function(i) {
  stopifnot(is.numeric(i), length(i) == 1, !is.na(i), abs(i) < 2^31)
  core_value(.Call(zudiff_c_probe_index, as.integer(i)))
}

probe_sum <- function(x) {
  stopifnot(is.integer(x), !anyNA(x))
  core_value(.Call(zudiff_c_probe_sum, x))
}

probe_stack <- function(n, fail) {
  stopifnot(is.numeric(n), length(n) == 1, n >= 1, n < 2^31)
  core_value(.Call(zudiff_c_probe_stack, as.integer(n), isTRUE(fail)))
}

stack_used <- function() .Call(zudiff_c_stack_used)
