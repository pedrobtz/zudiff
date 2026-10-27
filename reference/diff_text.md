# Diff two strings line by line

Splits `old` and `new` into lines, keeping each line's ending, and diffs
the lines with
[`diff_vec()`](https://pedrobtz.github.io/zudiff/reference/diff_vec.md).

## Usage

``` r
diff_text(old, new, algorithm = c("myers", "patience"), max_cost = NULL)
```

## Arguments

- old, new:

  Two strings.

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

An object of class `zudiff`, whose elements are lines. Apply it to `old`
with
[`diff_apply()`](https://pedrobtz.github.io/zudiff/reference/diff_apply.md)
to get `new` back as one string.

## Details

Lines compare exactly, endings included, as `diff` and git compare them.
So a file with Windows line endings (`"\r\n"`) differs from the same
file with Unix ones (`"\n"`) on every line. A string that does not end
in a newline has a last line without one, which
[`diff_unified()`](https://pedrobtz.github.io/zudiff/reference/diff_unified.md)
marks with `\ No newline at end of file`.

## Examples

``` r
old <- "a\nb\nc\n"
new <- "a\nx\nc\n"
d <- diff_text(old, new)
cat(diff_unified(d))
#> --- old
#> +++ new
#> @@ -1,3 +1,3 @@
#>  a
#> -b
#> +x
#>  c
identical(diff_apply(old, d), new)
#> [1] TRUE
```
