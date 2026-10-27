# diff_vec(): the round trip, the shape of the script (design §6.2) and the
# input checks (§8).

test_that("applying the script to old gives new, for every type", {
  withr::local_seed(20261027)
  prop <- property()
  for (type in supported_types) {
    for (i in 1:200) {
      p <- random_pair(type)
      prop$check(round_trips(p$old, p$new), type, " pair ", i)
    }
  }
  prop$done()
})

test_that("empty and identical inputs give the obvious scripts", {
  expect_identical(diff_edits(diff_vec(integer(), integer()))$op, character())
  e <- diff_edits(diff_vec(1:3, integer()))
  expect_identical(e$op, "delete")
  e <- diff_edits(diff_vec(integer(), 1:3))
  expect_identical(e$op, "insert")
  d <- diff_vec(letters, letters)
  expect_true(diff_identical(d))
  expect_identical(diff_edits(d)$op, "equal")
})

test_that("runs are maximal and a delete comes before an adjacent insert", {
  withr::local_seed(1)
  prop <- property()
  for (i in 1:300) {
    p <- random_pair("integer")
    e <- diff_edits(diff_vec(p$old, p$new))
    if (nrow(e) > 1) {
      prop$check(
        !any(e$op[-1] == e$op[-nrow(e)]),
        "pair ",
        i,
        ": runs not maximal"
      )
      prop$check(
        !any(e$op[-nrow(e)] == "insert" & e$op[-1] == "delete"),
        "pair ",
        i,
        ": insert before delete"
      )
    }
  }
  prop$done()
})

test_that("diff_edits() ranges are 1-based starts and lengths that tile both inputs", {
  withr::local_seed(2)
  prop <- property()
  for (i in 1:200) {
    p <- random_pair("character")
    e <- diff_edits(diff_vec(p$old, p$new))
    prop$check(
      identical(
        names(e),
        c("op", "old_start", "old_len", "new_start", "new_len")
      ) &&
        identical(sum(e$old_len), length(p$old)) &&
        identical(sum(e$new_len), length(p$new)) &&
        identical(e$old_start, cumsum(c(1L, e$old_len))[seq_len(nrow(e))]) &&
        identical(e$new_start, cumsum(c(1L, e$new_len))[seq_len(nrow(e))]) &&
        all(e$old_len[e$op == "insert"] == 0) &&
        all(e$new_len[e$op == "delete"] == 0),
      "pair ",
      i
    )
  }
  prop$done()
})

test_that("the script is minimal on cases with a known distance", {
  d <- diff_vec(c("a", "b", "c"), c("a", "x", "c"))
  expect_identical(d$distance, 2L)
  expect_true(d$minimal)
  # Myers' own example: ABCABBA to CBABAC has distance 5.
  d <- diff_vec(strsplit("ABCABBA", "")[[1]], strsplit("CBABAC", "")[[1]])
  expect_identical(d$distance, 5L)
})

test_that("equality is match()'s", {
  expect_true(diff_identical(diff_vec(c(NA, 1), c(NA, 1))))
  expect_true(diff_identical(diff_vec(NaN, NaN)))
  expect_false(diff_identical(diff_vec(NA_real_, NaN)))
  expect_true(diff_identical(diff_vec(0, -0)))
  expect_false(diff_identical(diff_vec(0.1 + 0.2, 0.3)))
  expect_true(diff_identical(diff_vec(round(0.1 + 0.2, 6), round(0.3, 6))))
  latin1 <- iconv("café", "UTF-8", "latin1")
  expect_identical(Encoding(latin1), "latin1")
  expect_true(diff_identical(diff_vec(latin1, "café")))
  f1 <- factor(c("a", "b"), levels = c("a", "b"))
  f2 <- factor(c("a", "b"), levels = c("b", "a"))
  expect_true(diff_identical(diff_vec(f1, f2)))
  expect_true(diff_identical(diff_vec(f1, c("a", "b"))))
})

test_that("bytes are diffed as bytes", {
  d <- diff_vec(charToRaw("kitten"), charToRaw("sitting"))
  expect_identical(diff_apply(charToRaw("kitten"), d), charToRaw("sitting"))
  expect_identical(d$distance, 5L)
})

test_that("bad inputs are zudiff_input_error", {
  expect_error(diff_vec(1L, TRUE), class = "zudiff_input_error")
  expect_error(diff_vec(1L, 1), class = "zudiff_input_error")
  expect_error(diff_vec(list(1), list(1)), class = "zudiff_input_error")
  expect_error(diff_vec(1:3, raw(1)), class = "zudiff_input_error")
  err <- expect_error(diff_vec(sum, 1), class = "zudiff_input_error")
  expect_s3_class(err, "zudiff_error")
  expect_error(
    diff_apply(1:2, diff_vec(1:3, 1:3)),
    class = "zudiff_input_error"
  )
  expect_error(
    diff_vec(1:3, 1:3, algorithm = "histogram"),
    class = "zudiff_input_error"
  )
})

test_that("identical inputs take the shortcut and give the same script as the core", {
  withr::local_seed(9)
  for (type in supported_types) {
    p <- random_pair(type)
    x <- p$old
    y <- x[seq_along(x)]
    for (algorithm in c("myers", "patience")) {
      fast <- diff_vec(x, y, algorithm = algorithm)
      expect_true(diff_identical(fast))
      expect_identical(fast$minimal, algorithm == "myers")
      expect_identical(diff_apply(x, fast), y)
      slow <- zudiff:::diff_vec_impl(
        x,
        c(y, y[0]),
        algorithm,
        if (algorithm == "myers") 0L else 1L,
        -1
      )
      expect_identical(diff_edits(fast), diff_edits(slow))
    }
  }
})
