# Write a diff as a unified diff

Writes the hunks of a diff in the unified format of GNU diff, which
`patch` and `git apply` read.

## Usage

``` r
diff_unified(d, context = 3L, old_name = "old", new_name = "new")
```

## Arguments

- d:

  A `zudiff` object, from
  [`diff_vec()`](https://pedrobtz.github.io/zudiff/reference/diff_vec.md)
  or
  [`diff_text()`](https://pedrobtz.github.io/zudiff/reference/diff_text.md).

- context:

  The number of unchanged lines around each change.

- old_name, new_name:

  The file names for the `---` and `+++` headers.

## Value

One string: the unified diff, ending in a newline, or `""` when the two
inputs are identical.

## Details

For a
[`diff_text()`](https://pedrobtz.github.io/zudiff/reference/diff_text.md)
result, each line is written as it is, and a last line without a newline
is followed by `\ No newline at end of file`. For a
[`diff_vec()`](https://pedrobtz.github.io/zudiff/reference/diff_vec.md)
result, each element is written with
[`format()`](https://rdrr.io/r/base/format.html) as one line.

## Examples

``` r
d <- diff_text("a\nb\nc\n", "a\nx\nc\n")
cat(diff_unified(d, old_name = "a/file.txt", new_name = "b/file.txt"))
#> --- a/file.txt
#> +++ b/file.txt
#> @@ -1,3 +1,3 @@
#>  a
#> -b
#> +x
#>  c
```
