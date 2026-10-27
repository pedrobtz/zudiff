# Apply a diff

Applies the edit script of `d` to `old`: kept runs come from `old` and
inserted runs from the `new` that `d` was computed against.

## Usage

``` r
diff_apply(old, d)
```

## Arguments

- old:

  The vector the diff was computed from, or one of the same length.

- d:

  A `zudiff` object, from
  [`diff_vec()`](https://pedrobtz.github.io/zudiff/reference/diff_vec.md).

## Value

The vector `d` turns `old` into. For atomic vectors it is identical to
`new`; for factors, it combines `old`'s and `new`'s levels as
[`c()`](https://rdrr.io/r/base/c.html) does.

## Examples

``` r
old <- c("a", "b", "c")
new <- c("a", "x", "c", "d")
identical(diff_apply(old, diff_vec(old, new)), new)
#> [1] TRUE
```
