# Diff two vectors

Computes the shortest edit script that turns `old` into `new`: which
runs of `old` are kept, deleted or inserted.

## Usage

``` r
diff_vec(old, new, algorithm = c("myers", "patience"), max_cost = NULL)
```

## Arguments

- old, new:

  Two vectors of the same type: logical, integer, double, complex,
  character or raw. A factor counts as a character vector of its labels.

- algorithm:

  The diff algorithm: `"myers"`, the default, or `"patience"`. Myers
  finds a shortest edit script. Patience first aligns the elements that
  occur exactly once on each side, then diffs the stretches between
  them, with Myers where a stretch has no such element. On text it keeps
  functions and blocks aligned where Myers may match stray braces and
  blank lines instead. Its scripts are not minimal in general, and the
  result always records `minimal = FALSE`.

- max_cost:

  The cost limit of Myers' search, which trades minimality for time.
  `NULL`, the default, follows GNU diff: about the square root of the
  input size, and at least 4096. `Inf` always finds a minimal script, in
  O((N + M) D) time for edit distance D. A smaller number gives up
  sooner on very different inputs; the script is still correct, but may
  not be minimal, which the result records.

  The limit counts the steps of each middle-snake search, as GNU diff
  does, not the edit distance of the whole script.

## Value

An object of class `zudiff`. Read it with
[`diff_edits()`](https://pedrobtz.github.io/zudiff/reference/diff_edits.md)
and
[`diff_identical()`](https://pedrobtz.github.io/zudiff/reference/diff_edits.md),
and apply it with
[`diff_apply()`](https://pedrobtz.github.io/zudiff/reference/diff_apply.md).

## Details

Two elements are equal when
[`match()`](https://rdrr.io/r/base/match.html) says so: `NA` equals
`NA`, `NaN` equals `NaN` but not `NA`, `0` equals `-0`, strings compare
after translation to a common encoding, and factors compare by label.
Doubles compare exactly; round them first for a tolerance, for example
`diff_vec(round(x, 6), round(y, 6))`. Raw vectors are compared byte by
byte.

## Examples

``` r
d <- diff_vec(c("a", "b", "c"), c("a", "x", "c"))
diff_edits(d)
#>       op old_start old_len new_start new_len
#> 1  equal         1       1         1       1
#> 2 delete         2       1         2       0
#> 3 insert         3       0         2       1
#> 4  equal         3       1         3       1
```
