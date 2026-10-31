# The boundary with the Goose core. Every .Call entry point returns its
# value, or a string on a Goose runtime failure (src/zudiff_r.c), raised
# here after the C side has rewound Goose's data stacks.

core_value <- function(res) {
  if (is.character(res)) {
    if (isTRUE(attr(res, "zudiff_interrupt"))) {
      interrupt_r()
    }
    zudiff_abort("runtime", res)
  }
  res
}

# A Ctrl-C the Goose core's poll saw, inside R_ToplevelExec(), which keeps
# it from R: raised as R raises one, an interrupt condition, then back to
# the top level.
interrupt_r <- function() {
  signalCondition(structure(class = c("interrupt", "condition"), list()))
  invokeRestart("abort")
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
  if (!is.numeric(i) || length(i) != 1 || is.na(i) || abs(i) >= 2^31) {
    stop("`i` must be one number below 2^31 in size.")
  }
  core_value(.Call(zudiff_c_probe_index, as.integer(i)))
}

probe_sum <- function(x) {
  if (!is.integer(x) || anyNA(x)) {
    stop("`x` must be an integer vector without NA.")
  }
  core_value(.Call(zudiff_c_probe_sum, x))
}

probe_stack <- function(n, fail) {
  if (!is.numeric(n) || length(n) != 1 || is.na(n) || n < 1 || n >= 2^31) {
    stop("`n` must be one number from 1 to below 2^31.")
  }
  core_value(.Call(zudiff_c_probe_stack, as.integer(n), isTRUE(fail)))
}

stack_used <- function() .Call(zudiff_c_stack_used)

# The n-th interrupt poll of the next Goose run raises a real SIGINT.
test_raise_after <- function(n) {
  invisible(.Call(zudiff_c_test_raise_after, as.integer(n)))
}

# Calls fn() at the n-th interrupt poll of the next Goose run, as an event
# handler would be; fn = NULL clears it.
test_poll_callback <- function(fn, after) {
  invisible(.Call(zudiff_c_test_poll_callback, fn, as.integer(after)))
}

# A write to a data stack's guard gap, as an overflow makes.
test_touch_gap <- function() {
  invisible(core_value(.Call(zudiff_c_test_touch_gap)))
}
