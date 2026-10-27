# git as an oracle (design §9): its change blocks, from `git diff -U0`
# hunk headers, as "-start,len +start,len" strings. A zero-length side's
# start is the line before the change, as in unified diffs.

git_available <- function() nzchar(Sys.which("git"))

git_blocks <- function(old, new, how = "--patience") {
  fa <- withr::local_tempfile()
  fb <- withr::local_tempfile()
  writeLines(old, fa)
  writeLines(new, fb)
  out <- suppressWarnings(system2(
    "git",
    c("diff", "--no-index", "--no-color", how, "-U0", fa, fb),
    stdout = TRUE
  ))
  heads <- regmatches(out, regexpr("^@@ [-+0-9,]+ [-+0-9,]+ @@", out))
  vapply(
    heads,
    function(h) {
      sides <- strsplit(h, " ")[[1]][2:3]
      norm <- function(s) {
        s <- substring(s, 2)
        if (!grepl(",", s)) {
          s <- paste0(s, ",1")
        }
        s
      }
      sprintf("-%s +%s", norm(sides[[1]]), norm(sides[[2]]))
    },
    "",
    USE.NAMES = FALSE
  )
}

# The same blocks from a zudiff object.
zudiff_blocks <- function(d) {
  e <- diff_edits(d)
  changed <- e$op != "equal"
  if (!any(changed)) {
    return(character())
  }
  group <- cumsum(c(TRUE, diff(changed) != 0))
  vapply(
    unique(group[changed]),
    function(g) {
      r <- e[group == g, ]
      ol <- sum(r$old_len)
      nl <- sum(r$new_len)
      os <- r$old_start[[1]]
      ns <- r$new_start[[1]]
      sprintf(
        "-%d,%d +%d,%d",
        if (ol == 0) os - 1L else os,
        ol,
        if (nl == 0) ns - 1L else ns,
        nl
      )
    },
    ""
  )
}

blocks_distance <- function(blocks) {
  sum(vapply(
    blocks,
    function(b) {
      n <- as.integer(regmatches(b, gregexpr("[0-9]+", b))[[1]])
      n[[2]] + n[[4]]
    },
    0L
  ))
}

# Two versions of a C file: a function moves above another and a new one
# is added. Myers' minimal script interleaves the bodies; patience moves
# the function as a block.
c_fixture <- function() {
  fn <- function(name) {
    c(
      paste0("int ", name, "(void)"),
      "{",
      paste0("    return ", name, ";"),
      "}",
      ""
    )
  }
  list(
    old = c(fn("gamma"), fn("alpha")),
    new = c(fn("alpha"), fn("gamma"), fn("beta"))
  )
}

# git's own unified diff of two texts, written to files byte for byte.
git_unified <- function(old, new, how = character()) {
  fa <- withr::local_tempfile()
  fb <- withr::local_tempfile()
  writeBin(charToRaw(enc2utf8(old)), fa)
  writeBin(charToRaw(enc2utf8(new)), fb)
  out <- suppressWarnings(system2(
    "git",
    c("diff", "--no-index", "--no-color", how, fa, fb),
    stdout = TRUE
  ))
  if (length(out) == 0L) {
    return("")
  }
  paste0(paste0(out, collapse = "\n"), "\n")
}
