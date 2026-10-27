# Checks shared by the property tests.
#
# One expect_identical() costs several milliseconds, so a loop of thousands
# of them spends the suite's time in testthat, not in zudiff. A property
# loop checks each case with identical() and records what failed;
# done() makes one expectation that lists the first failures.

property <- function() {
  failures <- character()
  list(
    check = function(ok, ...) {
      if (!isTRUE(ok)) {
        failures <<- c(failures, paste0(...))
      }
      invisible(ok)
    },
    done = function() {
      expect(
        length(failures) == 0L,
        sprintf(
          "%d case(s) failed; the first: %s",
          length(failures),
          paste(utils::head(failures, 5L), collapse = "; ")
        )
      )
    }
  )
}

# Applying diff_vec(old, new) to old gives new. Factors compare by label,
# since c() merges their levels.
round_trips <- function(old, new, ...) {
  got <- diff_apply(old, diff_vec(old, new, ...))
  if (is.factor(new)) {
    return(identical(as.character(got), as.character(new)))
  }
  identical(got, new)
}

# The full round trip for a diff of any type: its unified diff applied to
# old's lines gives new's lines. A vector diff's lines are its elements as
# diff_unified() formats them.
patch_round_trips <- function(d, context = 3L) {
  old <- paste0(zudiff:::as_lines(d, d$old), collapse = "")
  new <- paste0(zudiff:::as_lines(d, d$new), collapse = "")
  identical(
    patch_apply(old, patch_parse(diff_unified(d, context = context))),
    new
  )
}
