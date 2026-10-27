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
#' @param algorithm The diff algorithm: `"myers"`, the default, or
#'   `"patience"`. Myers finds a shortest edit script. Patience first
#'   aligns the elements that occur exactly once on each side, then diffs
#'   the stretches between them, with Myers where a stretch has no such
#'   element. On text it keeps functions and blocks aligned where Myers
#'   may match stray braces and blank lines instead. Its scripts are not
#'   minimal in general, and the result always records `minimal = FALSE`.
#' @param max_cost The cost limit of Myers' search, which trades
#'   minimality for time. `NULL`, the default, follows GNU diff: about the
#'   square root of the input size, and at least 4096. `Inf` always finds a
#'   minimal script, in O((N + M) D) time for edit distance D. A smaller
#'   number gives up sooner on very different inputs; the script is still
#'   correct, but may not be minimal, which the result records.
#'
#'   The limit counts the steps of each middle-snake search, as GNU diff
#'   does, not the edit distance of the whole script.
#' @return An object of class `zudiff`. Read it with [diff_edits()] and
#'   [diff_identical()], and apply it with [diff_apply()].
#' @export
#' @examples
#' d <- diff_vec(c("a", "b", "c"), c("a", "x", "c"))
#' diff_edits(d)
diff_vec <- function(
  old,
  new,
  algorithm = c("myers", "patience"),
  max_cost = NULL
) {
  algorithm <- check_algorithm(algorithm)
  code <- c(myers = 0L, patience = 1L)[[algorithm]]
  max_cost <- check_max_cost(max_cost)
  diff_vec_impl(old, new, algorithm, code, max_cost)
}

# The diff itself. code is the core's algorithm number: 0 for Myers, 1 for
# patience, 9 for
# the greedy reference the tests compare against.
diff_vec_impl <- function(old, new, algorithm, code, max_cost) {
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
  # Identical inputs are equal element by element under match() too, so
  # their script is one equal run, and match() is not needed.
  if (identical(a, b)) {
    return(new_zudiff(old, new, equal_script(length(a), code), algorithm))
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
  packed <- core_value(.Call(zudiff_c_diff, ia, ib, code, max_cost))
  new_zudiff(old, new, unpack_script(packed), algorithm)
}

# -1 asks the core for its default limit.
check_max_cost <- function(max_cost) {
  if (is.null(max_cost)) {
    return(-1)
  }
  if (
    !is.numeric(max_cost) ||
      length(max_cost) != 1 ||
      is.na(max_cost) ||
      max_cost < 0
  ) {
    zudiff_abort(
      "input",
      "`max_cost` must be NULL or a single non-negative number."
    )
  }
  as.double(max_cost)
}

check_algorithm <- function(algorithm) {
  choices <- c("myers", "patience")
  if (identical(algorithm, choices)) {
    return("myers")
  }
  if (
    !is.character(algorithm) ||
      length(algorithm) != 1 ||
      !algorithm %in% choices
  ) {
    zudiff_abort("input", "`algorithm` must be \"myers\" or \"patience\".")
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

# The script of two identical inputs of length n. Patience results are
# never marked minimal (design §6.4).
equal_script <- function(n, code) {
  list(
    op = if (n > 0L) 0L else integer(),
    old_start = if (n > 0L) 1L else integer(),
    new_start = if (n > 0L) 1L else integer(),
    len = if (n > 0L) as.integer(n) else integer(),
    minimal = code != 1L,
    distance = 0L
  )
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
  all <- readBin(
    packed,
    "integer",
    n = 4L + 4L * n,
    size = 4L,
    endian = "little"
  )
  at <- 4L * seq_len(n)
  list(
    op = all[at + 1L],
    old_start = all[at + 2L] + 1L,
    new_start = all[at + 3L] + 1L,
    len = all[at + 4L],
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
  new_edits(
    op = c("equal", "delete", "insert")[d$op + 1L],
    old_start = d$old_start,
    old_len = d$len * (d$op != 2L),
    new_start = d$new_start,
    new_len = d$len * (d$op != 1L)
  )
}

# A data frame of edits, built directly: data.frame() costs hundreds of
# microseconds, more than the diff of a short vector.
new_edits <- function(op, old_start, old_len, new_start, new_len) {
  structure(
    list(
      op = op,
      old_start = old_start,
      old_len = old_len,
      new_start = new_start,
      new_len = new_len
    ),
    class = "data.frame",
    row.names = .set_row_names(length(op))
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
#'   length. For a [diff_text()] result, the string.
#' @param d A `zudiff` object, from [diff_vec()] or [diff_text()].
#' @return The vector `d` turns `old` into. For atomic vectors it is
#'   identical to `new`; for factors, it combines `old`'s and `new`'s levels
#'   as [c()] does. For a [diff_text()] result, the new string.
#' @export
#' @examples
#' old <- c("a", "b", "c")
#' new <- c("a", "x", "c", "d")
#' identical(diff_apply(old, diff_vec(old, new)), new)
diff_apply <- function(old, d) {
  check_zudiff(d)
  if (isTRUE(d$text)) {
    lines <- diff_apply(split_lines(check_string(old, "old")), strip_text(d))
    return(paste0(lines, collapse = ""))
  }
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

# A text diff applied as a plain vector diff of its lines.
strip_text <- function(d) {
  d$text <- NULL
  d
}

check_zudiff <- function(d) {
  if (!inherits(d, "zudiff")) {
    zudiff_abort("input", "`d` must be a zudiff object, from diff_vec().")
  }
}
