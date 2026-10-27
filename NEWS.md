# zudiff 0.0.0.9000

* `diff_vec()` computes the shortest edit script between two vectors of
  the same type, or two raw vectors byte by byte, with Myers' algorithm.
  Equality is `match()`'s. Myers runs in linear space, and `max_cost`
  trades minimality for time as GNU diff does; the result records whether
  it is minimal. Ctrl-C stops a long diff.
* `diff_text()` diffs two strings line by line, keeping line endings.
* `diff_hunks()` groups changes with context, and `diff_unified()` writes
  a unified diff that GNU `patch` and `git apply` apply. A `zudiff` object
  prints as one, capped at 50 lines.
* `patch_parse()` reads unified diffs, from `diff_unified()`, GNU diff or
  `git diff`, and `patch_apply()` applies one with exact context.
* On two versions of a text, lines that occur only on one side are set
  aside before the search, as GNU diff does, which keeps the script
  minimal and halves the time on typical edits; identical inputs skip the
  search.
* `diff_vec(algorithm = "patience")` aligns the elements that occur once
  on each side first, which keeps functions and blocks of text together.
* `diff_edits()` lists its runs as 1-based starts and lengths,
  `diff_identical()` says whether the inputs were equal, and
  `diff_apply()` applies it.
* Windows is supported.
* `zudiff_info()` reports the package version, and the Goose compiler
  commit and runtime interface hash the bundled C was generated with.
