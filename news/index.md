# Changelog

## zudiff 0.0.0.9000

- [`diff_vec()`](https://pedrobtz.github.io/zudiff/reference/diff_vec.md)
  computes the shortest edit script between two vectors of the same
  type, or two raw vectors byte by byte, with Myers’ algorithm. Equality
  is [`match()`](https://rdrr.io/r/base/match.html)’s.
- [`diff_edits()`](https://pedrobtz.github.io/zudiff/reference/diff_edits.md)
  lists its runs as 1-based starts and lengths,
  [`diff_identical()`](https://pedrobtz.github.io/zudiff/reference/diff_edits.md)
  says whether the inputs were equal, and
  [`diff_apply()`](https://pedrobtz.github.io/zudiff/reference/diff_apply.md)
  applies it.
- [`zudiff_info()`](https://pedrobtz.github.io/zudiff/reference/zudiff_info.md)
  reports the package version, and the Goose compiler commit and runtime
  interface hash the bundled C was generated with.
