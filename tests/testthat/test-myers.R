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
  prop <- property()
  for (i in 1:500) {
    p <- random_pair("integer", max_len = 80L)
    prop$check(
      identical(
        diff_vec(p$old, p$new, max_cost = Inf)$distance,
        greedy_distance(p$old, p$new)
      ),
      "pair ",
      i
    )
  }
  prop$done()
})

test_that("a small cost limit still gives a correct script, marked not minimal", {
  withr::local_seed(4)
  prop <- property()
  seen_cut <- FALSE
  for (i in 1:300) {
    a <- sample.int(5L, 300L, replace = TRUE)
    b <- sample.int(5L, 300L, replace = TRUE)
    d <- diff_vec(a, b, max_cost = 3)
    prop$check(identical(diff_apply(a, d), b), "pair ", i, ": round trip")
    prop$check(
      d$distance >= reference_distance(a, b),
      "pair ",
      i,
      ": below minimal"
    )
    if (!d$minimal) {
      seen_cut <- TRUE
      e <- diff_edits(d)
      prop$check(
        identical(
          sum(e$old_len[e$op == "delete"]) + sum(e$new_len[e$op == "insert"]),
          d$distance
        ),
        "pair ",
        i,
        ": distance"
      )
    }
  }
  prop$done()
  expect_true(seen_cut)
})

test_that("the default cost limit is minimal on small inputs", {
  withr::local_seed(5)
  prop <- property()
  for (i in 1:200) {
    p <- random_pair("character", max_len = 60L)
    d <- diff_vec(p$old, p$new)
    prop$check(
      d$minimal && identical(d$distance, reference_distance(p$old, p$new)),
      "pair ",
      i
    )
  }
  prop$done()
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
  # Every element occurs on both sides, so none is discarded before the
  # search, and the search is long (two vectors with nothing in common are
  # now trivial: discarding leaves nothing to search).
  withr::local_seed(12)
  old <- sample.int(3L, 1e6, replace = TRUE)
  new <- sample.int(3L, 1e6, replace = TRUE)
  zudiff:::test_raise_after(5)
  res <- tryCatch(diff_vec(old, new, max_cost = Inf), interrupt = function(e) {
    "interrupted"
  })
  expect_identical(res, "interrupted")
  expect_true(diff_identical(diff_vec(1:3, 1:3)))
  expect_identical(diff_vec(c(1L, 2L), c(1L, 3L))$distance, 2L)
})

test_that("long equal runs, which the snakes follow in chunks, are diffed exactly", {
  withr::local_seed(10)
  for (i in 1:150) {
    n <- sample(c(63:65, 127:129, 200:700), 1)
    a <- as.raw(sample(0:255, n, replace = TRUE))
    b <- a
    at <- sample(n, sample(1:6, 1))
    b[at] <- as.raw((as.integer(b[at]) + 1L) %% 256L)
    if (i %% 3L == 0L) {
      b <- c(b[-(1:sample(1:5, 1))], as.raw(1:3))
    }
    d <- diff_vec(a, b, max_cost = Inf)
    expect_identical(diff_apply(a, d), b)
    expect_identical(d$distance, greedy_distance(a, b))
  }
})

test_that("Ctrl-C during a short diff, which does not catch it, still reaches R", {
  skip_on_os("windows")
  # 2 x 2000 elements: under the 4096 that catches Ctrl-C, long enough to
  # poll. R's own handler takes the signal and R acts on it at its next
  # check for interrupts, which Sys.sleep() is, so the diff itself finishes.
  withr::local_seed(13)
  a <- sample.int(3L, 2000, replace = TRUE)
  b <- sample.int(3L, 2000, replace = TRUE)
  zudiff:::test_raise_after(1)
  res <- tryCatch(
    {
      d <- diff_vec(a, b, max_cost = Inf)
      Sys.sleep(0.05)
      "not interrupted"
    },
    interrupt = function(e) "interrupted"
  )
  expect_identical(res, "interrupted")
  expect_identical(diff_vec(1:3, c(1L, 9L, 3L))$distance, 2L)
})
