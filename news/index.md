# Changelog

## zudiff 0.0.0.9000

- [`diff_vec()`](https://pedrobtz.github.io/zudiff/reference/diff_vec.md)
  computes the shortest edit script between two vectors of the same
  type, or two raw vectors byte by byte, with Myers’ algorithm. Equality
  is [`match()`](https://rdrr.io/r/base/match.html)’s. Myers runs in
  linear space, and `max_cost` trades minimality for time as GNU diff
  does; the result records whether it is minimal. Ctrl-C stops a long
  diff.
- [`diff_text()`](https://pedrobtz.github.io/zudiff/reference/diff_text.md)
  diffs two strings line by line, keeping line endings.
- [`diff_hunks()`](https://pedrobtz.github.io/zudiff/reference/diff_hunks.md)
  groups changes with context, and
  [`diff_unified()`](https://pedrobtz.github.io/zudiff/reference/diff_unified.md)
  writes a unified diff that GNU `patch` and `git apply` apply. A
  `zudiff` object prints as one, capped at 50 lines.
- `diff_vec(algorithm = "patience")` aligns the elements that occur once
  on each side first, which keeps functions and blocks of text together.
- [`diff_edits()`](https://pedrobtz.github.io/zudiff/reference/diff_edits.md)
  lists its runs as 1-based starts and lengths,
  [`diff_identical()`](https://pedrobtz.github.io/zudiff/reference/diff_edits.md)
  says whether the inputs were equal, and
  [`diff_apply()`](https://pedrobtz.github.io/zudiff/reference/diff_apply.md)
  applies it.
- [`zudiff_info()`](https://pedrobtz.github.io/zudiff/reference/zudiff_info.md)
  reports the package version, and the Goose compiler commit and runtime
  interface hash the bundled C was generated with.
