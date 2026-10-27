# zudiff 0.0.0.9000

* `diff_vec()` computes the shortest edit script between two vectors of
  the same type, or two raw vectors byte by byte, with Myers' algorithm.
  Equality is `match()`'s.
* `diff_edits()` lists its runs as 1-based starts and lengths,
  `diff_identical()` says whether the inputs were equal, and
  `diff_apply()` applies it.
* `zudiff_info()` reports the package version, and the Goose compiler
  commit and runtime interface hash the bundled C was generated with.
