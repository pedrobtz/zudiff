# Linear-space Myers, the cost limit and interrupts (design §6.3, §9).

test_that("the reference distance is right on cases worked by hand", {
  expect_identical(reference_distance(integer(), 1:3), 3L)
  expect_identical(reference_distance(c("a", "b", "c"), c("a", "x", "c")), 2L)
  expect_identical(
    reference_distance(
      strsplit("ABCABBA", "")[[1]],
      strsplit("CBABAC", "")[[1]]
    ),
    5L
  )
})

test_that("Myers with max_cost = Inf finds the minimal edit distance", {
  withr::local_seed(20261027)
  pairs <- if (exhaustive()) 1e4 else 1e3
  for (i in seq_len(pairs)) {
    a <- sample.int(3L, sample.int(201L, 1L) - 1L, replace = TRUE)
    b <- sample.int(3L, sample.int(201L, 1L) - 1L, replace = TRUE)
    d <- diff_vec(a, b, max_cost = Inf)
    if (d$distance != reference_distance(a, b) || !d$minimal) {
      fail(sprintf(
        "pair %d: distance %d, reference %d",
        i,
        d$distance,
        reference_distance(a, b)
      ))
    }
  }
  succeed()
})

test_that("the greedy reference agrees with linear-space Myers", {
  withr::local_seed(3)
  for (i in 1:500) {
    p <- random_pair("integer", max_len = 80L)
    expect_identical(
      diff_vec(p$old, p$new, max_cost = Inf)$distance,
      greedy_distance(p$old, p$new)
    )
  }
})

test_that("a small cost limit still gives a correct script, marked not minimal", {
  withr::local_seed(4)
  seen_cut <- FALSE
  for (i in 1:300) {
    a <- sample.int(5L, 300L, replace = TRUE)
    b <- sample.int(5L, 300L, replace = TRUE)
    d <- diff_vec(a, b, max_cost = 3)
    expect_identical(diff_apply(a, d), b)
    expect_gte(d$distance, reference_distance(a, b))
    if (!d$minimal) {
      seen_cut <- TRUE
      expect_identical(
        sum(diff_edits(d)$old_len[diff_edits(d)$op == "delete"]) +
          sum(diff_edits(d)$new_len[diff_edits(d)$op == "insert"]),
        d$distance
      )
    }
  }
  expect_true(seen_cut)
})

test_that("the default cost limit is minimal on small inputs", {
  withr::local_seed(5)
  for (i in 1:200) {
    p <- random_pair("character", max_len = 60L)
    d <- diff_vec(p$old, p$new)
    expect_true(d$minimal)
    expect_identical(d$distance, reference_distance(p$old, p$new))
  }
})

test_that("max_cost is checked", {
  expect_error(diff_vec(1:3, 1:3, max_cost = -1), class = "zudiff_input_error")
  expect_error(diff_vec(1:3, 1:3, max_cost = NA), class = "zudiff_input_error")
  expect_error(diff_vec(1:3, 1:3, max_cost = "a"), class = "zudiff_input_error")
  expect_error(diff_vec(1:3, 1:3, max_cost = 1:2), class = "zudiff_input_error")
  expect_true(diff_identical(diff_vec(1:3, 1:3, max_cost = 0)))
})

test_that("Ctrl-C stops a long diff, and the next call works", {
  skip_on_os("windows")
  old <- seq_len(1e6)
  new <- -seq_len(1e6)
  zudiff:::test_raise_after(5)
  res <- tryCatch(diff_vec(old, new, max_cost = Inf), interrupt = function(e) {
    "interrupted"
  })
  expect_identical(res, "interrupted")
  expect_true(diff_identical(diff_vec(1:3, 1:3)))
  expect_identical(diff_vec(c(1L, 2L), c(1L, 3L))$distance, 2L)
})
