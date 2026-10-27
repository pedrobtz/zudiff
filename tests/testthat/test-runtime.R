# The Goose runtime copied from zugojson: a runtime failure must be an R
# error, and Goose must keep working afterwards.

test_that("a Goose bounds-check failure is a runtime error", {
  expect_identical(probe_index(1), 20)
  err <- expect_error(probe_index(7), class = "zudiff_runtime_error")
  expect_s3_class(err, "zudiff_error")
})

test_that("Goose keeps working after many runtime failures", {
  for (k in 1:1000) {
    try(probe_index(7), silent = TRUE)
  }
  expect_identical(probe_index(2), 30)
  expect_identical(probe_sum(1:10), 55)
})

test_that("R's own error handling still works after Goose calls", {
  probe_sum(1:3)
  try(probe_index(7), silent = TRUE)
  f <- function(n) f(n + 1)
  res <- tryCatch(f(1), error = function(e) "caught")
  expect_identical(res, "caught")
})

test_that("an integer vector reaches Goose borrowed and whole", {
  expect_identical(probe_sum(integer()), 0)
  x <- c(.Machine$integer.max, .Machine$integer.max, -5L)
  expect_identical(probe_sum(x), 2 * .Machine$integer.max - 5)
})

test_that("a failure rewinds the data stacks", {
  base <- stack_used()
  expect_identical(probe_stack(1e5, FALSE), 99999)
  expect_identical(stack_used(), base)
  for (k in 1:10) {
    expect_error(probe_stack(1e5, TRUE), class = "zudiff_runtime_error")
    expect_identical(stack_used(), base)
  }
  expect_identical(probe_stack(10, FALSE), 9)
})
