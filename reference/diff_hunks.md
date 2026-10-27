# Hunks of a diff

Groups the changes of a diff into hunks, each with up to `context`
unchanged elements around it, as a unified diff shows them. Changes
closer together than twice the context share one hunk.

## Usage

``` r
diff_hunks(d, context = 3L)
```

## Arguments

- d:

  A `zudiff` object, from
  [`diff_vec()`](https://pedrobtz.github.io/zudiff/reference/diff_vec.md)
  or
  [`diff_text()`](https://pedrobtz.github.io/zudiff/reference/diff_text.md).

- context:

  The number of unchanged elements to keep on each side of a change.

## Value

A list of hunks. Each hunk is a list with `old_start`, `old_len`,
`new_start` and `new_len`, the range it covers in each input as in
[`diff_edits()`](https://pedrobtz.github.io/zudiff/reference/diff_edits.md),
and `edits`, its rows of
[`diff_edits()`](https://pedrobtz.github.io/zudiff/reference/diff_edits.md),
with the unchanged runs at its ends cut to the context.

## Examples

``` r
d <- diff_vec(1:20, c(1:4, 99L, 6:20))
diff_hunks(d, context = 2)
#> [[1]]
#> [[1]]$old_start
#> [1] 3
#> 
#> [[1]]$old_len
#> [1] 5
#> 
#> [[1]]$new_start
#> [1] 3
#> 
#> [[1]]$new_len
#> [1] 5
#> 
#> [[1]]$edits
#>       op old_start old_len new_start new_len
#> 1  equal         3       2         3       2
#> 2 delete         5       1         5       0
#> 3 insert         6       0         5       1
#> 4  equal         6       2         6       2
#> 
#> 
```
