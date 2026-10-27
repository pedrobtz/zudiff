#' Diff two vectors
#'
#' Computes the shortest edit script that turns `old` into `new`: which runs
#' of `old` are kept, deleted or inserted.
#'
#' Two elements are equal when [match()] says so: `NA` equals `NA`, `NaN`
#' equals `NaN` but not `NA`, `0` equals `-0`, strings compare after
#' translation to a common encoding, and factors compare by label. Doubles
#' compare exactly; round them first for a tolerance, for example
#' `diff_vec(round(x, 6), round(y, 6))`. Raw vectors are compared byte by
#' byte.
#'
#' @param old,new Two vectors of the same type: logical, integer, double,
#'   complex, character or raw. A factor counts as a character vector of its
#'   labels.
#' @param algorithm The diff algorithm. Only `"myers"` for now.
#' @return An object of class `zudiff`. Read it with [diff_edits()] and
#'   [diff_identical()], and apply it with [diff_apply()].
#' @export
#' @examples
#' d <- diff_vec(c("a", "b", "c"), c("a", "x", "c"))
#' diff_edits(d)
diff_vec <- function(old, new, algorithm = "myers") {
  algorithm <- check_algorithm(algorithm)
  a <- as_diffable(old, "old")
  b <- as_diffable(new, "new")
  if (typeof(a) != typeof(b)) {
    zudiff_abort(
      "input",
      sprintf(
        "`old` and `new` must have the same type, not %s and %s.",
        typeof(a),
        typeof(b)
      )
    )
  }
  if (length(a) + length(b) > .Machine$integer.max) {
    zudiff_abort(
      "input",
      "`old` and `new` together must be shorter than 2^31 elements."
    )
  }
  if (is.raw(a)) {
    ia <- a
    ib <- b
  } else {
    x <- c(a, b)
    ids <- match(x, x)
    ia <- ids[seq_along(a)]
    ib <- ids[length(a) + seq_along(b)]
  }
  packed <- core_value(.Call(zudiff_c_diff, ia, ib, 0L, Inf))
  new_zudiff(old, new, unpack_script(packed), algorithm)
}

check_algorithm <- function(algorithm) {
  if (
    !is.character(algorithm) ||
      length(algorithm) != 1 ||
      !algorithm %in% "myers"
  ) {
    zudiff_abort("input", "`algorithm` must be \"myers\".")
  }
  algorithm
}

# The vector the core sees: factors become their labels; anything that is
# not one of the supported atomic types is an input error.
as_diffable <- function(x, arg) {
  if (is.factor(x)) {
    return(as.character(x))
  }
  ok <- c("logical", "integer", "double", "complex", "character", "raw")
  if (!is.atomic(x) || !typeof(x) %in% ok) {
    zudiff_abort(
      "input",
      sprintf(
        "`%s` must be an atomic vector or a factor, not %s.",
        arg,
        typeof(x)
      )
    )
  }
  x
}

# The packed script of design §7, as a list.
unpack_script <- function(packed) {
  head <- readBin(packed, "integer", n = 4L, size = 4L, endian = "little")
  if (length(head) != 4L || head[[1]] != 1L) {
    zudiff_abort(
      "runtime",
      "The diff core returned a script in a format this version cannot read."
    )
  }
  n <- head[[2]]
  body <- readBin(
    packed[-(1:16)],
    "integer",
    n = 4L * n,
    size = 4L,
    endian = "little"
  )
  runs <- matrix(body, ncol = 4L, byrow = TRUE)
  list(
    op = runs[, 1],
    old_start = runs[, 2] + 1L,
    new_start = runs[, 3] + 1L,
    len = runs[, 4],
    minimal = head[[3]] == 1L,
    distance = head[[4]]
  )
}

new_zudiff <- function(old, new, script, algorithm) {
  structure(
    list(
      old = old,
      new = new,
      op = script$op,
      old_start = script$old_start,
      new_start = script$new_start,
      len = script$len,
      algorithm = algorithm,
      minimal = script$minimal,
      distance = script$distance
    ),
    class = "zudiff"
  )
}

#' Read a diff
#'
#' `diff_edits()` lists the runs of an edit script. `diff_identical()` says
#' whether the two inputs were equal.
#'
#' Each run is kept (`"equal"`), deleted or inserted. Ranges are a 1-based
#' start and a length, so `x[seq.int(start, length.out = len)]` selects a
#' run's elements. A delete has `new_len` 0 and an insert `old_len` 0; their
#' empty side's start is the position the run sits before. Adjacent runs
#' never share an operation, and a delete comes before an adjacent insert.
#'
#' @param d A `zudiff` object, from [diff_vec()].
#' @return `diff_edits()`: a data frame with columns `op`, `old_start`,
#'   `old_len`, `new_start` and `new_len`. `diff_identical()`: `TRUE` or
#'   `FALSE`.
#' @export
#' @examples
#' d <- diff_vec(1:5, c(1:2, 9L, 4:5))
#' diff_edits(d)
#' diff_identical(d)
diff_edits <- function(d) {
  check_zudiff(d)
  ops <- c("equal", "delete", "insert")[d$op + 1L]
  data.frame(
    op = ops,
    old_start = d$old_start,
    old_len = ifelse(d$op == 2L, 0L, d$len),
    new_start = d$new_start,
    new_len = ifelse(d$op == 1L, 0L, d$len),
    stringsAsFactors = FALSE
  )
}

#' @rdname diff_edits
#' @export
diff_identical <- function(d) {
  check_zudiff(d)
  all(d$op == 0L)
}

#' Apply a diff
#'
#' Applies the edit script of `d` to `old`: kept runs come from `old` and
#' inserted runs from the `new` that `d` was computed against.
#'
#' @param old The vector the diff was computed from, or one of the same
#'   length.
#' @param d A `zudiff` object, from [diff_vec()].
#' @return The vector `d` turns `old` into. For atomic vectors it is
#'   identical to `new`; for factors, it combines `old`'s and `new`'s levels
#'   as [c()] does.
#' @export
#' @examples
#' old <- c("a", "b", "c")
#' new <- c("a", "x", "c", "d")
#' identical(diff_apply(old, diff_vec(old, new)), new)
diff_apply <- function(old, d) {
  check_zudiff(d)
  if (length(old) != length(d$old)) {
    zudiff_abort(
      "input",
      sprintf(
        "`old` has %d elements but the diff was made from %d.",
        length(old),
        length(d$old)
      )
    )
  }
  pieces <- vector("list", length(d$op))
  for (i in seq_along(d$op)) {
    if (d$op[[i]] == 0L) {
      pieces[[i]] <- old[seq.int(d$old_start[[i]], length.out = d$len[[i]])]
    } else if (d$op[[i]] == 2L) {
      pieces[[i]] <- d$new[seq.int(d$new_start[[i]], length.out = d$len[[i]])]
    }
  }
  pieces <- pieces[d$op != 1L]
  if (length(pieces) == 0L) {
    return(d$new[0])
  }
  do.call(c, unname(pieces))
}

check_zudiff <- function(d) {
  if (!inherits(d, "zudiff")) {
    zudiff_abort("input", "`d` must be a zudiff object, from diff_vec().")
  }
}

#' @export
print.zudiff <- function(x, ...) {
  n <- sum(x$op != 0L)
  cat(sprintf(
    "<zudiff: %d changed run%s, edit distance %d%s>\n",
    n,
    if (n == 1L) "" else "s",
    x$distance,
    if (x$minimal) "" else ", not minimal"
  ))
  invisible(x)
}
