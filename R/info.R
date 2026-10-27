#' Information about zudiff
#'
#' Reports the package version and the Goose compiler the bundled C was
#' generated with.
#'
#' @return A list of strings: `version`, the package version;
#'   `goose_commit`, the Goose commit the C was generated at; and
#'   `goose_runtime`, that compiler's runtime interface hash.
#' @export
#' @examples
#' zudiff_info()
zudiff_info <- function() {
  goose <- .Call(zudiff_c_goose_info)
  list(
    version = as.character(utils::packageVersion("zudiff")),
    goose_commit = goose[[1]],
    goose_runtime = goose[[2]]
  )
}
