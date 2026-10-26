# RFC 0045: `zudiff`, Myers and patience diff in R, written in Goose

Adopted from [RFC 0045](https://github.com/pedrobtz/packages/blob/main/rfcs/started/0045-zudiff-sequence-diff-in-goose.md)
on 2026-10-26. From here on this file is authoritative; the RFC is history.

- **Status:** Proposed. Merging this file adopts the design as the starting
  point for the package's own `.agents/design.md`; each decision in section
  13 stays the maintainer's until the package repository records it.
  D3, equality through `match()`, is the one most worth a second look.
- **Date:** 2026-10-26.
- **Packages:** `zudiff` (not yet created; crandb returns `not_found` and
  there is no `pedrobtz/zudiff` repository). No `Imports`. No `LinkingTo`.
  `Suggests: testthat`. Built by hand on `zugojson`'s pattern, without
  `zugoose` (D1). MIT for `zudiff`'s own code; the Goose runtime pieces
  copied from Goose's `runtime_impl.h` stay Apache-2.0.
- **Source:** `base-layer-candidates.md` §3.5, which this RFC replaces;
  the conversation of 2026-10-26 that named `zudiff` the right second user
  for `zugoose`; RFC 0044 §7 and §14; `diffobj` 0.3.6 (`ses()`,
  `ses_dat()`, `src/diff.c`, GPL-2 or GPL-3); Myers, "An O(ND) difference
  algorithm and its variations" (Algorithmica 1986); Cohen's patience diff
  as described for Bazaar and as implemented in git's `xdiff/xpatience.c`;
  the GNU diffutils manual on the unified format;
  [`calpeyser/goose-evaluations`](https://github.com/calpeyser/goose-evaluations)
  (Goose against C, C++ and Rust on JSON, YAML and jq trees), its
  [Goose discussion](https://github.com/aardappel/goose/discussions/51) and
  the [rapidyaml change](https://github.com/biojppm/rapidyaml/pull/675) it
  led to (§4.1). Nothing has been built.

## 1. What zudiff is

`zudiff` computes the shortest edit script between two sequences and hands
it back as data: which runs of the old sequence were kept, deleted or
inserted. The sequences are two vectors of the same atomic type, two raw
vectors compared byte by byte, or two strings compared line by line. From
the script it builds hunks with context, writes unified diffs, and applies
a script or a unified diff to the old sequence.

The algorithms are written in Goose and compiled to C on the maintainer's
machine by `tools/regenerate.sh`, as in `zugojson`. The package ships that
C; installing it needs a C compiler and nothing else.

The one-line statement that governs every decision below:

> **The edit script as data, exact equality as R defines it, and plain C
> on CRAN's machines.**

### 1.1 What zudiff is not

- **Not a presentation layer.** No colours, no side-by-side layout, no
  object pretty-printing. `waldo` and `diffobj` do that, and could sit on
  top of `zudiff`.
- **Not a merge tool.** Three-way merge is §14, not v0.1.0 (D8).
- **Not a structural diff.** Lists, data frames and nested objects are
  for the caller to flatten; `daffiz` and `zurds` do that for theirs.
- **Not a C library for siblings.** Goose code is reached through `.Call`
  only (RFC 0044 §1.1), so `zudiff` has no C API (D2).

### 1.2 Where it sits among existing packages

The sketch said R has nothing underneath `waldo` and `diffobj` that exposes
the script. That was wrong. `diffobj::ses()` returns a shell-style script
(`"2c2" "5a6"`) and `ses_dat()` a data frame of matches, inserts and
deletes, both from a C Myers implementation derived from Michael Allen's
`libmba` diff. What is true:

- `diffobj` is GPL, so a package that wants an MIT or Apache licence
  cannot vendor its core, and pulling it in brings its presentation
  machinery as `Imports`.
- It compares character vectors. Bytes and typed vectors go through
  `as.character()` first.
- It has Myers only, with a `max.diffs` cut-off. No patience diff, no
  unified output, no patch application.

`waldo` uses `diffobj` for its sequence comparison. Base R's `tools`
package compares files by shelling out to `diff`, which CRAN's Windows
machines do not have.

`zudiff`'s case is the combination: MIT, bytes and typed vectors without
a detour through strings, patience diff, unified diffs both ways, and the
family's conventions.

## 2. Scope

**In v0.1.0:**

- Diff of two atomic vectors of the same type: logical, integer, double,
  complex, character, factor, and raw (§6).
- Diff of two strings as lines (`diff_text()`), keeping line endings and
  recording a missing final newline.
- Myers' algorithm in its linear-space form, with common prefix and suffix
  trimmed first, and a cost limit that trades minimality for time (§6.3).
- Patience diff, with Myers for the stretches between anchors (§6.4).
- Hunks with configurable context; unified-diff text in and out.
- Applying an edit script, and applying a unified diff with exact context
  (no fuzz).
- Interrupts from long diffs, through the runtime's own
  `zudiff_interrupted()` (§6.3).
- A Windows half of the copied runtime (D10).

**Not in v0.1.0** (§14): three-way merge, word and character diff inside
changed lines, histogram diff, patch fuzz, diffs of directories, a C API.

## 3. Position in the `zu*` family

| | zudiff |
| --- | --- |
| Role | R API |
| R prefix | `diff_`, and `patch_` for unified-diff input |
| Info function | `zudiff_info()` |
| Root condition class | `zudiff_error` |
| Public C prefix | none; internal glue uses `zudiff_`, the runtime `gs_` |
| From C | no (D2) |
| Hides symbols | yes (R3, `tools/check-symbols.sh` as in `zugojson`) |
| Vendored code | Goose runtime pieces in `src/goose_vendor.c` (Apache-2.0) |
| `Depends: R` | 4.1 (R2) |
| Language | en-GB (R2) |

**Relationships:**

- **`zugojson`**: the pattern. `zudiff` copies its runtime
  (`goose_r_runtime.{c,h}`), `tools/regenerate.sh`, `tools/check-symbols.sh`
  and the `goose.yaml` workflow, and writes its own `.Call` glue. Where
  `zudiff` changes the copied runtime (interrupts, D10's Windows half),
  the change is recorded in `tools/goose/PROVENANCE`.
- **`zugoose`** (RFC 0044): not used (D1). `zudiff` is an independent
  second hand-built Goose package. What it learns (borrowed vector
  arguments, raw results, interrupts, Windows) is reported to `zugoose` as
  issues. Moving to `use_zugoose()` later is §14.
- **`daffiz`**: aligns rows and cells of two tables. It calls `diff_vec()`
  on row keys.
- **`zurds`**: diffs two serialized objects. It calls `diff_vec()` on
  byte streams and on flattened values.
- **`zutoml`, `zuyaml`**: `Suggests: zudiff` in their round-trip tests,
  where a failing comparison prints a unified diff of the two documents.
- **`zupdf`**: checks that an incremental update only appends, with
  `diff_vec()` over the two files' bytes.
- **This repository**: the dashboard script can show what changed in
  `readme.md` between runs.

## 4. Architecture

Two layers, split at a hand-written `.Call` boundary.

1. **The core** (`tools/goose/zudiff.goose`, compiled into
   `src/zudiff_goose.c` by `tools/regenerate.sh` at the commit in
   `tools/goose/PIN`). Two exported functions:

   ```goose
   export fn diff_ids(a: const i32[:], b: const i32[:],
                      algorithm: i32, max_cost: i64) -> const u8[:]
   export fn diff_bytes(a: const u8[:], b: const u8[:],
                        algorithm: i32, max_cost: i64) -> const u8[:]
   ```

   Both return the packed script of §7. Neither sees an R object, an `NA`
   or a string: by the time values reach Goose they are integer ids or
   bytes, and equality is `==`.

   The glue (`src/zudiff_r.c`) borrows the integer or raw vectors as
   slices without copying, calls each export inside `goose_r_run()`, and
   copies the result into a raw vector only after the run returns. The
   runtime (`src/goose_r_runtime.{c,h}`) is `zugojson`'s, with the
   changes §6.3 and D10 need.
2. **The R layer** (`R/`). Turns any supported vector into ids (§6.1),
   calls the generated wrapper, unpacks the script into an object of class
   `zudiff`, and does everything that is formatting rather than search:
   hunks, unified text, patch parsing and application.

The split puts the quadratic-in-the-worst-case work in compiled code and
leaves the linear work, where R's vectorised functions are fast enough,
in R. Patch application is in R because it is a sequence of `c()` and
indexing over runs, linear in the output.

### 4.1 Memory layout in the core

The [Goose evaluations](https://github.com/calpeyser/goose-evaluations)
are the reference for how the core should hold its memory. Their
[json](https://github.com/calpeyser/goose-evaluations/tree/main/json),
[yaml](https://github.com/calpeyser/goose-evaluations/tree/main/yaml) and
[jq](https://github.com/calpeyser/goose-evaluations/tree/main/jq)
programs are worth reading before Stage 1. There Goose matches or beats
yyjson, rapidyaml and jaq because of data layout: one pool per structure,
values only as large as they need to be, 4-byte links, and nothing freed
piece by piece. Its weak case is an array grown one step at a time, as in
jq's `reduce`. The
[rapidyaml change](https://github.com/biojppm/rapidyaml/pull/675) shows
the same lessons in C. It sizes the node array from the input and never
writes a slot before a node uses it. On real manifests that cut parse time
by up to half.

For `zudiff` that means:

- **Size buffers from the input, once.** Runs number at most N + M (§7),
  and Myers' diagonal array is bounded by the cost limit (§6.3), so the
  script buffer and the search arrays are allocated up front. Nothing
  grows in a loop.
- **Don't clear what may not be read.** Write a slot when the search
  reaches it, not when the buffer is allocated.
- **Keep records small.** Ids, positions and lengths are `i32` (§7, §8),
  and patience diff's occurrence counts are flat arrays indexed by id
  (§6.4), not a hash table.

§10's benchmarks check whether these choices pay off. The evaluations'
numbers are evidence about Goose, not targets for `zudiff`.

## 5. Public R API (v0.1.0 shape)

```r
# computing a diff
diff_vec(old, new, algorithm = c("myers", "patience"), max_cost = NULL)
diff_text(old, new, algorithm = c("myers", "patience"), max_cost = NULL)

# reading it
diff_edits(d)                  # data frame: op, old_from, old_to, new_from, new_to
diff_hunks(d, context = 3L)    # list of hunks, each with its edits
diff_identical(d)              # TRUE when the script has no inserts or deletes

# unified diffs
diff_unified(d, context = 3L, old_name = "old", new_name = "new")
patch_parse(text)              # unified diff text to a list of file patches
patch_apply(old, patch)        # exact context, no fuzz

# applying a script
diff_apply(old, d)

zudiff_info()
```

A `zudiff` object holds the two inputs (R's copy-on-modify means no copy),
the runs, the algorithm, and whether the result is minimal. It prints as a
unified diff with three lines of context, truncated to the console width.

`diff_text()` takes two strings, splits each into lines with their endings
kept, and diffs the lines. A string not ending in a newline gets the
unified format's `\ No newline at end of file` marker. `diff_unified()` on
a `diff_vec()` result formats each element with `format()` as one line.

## 6. Semantics

### 6.1 Equality

Two elements are equal when `match()` says so. The R layer computes

```r
ids <- match(c(old, new), unique(c(old, new)))
```

and passes the first `length(old)` ids and the rest to `diff_ids`. That
makes `match()`'s rules `zudiff`'s rules, documented once:

- `NA` equals `NA`, and `NaN` equals `NaN`; `NA` and `NaN` differ.
- `0` and `-0` are equal.
- Strings compare after translation to a common encoding, so the same
  text in Latin-1 and UTF-8 is equal.
- Factors compare by level label, not by code, so two factors with the
  same labels in a different level order diff correctly.

`old` and `new` must have the same type after the usual factor-to-character
rule; a logical against an integer is a `zudiff_input_error`, not a silent
coercion. Raw vectors skip `match()` and go to `diff_bytes` directly,
since a byte is its own id.

### 6.2 The edit script

An edit script is a sequence of runs. Each run is an operation (`equal`,
`delete`, `insert`), a start in `old`, a start in `new`, and a length.
Runs are maximal: no two adjacent runs share an operation. Where a
deletion and an insertion are adjacent, the deletion comes first, as in
unified diffs. Applying the script to `old` gives `new` exactly, for every
input; that is the property the tests rest on (§9).

### 6.3 Myers

The default. Common prefix and suffix are trimmed first, which is most of
the work for the usual input of two versions of one file. The middle is
diffed with the linear-space divide and conquer of Myers' §4b: find the
middle snake, recurse on each side. Memory is O(N + M) on Goose's data
stacks.

The answer is minimal unless the cost limit is reached. `max_cost`, an
edit distance, defaults to `max(256, sqrt(N + M) * 8)` when `NULL`. When
the middle-snake search passes it, the search stops and splits at the
furthest-reaching diagonal found so far, as GNU diff does. The result is
still a correct script, and the object records `minimal = FALSE`.
`max_cost = Inf` always finds the minimum, at O((N + M) D) time.

The outer loop over D calls `zudiff_interrupted()` every 2¹⁰ steps, so
Ctrl-C stops a long diff. It is an `extern fn` into the runtime, the way
`zugojson` reaches `zugojson_strtod`. The runtime installs a `SIGINT`
handler that sets a flag for the duration of `goose_r_run()` only. When the
flag is set, the core fails the call, the stacks rewind, and the glue
re-raises the interrupt in R after the run. `zugojson`'s runtime has none
of this; it is the first change `zudiff` makes to the copy, and it mirrors
RFC 0044 §6.2 so that a later move to `zugoose` changes only the name.

### 6.4 Patience

For text, where Myers aligns braces and blank lines and readers want
functions aligned. Elements that occur exactly once in each side become
anchors; the longest increasing subsequence of anchors, by patience
sorting, fixes the alignment; each stretch between anchors is diffed
recursively, and with Myers when it has no unique elements. Since ids are
small integers below N + M, occurrence counts live in two arrays, not a
hash table.

Patience is not minimal in general, so a patience result records
`minimal = FALSE`.

### 6.5 Unified diffs

Output follows the GNU diffutils description: `---` and `+++` headers,
`@@ -l,s +l,s @@` hunk headers, a hunk's context merged with the next when
they overlap, and the no-newline marker. Input accepts the same, plus
git's `diff --git` and `index` lines, which it skips. A patch whose
context lines do not match `old` exactly at the stated position is a
`zudiff_patch_error` naming the hunk; v0.1.0 does not search for an
offset (D7).

## 7. The packed script

RFC 0044 §7 lets an export return a scalar or `const u8[:]` and nothing
else at the pin. A script is a vector of runs, so the core packs it into
bytes and the R layer unpacks it:

- A header of four little-endian `i32`: format version (1), number of
  runs, minimal flag, and the edit distance found.
- Then one record per run of four little-endian `i32`: operation (0
  equal, 1 delete, 2 insert), start in `old`, start in `new`, length.

The R layer reads it with one `readBin(x, "integer", n, size = 4, endian =
"little")` and a `matrix()`. Sixteen bytes per run, and runs number at
most N + M. The format version lets the R layer refuse a core it does not
understand.

When Goose allows numeric vector results from an export (Goose spec
§7.11 forbids them at the pin), the export returns `const i32[:]` and the
packing goes. The R API does not change.

## 8. Errors

Every condition inherits from `zudiff_error`; tests assert on class.

| Class | Raised when |
| --- | --- |
| `zudiff_input_error` | types differ, an unsupported type, a long vector |
| `zudiff_runtime_error` | a Goose failure the core did not raise itself |
| `zudiff_patch_error` | a unified diff does not parse or does not match |

These follow `zugojson`'s classes, which are also the ones `zugoose`
would generate (RFC 0044 §8). The core raises nothing of its own: inputs
are checked in R, so any Goose failure is a `zudiff_runtime_error`, and
the glue returns its message for R to raise after the run. Inputs longer
than 2³¹ − 1 are an input error: ids and positions are `i32`.

## 9. Testing

`testthat` 3e, one file per section of §6.

- **The round trip.** For every test input, `diff_apply(old, d)` is
  identical to `new`, and so is `patch_apply(old, patch_parse(
  diff_unified(d)))`. A property test draws random vectors over small
  alphabets, of every type in §6.1 and with `NA` and `NaN` mixed in, and
  checks both.
- **Minimality.** With `max_cost = Inf`, Myers' edit distance equals the
  one from an O(NM) dynamic-programming reference written in R in the test
  helpers, on 10⁴ random pairs of length up to 200.
- **Interoperation.** Where the CI image has them: GNU `patch` applies
  `diff_unified()`'s output to `old` and gives `new`, and `patch_apply()`
  applies the output of `git diff --no-index`, `--minimal` and
  `--patience`, to give `new`. Hunks need not match git's character for
  character, since tie-breaking differs; the edit distance from `--minimal`
  must match Myers' exactly.
- **Equality.** A table test for each rule of §6.1.
- **The runtime.** `zugojson`'s `test-runtime.R` comes with the copied
  runtime: a failure rewinds the stacks and the next call succeeds.
  `zudiff` adds an interrupt test on a pair of 10⁶-element vectors with
  no common elements and `max_cost = Inf`.
- **The generated C.** The `goose.yaml` workflow rebuilds Goose at the
  pin and fails if `tools/regenerate.sh --verify` finds a difference.
- **From the family** (R3): `test-abi.R`, that the shared object exports
  `R_init_zudiff` only.

## 10. Performance targets

Measured by `tools/run-benchmarks`, recorded in `.agents/benchmarks.md`,
with the baseline run in Stage 0 before any `zudiff` code exists.

| Operation | Target |
| --- | --- |
| 10⁵-line texts, 1 % of lines changed | 5× faster than `diffobj::ses()` |
| same, `match()` share of the total | recorded |
| two 10 MB raw vectors, 100 scattered edits | under 100 ms |
| two identical 10⁶-element vectors | under 10 ms beyond `match()` |
| empty call overhead | within 10 % of `zugojson`'s empty call |

The 5× is a guess until Stage 0 measures `diffobj`; if it is already that
fast, the target becomes parity and the case rests on §1.2's other points.

## 11. Roadmap

Stages run the quick CI profile unless marked `full`. Each is one pull
request, merged on green.

| Stage | Delivers | Exit criterion |
| --- | --- | --- |
| 0 (`full`) | `zugojson`'s runtime and scripts, CI, baseline | §10 baseline |
| 1 | greedy Myers core, §7 packing, `diff_vec()`, §6.1 | round trip; §6.1 |
| 2 | linear space, cost limit, interrupts | minimality test; interrupt test |
| 3 | patience | round trip; `--patience` interop |
| 4 | `diff_text()`, hunks, `diff_unified()`, printing | GNU `patch` interop |
| 5 | `patch_parse()`, `patch_apply()`, benchmarks | §9 passes; §10 recorded |
| 6 (`full`) | Windows runtime (D10) | §9 on the Windows leg |
| 7 (`full`) | README, article, release preparation | §12 |

Stage 0 is `full` because it brings the first compiled code: a longjmp out
of Goose and `PROT_NONE` stack guards.

Stage 1's greedy Myers uses O((N + M) D) memory; Stage 2 replaces it and
keeps it as the test reference for the linear-space version.

## 12. Acceptance criteria for v0.1.0

- Every behaviour in §6, §7 and §8 has a passing test.
- The round-trip property holds on 10⁵ generated pairs across all types.
- Myers with `max_cost = Inf` matches the reference edit distance on every
  generated pair.
- `tools/regenerate.sh --verify` passes in CI against `zudiff`'s pin, and
  `tools/check-symbols.sh` finds no forbidden symbol.
- `R CMD check --as-cran` is clean on all r-actions legs, Windows
  included; no `Imports`.
- Ten stages in the roadmap. A stage that needs a second pull request
  moves scope to §14, not the release.

## 13. Decisions

Marked **(M)** when the maintainer decided it in the conversation and
**(C)** when this RFC decides it and the maintainer may overturn it.

- **D1 (M, revised 2026-10-26).** `zudiff` is written in Goose and built
  by hand on `zugojson`'s pattern, independently of `zugoose`, and starts
  now. The RFC first had it wait for `zugoose` v0.1.0 as its second user.
  The maintainer chose to build it independently and see how that works.
  Only the glue and the runtime would come from `zugoose`; the algorithms
  and the R layer do not depend on it. The cost is a second hand-copied
  runtime, the duplication RFC 0044 exists to end. What `zudiff` learns
  goes to `zugoose` as issues, and moving to `use_zugoose()` is §14.
- **D2 (C).** No C API. Siblings call R functions. A sibling that needs
  diffs from its own C code is a reason to revisit, and the answer would be
  a C port of the core, not reaching into Goose.
- **D3 (C).** Equality is `match()`'s, applied in R before the core runs,
  and the core diffs integer ids. This answers the sketch's open question
  on hashing: R's own hashed `match()` does it, collisions are resolved by
  `match()`, and `NA`, `NaN`, signed zero, encodings and factors behave as
  R users already expect. The cost is one pass and one `c()` copy in R,
  which §10 measures. The alternative, hashing in Goose, needs a hash of
  doubles and strings that reproduces R's equality, and the strings cannot
  reach Goose as a vector at the pin anyway.
- **D4 (C).** The script is packed into bytes (§7) until Goose exports
  can return integer vectors.
- **D5 (C).** Myers with a cost limit by default, minimal on request, and
  the result says which it is.
- **D6 (C).** Patience diff is in v0.1.0; histogram diff is not (§14).
  Patience is the variant readers ask for, and it reuses Myers for the
  gaps.
- **D7 (C).** Patch application requires exact context. Fuzz and offset
  search are §14.
- **D8 (C).** No three-way merge in v0.1.0.
- **D9 (C).** Hunks, unified text and patch application are in R, not
  Goose. They are linear, string-heavy, and need R's encodings.
- **D10 (C).** Windows blocks v0.1.0. `zugojson`'s runtime stops the build
  on Windows with `#error`, so Stage 6 writes the Windows half:
  `VirtualAlloc` with `PAGE_NOACCESS` for the stack gap, a vectored
  exception handler for the fault, and a console control handler for
  Ctrl-C, as RFC 0044 §6.2 describes. If `zugoose`'s Windows stage lands
  first, Stage 6 copies that instead (Q5).

## 14. Later versions, in the order they are expected

- **Integer vector results** from the core, when Goose allows them,
  replacing §7's packing.
- **Moving to `zugoose`**: replace the hand-written glue, runtime and
  scripts with `use_zugoose()`'s output, with the test suite unchanged,
  once `zugoose` v0.1.0 covers borrowed vectors, raw results, interrupts
  and Windows.
- **Word and character diff** inside changed lines, for `daffiz`'s cells
  and for display.
- **Histogram diff**, git's refinement of patience, if users ask.
- **Patch fuzz and offsets**, as GNU `patch` does.
- **Three-way merge** with conflict markers.
- **Diffs of files and directories**, with `zufs` once it exists.

## 15. Open questions

- **Q1.** Is the `max_cost` default right? GNU diff and git use different
  heuristics; Stage 2 compares the three on the benchmark corpus.
- **Q2.** Should `diff_vec()` on doubles offer a tolerance, as `waldo`
  does? A tolerance breaks transitivity, and Myers assumes it; this RFC
  says no and leaves rounding to the caller.
- **Q3.** Should `diff_text()` normalise line endings (`\r\n` against
  `\n`)? This RFC treats them as different, as `diff` does, with an
  argument to strip them deferred.
- **Q4.** Is v0.1.0 a CRAN submission or a GitHub release? The board's
  `CRAN intent` field records the answer; this RFC assumes `Planned`,
  since `zudiff` is a runtime package with users, unlike `zugoose`.
- **Q5.** For Windows (D10), does `zudiff` write its own runtime half, or
  wait for `zugoose`'s Stage 5 and copy it? Decide when `zudiff` reaches
  Stage 6, depending on where `zugoose` is.

## 16. What this RFC does not decide

The print method's truncation rule, the names of the hunk object's
fields, whether `diff_edits()` uses 1-based inclusive ranges or start and
length, and the article's examples.
