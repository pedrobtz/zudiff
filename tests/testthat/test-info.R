test_that("zudiff_info() reports the package version and the Goose pin", {
  info <- zudiff_info()
  expect_type(info, "list")
  expect_identical(info$version, as.character(utils::packageVersion("zudiff")))
  expect_match(info$goose_commit, "^[0-9a-f]{40}$")
  expect_match(info$goose_runtime, "^[0-9a-f]+$")
})
