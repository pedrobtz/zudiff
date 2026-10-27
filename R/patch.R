#' Read a unified diff
#'
#' Parses unified diff text, as [diff_unified()], GNU `diff -u` and
#' `git diff` write it, into one patch per file.
#'
#' Lines before a file's `---` header that are not part of a hunk are
#' skipped, such as git's `diff --git` and `index` lines. A timestamp after
#' a tab in the `---` and `+++` headers is dropped. A hunk must have exactly
#' the lines its `@@` header counts.
#'
#' @param text The unified diff, as one string.
#' @return A list of file patches, each a list with `old_name`, `new_name`
#'   and `hunks`. Each hunk is a list with `old_start`, `old_len`,
#'   `new_start` and `new_len`, as in the `@@` header, and `lines`, a data
#'   frame with `op` (`"equal"`, `"delete"` or `"insert"`) and `text`, the
#'   line with its ending. A line followed by `\ No newline at end of file`
#'   has no ending.
#' @export
#' @examples
#' d <- diff_text("a\nb\nc\n", "a\nx\nc\n")
#' p <- patch_parse(diff_unified(d))
#' p[[1]]$hunks[[1]]$lines
patch_parse <- function(text) {
  lines <- split_lines(check_string(text, "text"))
  files <- list()
  i <- 1L
  n <- length(lines)
  while (i <= n) {
    if (!startsWith(lines[[i]], "--- ")) {
      i <- i + 1L
      next
    }
    if (i == n || !startsWith(lines[[i + 1L]], "+++ ")) {
      patch_abort(i, "a `---` header must be followed by a `+++` header.")
    }
    file <- list(
      old_name = header_name(lines[[i]]),
      new_name = header_name(lines[[i + 1L]]),
      hunks = list()
    )
    i <- i + 2L
    while (i <= n && startsWith(lines[[i]], "@@ ")) {
      parsed <- parse_hunk(lines, i)
      file$hunks[[length(file$hunks) + 1L]] <- parsed$hunk
      i <- parsed$next_line
      if (i <= n && is_stray_hunk_line(lines, i)) {
        patch_abort(i, "the hunk has more lines than its header counts.")
      }
    }
    files[[length(files) + 1L]] <- file
  }
  files
}

# A line right after a complete hunk that looks like one of its lines,
# other than the `---` that starts the next file's header.
is_stray_hunk_line <- function(lines, i) {
  line <- lines[[i]]
  if (
    startsWith(line, "--- ") &&
      i < length(lines) &&
      startsWith(lines[[i + 1L]], "+++ ")
  ) {
    return(FALSE)
  }
  substr(line, 1L, 1L) %in% c(" ", "-", "+")
}

header_name <- function(line) {
  name <- sub("\r?\n$", "", substring(line, 5L))
  sub("\t.*$", "", name)
}

hunk_header <- "^@@ -([0-9]+)(,([0-9]+))? \\+([0-9]+)(,([0-9]+))? @@"

# One hunk starting at lines[[i]], its `@@` header.
parse_hunk <- function(lines, i) {
  m <- regmatches(lines[[i]], regexec(hunk_header, lines[[i]]))[[1]]
  if (length(m) == 0L) {
    patch_abort(i, "malformed `@@` hunk header.")
  }
  count <- function(x) if (nzchar(x)) as.integer(x) else 1L
  old_len <- count(m[[4]])
  new_len <- count(m[[7]])
  hunk <- list(
    old_start = as.integer(m[[2]]),
    old_len = old_len,
    new_start = as.integer(m[[5]]),
    new_len = new_len
  )
  op <- character()
  text <- character()
  need_old <- old_len
  need_new <- new_len
  j <- i + 1L
  while (need_old > 0L || need_new > 0L) {
    if (j > length(lines)) {
      patch_abort(j, "the hunk ends before its header's line counts are met.")
    }
    line <- lines[[j]]
    first <- substr(line, 1L, 1L)
    # A bare newline is an empty context line whose space was stripped.
    if (line %in% c("\n", "\r\n")) {
      first <- " "
      line <- paste0(" ", line)
    }
    if (first == " ") {
      need_old <- need_old - 1L
      need_new <- need_new - 1L
      op <- c(op, "equal")
    } else if (first == "-") {
      need_old <- need_old - 1L
      op <- c(op, "delete")
    } else if (first == "+") {
      need_new <- need_new - 1L
      op <- c(op, "insert")
    } else {
      patch_abort(j, "a hunk line must start with a space, `-` or `+`.")
    }
    if (need_old < 0L || need_new < 0L) {
      patch_abort(j, "the hunk has more lines than its header counts.")
    }
    text <- c(text, substring(line, 2L))
    j <- j + 1L
    if (j <= length(lines) && startsWith(lines[[j]], "\\")) {
      text[[length(text)]] <- sub("\r?\n$", "", text[[length(text)]])
      j <- j + 1L
    }
  }
  hunk$lines <- data.frame(op = op, text = text, stringsAsFactors = FALSE)
  list(hunk = hunk, next_line = j)
}

patch_abort <- function(line, message) {
  zudiff_abort("patch", sprintf("Line %d of the patch: %s", line, message))
}

#' Apply a unified diff
#'
#' Applies a patch to `old`, a string. Every hunk must match `old` exactly
#' where its header says: its unchanged and deleted lines, endings included,
#' must be the lines of `old` at that position. There is no fuzz and no
#' search for an offset; a hunk that does not match is an error naming it.
#'
#' @param old The text the patch was made from, as one string.
#' @param patch A unified diff: one string, or the result of [patch_parse()],
#'   or one file patch from it. It must hold one file patch, or none, which
#'   leaves `old` as it is.
#' @return The patched text, as one string.
#' @export
#' @examples
#' old <- "a\nb\nc\n"
#' new <- "a\nx\nc\n"
#' patch <- diff_unified(diff_text(old, new))
#' identical(patch_apply(old, patch), new)
patch_apply <- function(old, patch) {
  old_lines <- split_lines(check_string(old, "old"))
  file <- as_file_patch(patch)
  if (is.null(file)) {
    return(enc2utf8(old))
  }
  out <- vector("list", 2L * length(file$hunks) + 1L)
  pos <- 1L
  for (k in seq_along(file$hunks)) {
    h <- file$hunks[[k]]
    # An empty old side is named by the line before it.
    start <- if (h$old_len == 0L) h$old_start + 1L else h$old_start
    if (start < pos) {
      zudiff_abort(
        "patch",
        sprintf(
          "Hunk %d starts at line %d, before the end of the hunk before it.",
          k,
          h$old_start
        )
      )
    }
    from_old <- h$lines$op != "insert"
    want <- h$lines$text[from_old]
    at <- start + seq_along(want) - 1L
    if (any(at > length(old_lines)) || !identical(old_lines[at], want)) {
      zudiff_abort(
        "patch",
        sprintf("Hunk %d does not match the text at line %d.", k, h$old_start)
      )
    }
    out[[2L * k - 1L]] <- old_lines[seq_len(start - pos) + pos - 1L]
    out[[2L * k]] <- h$lines$text[h$lines$op != "delete"]
    pos <- start + length(want)
  }
  out[[length(out)]] <- old_lines[seq.int(
    pos,
    length.out = max(0L, length(old_lines) - pos + 1L)
  )]
  paste0(unlist(out), collapse = "")
}

as_file_patch <- function(patch) {
  if (is.character(patch)) {
    patch <- patch_parse(patch)
  }
  if (is.list(patch) && !is.null(patch$hunks)) {
    return(patch)
  }
  # An empty patch, as diff_unified() writes for identical inputs, changes
  # nothing.
  if (is.list(patch) && length(patch) == 0L) {
    return(NULL)
  }
  if (!is.list(patch) || length(patch) != 1L || is.null(patch[[1]]$hunks)) {
    zudiff_abort(
      "patch",
      "`patch` must hold exactly one file patch; apply each file's patch on its own."
    )
  }
  patch[[1]]
}
