test_that("zudiff_info() reports the package version", {
  info <- zudiff_info()
  expect_type(info, "list")
  expect_identical(info$version, as.character(utils::packageVersion("zudiff")))
})
