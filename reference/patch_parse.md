# Read a unified diff

Parses unified diff text, as
[`diff_unified()`](https://pedrobtz.github.io/zudiff/reference/diff_unified.md),
GNU `diff -u` and `git diff` write it, into one patch per file.

## Usage

``` r
patch_parse(text)
```

## Arguments

- text:

  The unified diff, as one string.

## Value

A list of file patches, each a list with `old_name`, `new_name` and
`hunks`. Each hunk is a list with `old_start`, `old_len`, `new_start`
and `new_len`, as in the `@` header, and `lines`, a data frame with `op`
(`"equal"`, `"delete"` or `"insert"`) and `text`, the line with its
ending. A line followed by `\ No newline at end of file` has no ending.

## Details

Lines before a file's `---` header that are not part of a hunk are
skipped, such as git's `diff --git` and `index` lines. A timestamp after
a tab in the `---` and `+++` headers is dropped. A hunk must have
exactly the lines its `@` header counts.

## Examples

``` r
d <- diff_text("a\nb\nc\n", "a\nx\nc\n")
p <- patch_parse(diff_unified(d))
p[[1]]$hunks[[1]]$lines
#>       op text
#> 1  equal  a\n
#> 2 delete  b\n
#> 3 insert  x\n
#> 4  equal  c\n
```
