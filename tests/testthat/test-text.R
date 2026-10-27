# diff_text(), hunks, unified output and printing (design §5, §5.1, §6.5).

test_that("diff_text() splits lines with their endings and round-trips", {
  withr::local_seed(1)
  prop <- property()
  for (f in text_fixtures(100)) {
    for (algorithm in c("myers", "patience")) {
      d <- diff_text(f$old, f$new, algorithm = algorithm)
      prop$check(
        identical(diff_apply(f$old, d), f$new),
        algorithm,
        ": ",
        deparse(f)
      )
    }
  }
  prop$done()
  expect_identical(zudiff:::split_lines("a\nb"), c("a\n", "b"))
  expect_identical(zudiff:::split_lines("a\r\n\nb\n"), c("a\r\n", "\n", "b\n"))
  expect_identical(zudiff:::split_lines(""), character())
})

test_that("line endings compare exactly", {
  d <- diff_text("a\nb\n", "a\r\nb\r\n")
  expect_identical(d$distance, 4L)
  expect_false(diff_identical(diff_text("a", "a\n")))
})

test_that("hunks keep the context and merge when contexts meet", {
  d <- diff_vec(1:30, replace(1:30, c(5L, 12L, 25L), 0L))
  h <- diff_hunks(d, context = 3)
  expect_length(h, 2L)
  expect_identical(
    h[[1]][c("old_start", "old_len", "new_start", "new_len")],
    list(old_start = 2L, old_len = 14L, new_start = 2L, new_len = 14L)
  )
  expect_named(
    h[[1]],
    c("old_start", "old_len", "new_start", "new_len", "edits")
  )
  expect_identical(sum(h[[2]]$edits$old_len), h[[2]]$old_len)
  expect_length(diff_hunks(d, context = 0), 3L)
  expect_length(diff_hunks(d, context = 10), 1L)
  expect_identical(diff_hunks(diff_vec(1:3, 1:3)), list())
  expect_error(diff_hunks(d, context = -1), class = "zudiff_input_error")
  expect_error(diff_hunks(d, context = 1.5), class = "zudiff_input_error")
})

test_that("unified output is GNU's format", {
  old <- paste0(paste0("line ", 1:20, collapse = "\n"), "\n")
  new <- sub("line 17\n", "", sub("line 5\n", "line five\n", old))
  expect_snapshot(cat(diff_unified(
    diff_text(old, new),
    old_name = "a/f.txt",
    new_name = "b/f.txt"
  )))
  expect_snapshot(cat(diff_unified(diff_text(old, new), context = 0)))
  expect_snapshot(cat(diff_unified(diff_text("a\nb", "a\nb\n"))))
  expect_snapshot(cat(diff_unified(diff_text("", "x\n"))))
  expect_snapshot(cat(diff_unified(diff_vec(c(1.5, 2, NA), c(1.5, 2.25, NA)))))
  expect_identical(diff_unified(diff_text("a\n", "a\n")), "")
  expect_error(
    diff_unified(diff_text("a", "b"), old_name = "x\ny"),
    class = "zudiff_input_error"
  )
})

test_that("GNU patch applies diff_unified()'s output", {
  skip_if_not(gnu_patch_available(), "GNU patch is not available")
  withr::local_seed(2)
  prop <- property()
  for (f in text_fixtures(60)) {
    for (context in c(0L, 3L)) {
      d <- diff_text(f$old, f$new)
      if (diff_identical(d)) {
        next
      }
      prop$check(
        identical(
          apply_with_gnu_patch(f$old, diff_unified(d, context = context)),
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

test_that("git apply applies diff_unified()'s output", {
  skip_if_not(git_available(), "git is not available")
  withr::local_seed(3)
  prop <- property()
  for (f in text_fixtures(60)) {
    for (algorithm in c("myers", "patience")) {
      d <- diff_text(f$old, f$new, algorithm = algorithm)
      if (diff_identical(d) || !nzchar(f$old)) {
        next
      }
      patch <- diff_unified(d, old_name = "a/f", new_name = "b/f")
      prop$check(
        identical(apply_with_git(f$old, patch), f$new),
        algorithm,
        ": ",
        deparse(f)
      )
    }
  }
  prop$done()
})

test_that("the print method caps and clips", {
  withr::local_options(width = 40)
  d <- diff_text("a\nb\nc\n", "a\nx\nc\n")
  expect_snapshot(print(d))
  long <- diff_vec(1:200, 201:400)
  expect_snapshot(print(long))
  expect_snapshot(print(diff_vec(strrep("w", 100), strrep("v", 100))))
  expect_snapshot(print(diff_vec(1:3, 1:3)))
  expect_output(print(long, n = Inf), "400")
})

test_that("diff_text() checks its inputs", {
  expect_error(diff_text(c("a", "b"), "a"), class = "zudiff_input_error")
  expect_error(diff_text(NA_character_, "a"), class = "zudiff_input_error")
  expect_error(diff_text(1, "a"), class = "zudiff_input_error")
})
