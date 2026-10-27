#' Information about zudiff
#'
#' Reports the package version. Later versions add the Goose compiler
#' commit the bundled C was generated with.
#'
#' @return A list with element `version`, a string.
#' @export
#' @examples
#' zudiff_info()
zudiff_info <- function() {
  list(version = as.character(utils::packageVersion("zudiff")))
}
