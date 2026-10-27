# Information about zudiff

Reports the package version and the Goose compiler the bundled C was
generated with.

## Usage

``` r
zudiff_info()
```

## Value

A list of strings: `version`, the package version; `goose_commit`, the
Goose commit the C was generated at; and `goose_runtime`, that
compiler's runtime interface hash.

## Examples

``` r
zudiff_info()
#> $version
#> [1] "0.0.0.9000"
#> 
#> $goose_commit
#> [1] "e76d5c9f7f0a17d83c12a405fbb2513094d03985"
#> 
#> $goose_runtime
#> [1] "a5dbd11b6309"
#> 
```
