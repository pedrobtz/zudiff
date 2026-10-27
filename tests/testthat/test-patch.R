# patch_parse() and patch_apply() (design §6.5, §9, D7).

test_that("diff_unified() output round-trips through patch_parse() and patch_apply()", {
  withr::local_seed(20261027)
  # tools/run-sweep runs the full 10^5 pairs of design §12.
  pairs <- if (exhaustive()) 2000 else 300
  prop <- property()
  for (i in seq_len(pairs)) {
    type <- supported_types[[(i - 1L) %% length(supported_types) + 1L]]
    p <- random_pair(type)
    d <- diff_vec(
      p$old,
      p$new,
      algorithm = if (i %% 2L) "myers" else "patience"
    )
    prop$check(patch_round_trips(d, context = i %% 4L), type, " pair ", i)
  }
  prop$done()
})

test_that("text patches round-trip, including the format's special cases", {
  withr::local_seed(5)
  prop <- property()
  for (f in text_fixtures(100)) {
    for (context in c(0L, 3L)) {
      d <- diff_text(f$old, f$new)
      prop$check(
        identical(
          patch_apply(f$old, diff_unified(d, context = context)),
          f$new
        ) &&
          identical(
            patch_apply(f$old, patch_parse(diff_unified(d))[[1]]),
            f$new
          ),
        "context ",
        context,
        ": ",
        deparse(f)
      )
    }
  }
  prop$done()
})

test_that("patch_apply() applies git diff --no-index output", {
  skip_if_not(git_available(), "git is not available")
  withr::local_seed(6)
  prop <- property()
  for (f in text_fixtures(40)) {
    if (identical(f$old, f$new)) {
      next
    }
    for (how in list(character(), "--minimal", "--patience")) {
      prop$check(
        identical(patch_apply(f$old, git_unified(f$old, f$new, how)), f$new),
        paste(how, collapse = ""),
        ": ",
        deparse(f)
      )
    }
  }
  prop$done()
})

test_that("Myers' edit distance equals git diff --minimal's", {
  skip_if_not(git_available(), "git is not available")
  withr::local_seed(8)
  pairs <- if (exhaustive()) 300 else 50
  prop <- property()
  for (i in seq_len(pairs)) {
    k <- sample(3:40, 1)
    a <- paste0("l", sample.int(k, sample(5:60, 1), replace = TRUE))
    b <- paste0("l", sample.int(k, sample(5:60, 1), replace = TRUE))
    prop$check(
      identical(
        diff_vec(a, b, max_cost = Inf)$distance,
        blocks_distance(git_blocks(a, b, "--minimal"))
      ),
      "pair ",
      i
    )
  }
  prop$done()
})

test_that("patch_parse() reads names, timestamps, git headers and several files", {
  text <- paste0(
    "diff --git a/x.txt b/x.txt\n",
    "index 1234567..89abcde 100644\n",
    "--- a/x.txt\t2026-10-27 10:00:00.000000000 +0000\n",
    "+++ b/x.txt\t2026-10-27 10:00:01.000000000 +0000\n",
    "@@ -1,2 +1,2 @@\n",
    " a\n",
    "-b\n",
    "+c\n",
    "diff --git a/y.txt b/y.txt\n",
    "--- a/y.txt\n",
    "+++ b/y.txt\n",
    "@@ -1 +1 @@\n",
    "-p\n",
    "\\ No newline at end of file\n",
    "+q\n"
  )
  p <- patch_parse(text)
  expect_length(p, 2L)
  expect_identical(p[[1]]$old_name, "a/x.txt")
  expect_identical(p[[1]]$new_name, "b/x.txt")
  expect_identical(p[[1]]$hunks[[1]]$lines$op, c("equal", "delete", "insert"))
  expect_identical(p[[2]]$hunks[[1]]$lines$text, c("p", "q\n"))
  expect_identical(patch_apply("a\nb\n", p[[1]]), "a\nc\n")
  expect_identical(patch_apply("p", p[[2]]), "q\n")
  expect_error(patch_apply("a\nb\n", p), class = "zudiff_patch_error")
  expect_identical(patch_parse(""), list())
  expect_identical(patch_apply("a\n", ""), "a\n")
})

test_that("a bare newline in a hunk is an empty context line", {
  patch <- "--- old\n+++ new\n@@ -1,3 +1,3 @@\n a\n\n-b\n+c\n"
  expect_identical(patch_apply("a\n\nb\n", patch), "a\n\nc\n")
})

test_that("a patch that does not match or does not parse is a zudiff_patch_error", {
  patch <- diff_unified(diff_text("a\nb\nc\n", "a\nx\nc\n"))
  err <- expect_error(
    patch_apply("a\nz\nc\n", patch),
    class = "zudiff_patch_error"
  )
  expect_s3_class(err, "zudiff_error")
  # Exact context, no offset search (D7): the same lines one line lower fail.
  expect_error(patch_apply("q\na\nb\nc\n", patch), class = "zudiff_patch_error")
  expect_error(
    patch_apply("a\r\nb\r\nc\r\n", patch),
    class = "zudiff_patch_error"
  )
  expect_error(patch_apply("a\n", patch), class = "zudiff_patch_error")
  expect_error(
    patch_parse("--- a\n@@ -1 +1 @@\n"),
    class = "zudiff_patch_error"
  )
  expect_error(
    patch_parse("--- a\n+++ b\n@@ -1,2 +1 @@\n-x\n"),
    class = "zudiff_patch_error"
  )
  expect_error(
    patch_parse("--- a\n+++ b\n@@ -1 +1 @@\n-x\n+y\n+z\n@@ -9 +9 @@\n"),
    class = "zudiff_patch_error"
  )
  expect_error(
    patch_parse("--- a\n+++ b\n@@ -1 +1 @@\n*x\n"),
    class = "zudiff_patch_error"
  )
  expect_error(
    patch_parse("--- a\n+++ b\n@@ bad @@\n"),
    class = "zudiff_patch_error"
  )
  two <- "--- o\n+++ n\n@@ -3 +3 @@\n-c\n+C\n@@ -1 +1 @@\n-a\n+A\n"
  expect_error(patch_apply("a\nb\nc\n", two), class = "zudiff_patch_error")
})
