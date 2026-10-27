#' Diff two strings line by line
#'
#' Splits `old` and `new` into lines, keeping each line's ending, and diffs
#' the lines with [diff_vec()].
#'
#' Lines compare exactly, endings included, as `diff` and git compare them.
#' So a file with Windows line endings (`"\r\n"`) differs from the same file
#' with Unix ones (`"\n"`) on every line. A string that does not end in a
#' newline has a last line without one, which [diff_unified()] marks with
#' `\ No newline at end of file`.
#'
#' @param old,new Two strings.
#' @inheritParams diff_vec
#' @return An object of class `zudiff`, whose elements are lines. Apply it to
#'   `old` with [diff_apply()] to get `new` back as one string.
#' @export
#' @examples
#' old <- "a\nb\nc\n"
#' new <- "a\nx\nc\n"
#' d <- diff_text(old, new)
#' cat(diff_unified(d))
#' identical(diff_apply(old, d), new)
diff_text <- function(
  old,
  new,
  algorithm = c("myers", "patience"),
  max_cost = NULL
) {
  old_lines <- split_lines(check_string(old, "old"))
  new_lines <- split_lines(check_string(new, "new"))
  d <- diff_vec(
    old_lines,
    new_lines,
    algorithm = algorithm,
    max_cost = max_cost
  )
  d$text <- TRUE
  d
}

check_string <- function(x, arg) {
  if (!is.character(x) || length(x) != 1 || is.na(x)) {
    zudiff_abort("input", sprintf("`%s` must be a single string.", arg))
  }
  enc2utf8(x)
}

# Lines with their endings kept: every "\n" ends a line, and text after the
# last one, if any, is a last line without an ending.
split_lines <- function(x) {
  if (!nzchar(x)) {
    return(character())
  }
  regmatches(x, gregexpr("[^\n]*\n|[^\n]+$", x))[[1]]
}

#' Hunks of a diff
#'
#' Groups the changes of a diff into hunks, each with up to `context`
#' unchanged elements around it, as a unified diff shows them. Changes
#' closer together than twice the context share one hunk.
#'
#' @param d A `zudiff` object, from [diff_vec()] or [diff_text()].
#' @param context The number of unchanged elements to keep on each side of
#'   a change.
#' @return A list of hunks. Each hunk is a list with `old_start`, `old_len`,
#'   `new_start` and `new_len`, the range it covers in each input as in
#'   [diff_edits()], and `edits`, its rows of [diff_edits()], with the
#'   unchanged runs at its ends cut to the context.
#' @export
#' @examples
#' d <- diff_vec(1:20, c(1:4, 99L, 6:20))
#' diff_hunks(d, context = 2)
diff_hunks <- function(d, context = 3L) {
  check_zudiff(d)
  context <- check_context(context)
  e <- diff_edits(d)
  changed <- which(e$op != "equal")
  if (length(changed) == 0L) {
    return(list())
  }
  # Between two changed rows lies either nothing (a delete followed by its
  # insert) or one equal row. A gap short enough for both contexts to meet
  # joins two changes into one hunk.
  between <- changed[-1] - 1L
  gap <- e$old_len[between] * (between != changed[-length(changed)])
  group <- cumsum(c(TRUE, gap > 2 * context))
  firsts <- changed[!duplicated(group)]
  lasts <- changed[!duplicated(group, fromLast = TRUE)]
  lapply(seq_along(firsts), function(k) {
    rows <- firsts[[k]]:lasts[[k]]
    old_start <- e$old_start[rows]
    new_start <- e$new_start[rows]
    old_len <- e$old_len[rows]
    new_len <- e$new_len[rows]
    op <- e$op[rows]
    if (rows[[1]] > 1L && context > 0) {
      r <- rows[[1]] - 1L
      keep <- min(e$old_len[[r]], context)
      op <- c("equal", op)
      old_start <- c(e$old_start[[r]] + e$old_len[[r]] - keep, old_start)
      new_start <- c(e$new_start[[r]] + e$new_len[[r]] - keep, new_start)
      old_len <- c(keep, old_len)
      new_len <- c(keep, new_len)
    }
    last <- rows[[length(rows)]]
    if (last < nrow(e) && context > 0) {
      r <- last + 1L
      keep <- min(e$old_len[[r]], context)
      op <- c(op, "equal")
      old_start <- c(old_start, e$old_start[[r]])
      new_start <- c(new_start, e$new_start[[r]])
      old_len <- c(old_len, keep)
      new_len <- c(new_len, keep)
    }
    list(
      old_start = old_start[[1]],
      old_len = sum(old_len),
      new_start = new_start[[1]],
      new_len = sum(new_len),
      edits = new_edits(op, old_start, old_len, new_start, new_len)
    )
  })
}

check_context <- function(context) {
  if (
    !is.numeric(context) ||
      length(context) != 1 ||
      is.na(context) ||
      context < 0 ||
      context != trunc(context)
  ) {
    zudiff_abort(
      "input",
      "`context` must be a single non-negative whole number."
    )
  }
  as.integer(context)
}

#' Write a diff as a unified diff
#'
#' Writes the hunks of a diff in the unified format of GNU diff, which
#' `patch`, `git apply` and [patch_apply()] read.
#'
#' For a [diff_text()] result, each line is written as it is, and a last
#' line without a newline is followed by `\ No newline at end of file`. For a
#' [diff_vec()] result, each element is written with [format()] as one line.
#'
#' @param d A `zudiff` object, from [diff_vec()] or [diff_text()].
#' @param context The number of unchanged lines around each change.
#' @param old_name,new_name The file names for the `---` and `+++` headers.
#' @return One string: the unified diff, ending in a newline, or `""` when
#'   the two inputs are identical.
#' @export
#' @examples
#' d <- diff_text("a\nb\nc\n", "a\nx\nc\n")
#' cat(diff_unified(d, old_name = "a/file.txt", new_name = "b/file.txt"))
diff_unified <- function(d, context = 3L, old_name = "old", new_name = "new") {
  check_zudiff(d)
  check_name(old_name, "old_name")
  check_name(new_name, "new_name")
  lines <- unified_lines(d, diff_hunks(d, context))
  if (length(lines) == 0L) {
    return("")
  }
  paste0(
    c(paste0("--- ", old_name, "\n"), paste0("+++ ", new_name, "\n"), lines),
    collapse = ""
  )
}

check_name <- function(x, arg) {
  if (!is.character(x) || length(x) != 1 || is.na(x) || grepl("\n", x)) {
    zudiff_abort(
      "input",
      sprintf("`%s` must be a single string with no newline.", arg)
    )
  }
}

# The body of a unified diff, one element per output line, each ending in
# "\n".
unified_lines <- function(d, hunks) {
  out <- vector("list", 2L * length(hunks))
  for (k in seq_along(hunks)) {
    h <- hunks[[k]]
    e <- h$edits
    from_new <- e$op == "insert"
    len <- ifelse(from_new, e$new_len, e$old_len)
    at <- sequence(len, from = ifelse(from_new, e$new_start, e$old_start))
    side_new <- rep(from_new, len)
    lines <- character(length(at))
    lines[!side_new] <- lines_of(d, d$old, at[!side_new])
    lines[side_new] <- lines_of(d, d$new, at[side_new])
    prefix <- rep(c(equal = " ", delete = "-", insert = "+")[e$op], len)
    out[[2L * k - 1L]] <- sprintf(
      "@@ -%s +%s @@\n",
      hunk_range(h$old_start, h$old_len),
      hunk_range(h$new_start, h$new_len)
    )
    out[[2L * k]] <- mark_lines(prefix, lines)
  }
  unlist(out)
}

# Elements at of one side, as lines; only those are formatted.
lines_of <- function(d, x, at) {
  as_lines(d, x[at])
}

# A range in a hunk header: "start,len", with ",1" left out and an empty
# range named by the line before it, as GNU diff writes them.
hunk_range <- function(start, len) {
  if (len == 1L) {
    return(as.character(start))
  }
  sprintf("%d,%d", if (len == 0L) start - 1L else start, len)
}

# The elements of one side as lines. Text lines keep their endings; other
# elements are formatted one by one and given one.
as_lines <- function(d, x) {
  if (isTRUE(d$text)) {
    return(x)
  }
  if (is.factor(x)) {
    x <- as.character(x)
  }
  if (length(x) == 0L) {
    return(character())
  }
  paste0(vapply(seq_along(x), function(i) format(x[[i]]), ""), "\n")
}

mark_lines <- function(prefix, lines) {
  out <- paste0(prefix, lines)
  bare <- !endsWith(lines, "\n")
  out[bare] <- paste0(out[bare], "\n\\ No newline at end of file\n")
  out
}

#' @export
print.zudiff <- function(x, n = 50L, ...) {
  if (diff_identical(x)) {
    cat("<zudiff: no differences>\n")
    return(invisible(x))
  }
  body <- unified_lines(x, diff_hunks(x))
  lines <- sub(
    "\n$",
    "",
    unlist(strsplit(paste0(body, collapse = ""), "(?<=\n)", perl = TRUE))
  )
  cat(sprintf(
    "<zudiff: %s, edit distance %d%s>\n",
    x$algorithm,
    x$distance,
    if (x$minimal) "" else ", not minimal"
  ))
  shown <- lines[seq_len(min(length(lines), n))]
  width <- getOption("width", 80L)
  long <- nchar(shown, type = "width") > width
  shown[long] <- paste0(strtrim(shown[long], width - 3L), "...")
  cat(shown, sep = "\n")
  if (length(lines) > length(shown)) {
    cat(sprintf(
      "... %d more line%s; use `print(d, n = Inf)` to see them all.\n",
      length(lines) - length(shown),
      if (length(lines) - length(shown) == 1L) "" else "s"
    ))
  }
  invisible(x)
}
