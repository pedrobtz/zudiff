# Apply a unified diff

Applies a patch to `old`, a string. Every hunk must match `old` exactly
where its header says: its unchanged and deleted lines, endings
included, must be the lines of `old` at that position. There is no fuzz
and no search for an offset; a hunk that does not match is an error
naming it.

## Usage

``` r
patch_apply(old, patch)
```

## Arguments

- old:

  The text the patch was made from, as one string.

- patch:

  A unified diff: one string, or the result of
  [`patch_parse()`](https://pedrobtz.github.io/zudiff/reference/patch_parse.md),
  or one file patch from it. It must hold one file patch, or none, which
  leaves `old` as it is.

## Value

The patched text, as one string.

## Examples

``` r
old <- "a\nb\nc\n"
new <- "a\nx\nc\n"
patch <- diff_unified(diff_text(old, new))
identical(patch_apply(old, patch), new)
#> [1] TRUE
```
