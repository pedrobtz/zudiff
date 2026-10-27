# Read a diff

`diff_edits()` lists the runs of an edit script. `diff_identical()` says
whether the two inputs were equal.

## Usage

``` r
diff_edits(d)

diff_identical(d)
```

## Arguments

- d:

  A `zudiff` object, from
  [`diff_vec()`](https://pedrobtz.github.io/zudiff/reference/diff_vec.md).

## Value

`diff_edits()`: a data frame with columns `op`, `old_start`, `old_len`,
`new_start` and `new_len`. `diff_identical()`: `TRUE` or `FALSE`.

## Details

Each run is kept (`"equal"`), deleted or inserted. Ranges are a 1-based
start and a length, so `x[seq.int(start, length.out = len)]` selects a
run's elements. A delete has `new_len` 0 and an insert `old_len` 0;
their empty side's start is the position the run sits before. Adjacent
runs never share an operation, and a delete comes before an adjacent
insert.

## Examples

``` r
d <- diff_vec(1:5, c(1:2, 9L, 4:5))
diff_edits(d)
#>       op old_start old_len new_start new_len
#> 1  equal         1       2         1       2
#> 2 delete         3       1         3       0
#> 3 insert         4       0         3       1
#> 4  equal         4       2         4       2
diff_identical(d)
#> [1] FALSE
```
