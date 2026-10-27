# Patience diff (design §6.4).

test_that("applying a patience script to old gives new, for every type", {
  withr::local_seed(20261027)
  prop <- property()
  for (type in supported_types) {
    for (i in 1:200) {
      p <- random_pair(type)
      prop$check(
        round_trips(p$old, p$new, algorithm = "patience"),
        type,
        " pair ",
        i
      )
    }
  }
  prop$done()
})

test_that("patience round-trips on larger inputs with repeats and unique lines", {
  withr::local_seed(6)
  pairs <- if (exhaustive()) 2000 else 200
  for (i in seq_len(pairs)) {
    k <- sample(2:60, 1)
    a <- sample.int(k, sample.int(150, 1), replace = TRUE)
    b <- sample.int(k, sample.int(150, 1), replace = TRUE)
    if (!identical(diff_apply(a, diff_vec(a, b, algorithm = "patience")), b)) {
      fail(sprintf("pair %d does not round-trip", i))
    }
  }
  succeed()
})

test_that("patience results are marked not minimal", {
  d <- diff_vec(1:3, c(1L, 3L), algorithm = "patience")
  expect_false(d$minimal)
  expect_identical(d$algorithm, "patience")
  expect_true(diff_identical(diff_vec(
    letters,
    letters,
    algorithm = "patience"
  )))
})

test_that("with every element unique, patience is minimal", {
  withr::local_seed(7)
  prop <- property()
  for (i in 1:300) {
    a <- sample.int(80, sample.int(40, 1))
    b <- sample.int(80, sample.int(40, 1))
    d <- diff_vec(a, b, algorithm = "patience")
    prop$check(identical(d$distance, reference_distance(a, b)), "pair ", i)
  }
  prop$done()
})

test_that("patience moves a function as a block where Myers interleaves it", {
  f <- c_fixture()
  myers <- diff_edits(diff_vec(f$old, f$new))
  patience <- diff_edits(diff_vec(f$old, f$new, algorithm = "patience"))
  expect_gt(sum(myers$op != "equal"), sum(patience$op != "equal"))
  expect_identical(patience$op, c("delete", "equal", "insert"))
  expect_identical(patience$old_len, c(5L, 5L, 0L))
  expect_identical(patience$new_len, c(0L, 5L, 10L))
})

test_that("patience matches git diff --patience on the C fixture", {
  skip_if_not(git_available(), "git is not available")
  f <- c_fixture()
  d <- diff_vec(f$old, f$new, algorithm = "patience")
  expect_identical(zudiff_blocks(d), git_blocks(f$old, f$new, "--patience"))
})

test_that("patience's edit distance agrees with git's on random line files", {
  skip_if_not(git_available(), "git is not available")
  withr::local_seed(4)
  pairs <- if (exhaustive()) 300 else 50
  agree <- 0
  for (i in seq_len(pairs)) {
    k <- sample(3:40, 1)
    a <- paste0("l", sample.int(k, sample(5:60, 1), replace = TRUE))
    b <- paste0("l", sample.int(k, sample(5:60, 1), replace = TRUE))
    d <- diff_vec(a, b, algorithm = "patience")
    expect_identical(diff_apply(a, d), b)
    if (d$distance == blocks_distance(git_blocks(a, b, "--patience"))) {
      agree <- agree + 1
    }
  }
  # Tie-breaking differs between the two, so hunks need not match; the
  # distances do on nearly every pair (499 of 500 on 2026-10-27, git
  # 2.55.0, where the one exception was shorter in zudiff).
  expect_gte(agree / pairs, 0.95)
})

test_that("algorithm is checked", {
  expect_error(
    diff_vec(1:3, 1:3, algorithm = "histogram"),
    class = "zudiff_input_error"
  )
  expect_error(
    diff_vec(1:3, 1:3, algorithm = c("patience", "myers")),
    class = "zudiff_input_error"
  )
  expect_identical(diff_vec(1:3, 1:3)$algorithm, "myers")
})
