# zudiff: roadmap

Status: draft 2026-10-26. Implements [design.md](design.md).
Target: v0.1.0, the first CRAN release (design Q4 recommends CRAN).
Tracking: [v0.1.0 (#1)](https://github.com/pedrobtz/zudiff/issues/1), with
one sub-issue per stage;
[CRAN-submission (#12)](https://github.com/pedrobtz/zudiff/issues/12).

The design's §11 has eight stages. This roadmap keeps their order and
splits two of them to fit the portfolio's brackets. Design stage 0 becomes
Stage 0 (package identity and CI) and Stage 1 (the Goose toolchain and the
copied runtime). Design stage 7 becomes Stage 8 (`Full CI`) and Stage 9
(readiness, with the README and the article). Each stage is still one pull
request, as §12 requires; scope that needs a second one moves to "After
0.1.0".

Until Stage 7 the package is POSIX only, as `zugojson` is: the copied
runtime stops the build on Windows with `#error`. `DESCRIPTION` says
`OS_type: unix` and the R CMD check caller drops its Windows runners until
then.

## Stages

| Stage | Title | CI | Issue | Pull request | Done |
| --- | --- | --- | --- | --- | --- |
| 0 | [Package identity](#stage-0--package-identity) | quick | [#2](https://github.com/pedrobtz/zudiff/issues/2) | [#14](https://github.com/pedrobtz/zudiff/pull/14) | 2026-10-27 |
| 1 | [Goose toolchain and runtime](#stage-1--goose-toolchain-and-runtime) | full | [#3](https://github.com/pedrobtz/zudiff/issues/3) | [#15](https://github.com/pedrobtz/zudiff/pull/15) | 2026-10-27 |
| 2 | [Greedy Myers and diff_vec()](#stage-2--greedy-myers-and-diff_vec) | quick | [#4](https://github.com/pedrobtz/zudiff/issues/4) | [#16](https://github.com/pedrobtz/zudiff/pull/16) | 2026-10-27 |
| 3 | [Linear space, cost limit and interrupts](#stage-3--linear-space-cost-limit-and-interrupts) | quick | [#5](https://github.com/pedrobtz/zudiff/issues/5) | [#17](https://github.com/pedrobtz/zudiff/pull/17) | 2026-10-27 |
| 4 | [Patience diff](#stage-4--patience-diff) | quick | [#6](https://github.com/pedrobtz/zudiff/issues/6) | | 2026-10-27 |
| 5 | [Text, hunks and unified output](#stage-5--text-hunks-and-unified-output) | quick | [#7](https://github.com/pedrobtz/zudiff/issues/7) | | |
| 6 | [Patches and benchmarks](#stage-6--patches-and-benchmarks) | quick | [#8](https://github.com/pedrobtz/zudiff/issues/8) | | |
| 7 | [Windows runtime](#stage-7--windows-runtime) | full | [#9](https://github.com/pedrobtz/zudiff/issues/9) | | |
| 8 | [Full CI](#stage-8--full-ci) | full | [#10](https://github.com/pedrobtz/zudiff/issues/10) | | |
| 9 | [v0.1.0 readiness](#stage-9--v010-readiness) | full | [#11](https://github.com/pedrobtz/zudiff/issues/11) | | |

## Stage 0 — Package identity

**Issue.** [#2](https://github.com/pedrobtz/zudiff/issues/2), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zudiff/issues/1).

**CI.** `quick`.

**Goal.** The scaffold says what the package is, and CI checks it quickly
on the platforms the POSIX-only stages need.

**Work.**

- `DESCRIPTION`: real Title and Description, `Authors@R` with `aut`, `cre`
  and `cph`, `Depends: R (>= 4.1)`, `Language: en-GB` (design §3),
  `OS_type: unix` and `SystemRequirements` as in `zugojson`, until Stage 7.
- `R-CMD-check.yaml`: `runners` without Windows, as in `zugojson`, with a
  comment pointing at Stage 7.
- ~~Callers for the r-actions checks a compiled package needs in the full
  profile~~. Moved to Stage 1 on 2026-10-27: on the scaffold's C stub,
  UBSan's check that the build was instrumented fails, because the stub has
  nothing UBSan instruments. The checks arrive with the first real C.
- Pin `coverage.yml` to a commit with the tag in a comment, since it holds
  a write token.
- `zudiff_info()`, returning the package version; it gains the Goose pin
  in Stage 1. Replace the placeholder test with one for it.
- `CLAUDE.md` from the template and `.Rbuildignore` with the entries its
  "Working with skills" lists (done by `pkg-init`).

**Exit criteria.**

- `R CMD check` passes on the quick r-actions profile.
- Every check of the pull request's quick run finishes in under five
  minutes. Anything tuned to get there is recorded here.

  Nothing was tuned. On 2026-10-27 the package's own steps took seconds,
  but `r-lib/actions/setup-r` varied from about one to seven minutes
  between runs of the same job: coverage took 1m06s, then 5m54s, of which
  setup-r was 314 s. `quick-step` and `quick-containers` cannot shorten
  that, so it is recorded rather than tuned.
- `DESCRIPTION` carries no scaffold placeholder text.

**Design.** §3, §5 (`zudiff_info()`).

## Stage 1 — Goose toolchain and runtime

**Issue.** [#3](https://github.com/pedrobtz/zudiff/issues/3), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zudiff/issues/1).

**CI.** `full — first runtime code: a longjmp out of Goose, PROT_NONE
stack guards and fault handlers, which every later stage runs on`.

**Goal.** A trivial Goose export runs inside R through a copy of
`zugojson`'s runtime, CI proves the committed C is what the pin produces,
and the §10 baseline is recorded before any diff code exists.

**Work.**

- `tools/goose/PIN`: start from `zugojson`'s pin, so the copied runtime
  matches the compiler's runtime interface hash. Moving to a newer Goose
  release is a separate, later change.
- Copy from `zugojson`: `src/goose_r_runtime.{c,h}`, `tools/regenerate.sh`,
  `tools/check-symbols.sh`, the `goose.yaml` workflow and
  `tests/testthat/test-runtime.R`. Rename what names the package; record
  the copy and every change in `src/goose_r_runtime.c`'s header comment.
- `tools/goose/zudiff.goose` with one probe export, regenerated into
  `src/zudiff_goose.{c,h}`, `src/goose_version.h` and `src/goose_vendor.c`.
- `src/zudiff_r.c`: the `.Call` glue and `R_init_zudiff()`, replacing the
  scaffold's `src/zudiff.c`. Runtime failures come back as a message that
  R raises as `zudiff_runtime_error` (design §8).
- `inst/COPYRIGHTS` and `inst/licenses/goose-LICENSE` (Apache-2.0), and
  the vendored code declared in `DESCRIPTION`.
- `.covrignore` excluding the generated and vendored C.
- `native-checks.yaml` from r-actions' example (sanitizers, valgrind, LTO,
  gctorture, rchk, analyzers, cran-special), moved here from Stage 0, with
  the generated and vendored C excluded where the workflows allow it.
- `tests/testthat/test-abi.R`: the shared object exports `R_init_zudiff`
  only (design §9).
- `tools/run-benchmarks` and `.agents/benchmarks.md` with the baseline:
  `diffobj::ses()` on the §10 inputs and the empty-call cost of the probe
  against `zugojson`'s.

**Exit criteria.**

- `goose.yaml`'s regenerate job passes: the committed C equals what
  `tools/regenerate.sh --verify` produces at the pin.
- `tools/check-symbols.sh` finds no forbidden symbol on Linux and macOS.
- The runtime tests pass: a failure rewinds the stacks and the next call
  succeeds.
- A full-profile run is green on the pull request.
- `.agents/benchmarks.md` holds the §10 baseline.

**Design.** §4, §8, §9 (runtime, ABI), §10 (baseline), D1.

## Stage 2 — Greedy Myers and diff_vec()

**Issue.** [#4](https://github.com/pedrobtz/zudiff/issues/4), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zudiff/issues/1).

**CI.** `quick`.

**Goal.** `diff_vec()` diffs any two supported vectors with a correct edit
script, and the script round-trips.

**Work.**

- In Goose: `diff_ids()` and `diff_bytes()` with greedy Myers
  (O((N + M) D) memory), prefix and suffix trimming, and the §7 packed
  script. Buffers sized from the input once (§4.1).
- In R: the type checks and `match()` ids of §6.1, raw vectors sent
  straight to `diff_bytes()`, unpacking with `readBin()`, the format
  version check, and the `zudiff` object.
- `diff_vec()`, `diff_edits()`, `diff_identical()` and `diff_apply()`.
  `diff_edits()` reports 1-based start-and-length ranges (design §5.1).
- Ids computed as `match(x, x)` (design §6.1, D3).
- `zudiff_input_error` for mismatched or unsupported types and long
  vectors.
- Tests: the round-trip property over every §6.1 type with `NA` and `NaN`
  mixed in; a table test per §6.1 equality rule; the run invariants of
  §6.2 (maximal runs, delete before insert).

**Exit criteria.**

- `diff_apply(old, diff_vec(old, new))` is identical to `new` on every
  generated pair.
- Every §6.1 rule and §6.2 invariant has a passing test.
- `R CMD check` passes on the quick profile.

**Design.** §5, §6.1, §6.2, §7, §8.

## Stage 3 — Linear space, cost limit and interrupts

**Issue.** [#5](https://github.com/pedrobtz/zudiff/issues/5), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zudiff/issues/1).

**CI.** `quick`.

**Goal.** Myers runs in O(N + M) memory, stops at the cost limit with a
correct script, and Ctrl-C ends a long diff.

**Work.**

- Linear-space divide and conquer (Myers §4b) replacing the greedy core,
  which stays in the Goose source as the test reference.
- `max_cost`: the default `max(256, sqrt(N + M) * 8)`, the split at the
  furthest-reaching diagonal, `minimal = FALSE` when it is hit, and
  `max_cost = Inf`.
- `zudiff_interrupted()` as an `extern fn`, a `SIGINT` handler installed
  only for the duration of `goose_r_run()`, and the glue re-raising the
  interrupt in R. The change is recorded in `src/goose_r_runtime.c`'s header comment.
- An O(NM) dynamic-programming edit-distance reference in
  `tests/testthat/helper-reference.R`.
- Check the recommended `max_cost` default (design Q1) against GNU
  diffutils' `analyze.c` and git's `xdiff/xdiffi.c`, compare the three on
  the benchmark corpus, and record the outcome in the design.

  Done in part on 2026-10-27: the default is checked against both sources
  and recorded in design Q1. Comparing the three heuristics on the
  benchmark corpus moves to Stage 6, which builds the corpus; on the §10
  text input the default already gives a minimal script.

**Exit criteria.**

- With `max_cost = Inf`, the edit distance equals the reference's on 10⁴
  random pairs of length up to 200.
- The round trip still holds, including for results with
  `minimal = FALSE`.
- The interrupt test on two 10⁶-element vectors with no common elements
  passes, and the next call succeeds.
- `R CMD check` passes on the quick profile.

**Design.** §6.3, §9 (minimality, the core), D5, Q1.

## Stage 4 — Patience diff

**Issue.** [#6](https://github.com/pedrobtz/zudiff/issues/6), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zudiff/issues/1).

**CI.** `quick`.

**Goal.** `algorithm = "patience"` aligns on unique elements and falls back
to Myers between anchors.

**Work.**

- In Goose: occurrence counts in flat arrays indexed by id, the longest
  increasing subsequence of anchors by patience sorting, and recursion with
  Myers for stretches without unique elements.
- Patience results record `minimal = FALSE`.
- Tests: the round trip under patience; `git diff --no-index --patience`
  interop where the CI image has git.

**Exit criteria.**

- The round-trip property holds for patience on every generated pair.
- Where git is available, patience's edit script applied to `old` gives
  `new` for the interop fixtures, and git's `--patience` output is
  recorded for comparison.
- `R CMD check` passes on the quick profile.

  Recorded on 2026-10-27, git 2.55.0: on 500 random line files the edit
  distance equalled `git diff --patience`'s on 499; on the one other,
  zudiff's script was shorter (89 against 91). Hunks differ by
  tie-breaking on about half the pairs. On the C fixture in
  `helper-git.R` the change blocks are identical to git's, which a test
  asserts. Myers with `max_cost = Inf` equalled `git diff --minimal`'s
  distance on all 500.

**Design.** §6.4, D6.

## Stage 5 — Text, hunks and unified output

**Issue.** [#7](https://github.com/pedrobtz/zudiff/issues/7), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zudiff/issues/1).

**CI.** `quick`.

**Goal.** Two strings diff as lines, and any result prints and writes as a
GNU-compatible unified diff.

**Work.**

- `diff_text()`: split into lines with their endings kept, and the
  no-newline marker. Line endings are compared exactly (Q3), and the
  documentation warns that CRLF against LF differs on every line.
- `diff_hunks()` with configurable context, merging overlapping hunks.
  Hunk fields as in design §5.1.
- `diff_unified()` with `---` and `+++` headers and `@@` hunk headers;
  `format()` per element for `diff_vec()` results.
- The print method: a unified diff with three lines of context, at most
  `n` lines (50 by default) with a footer, each clipped to the console
  width (design §5.1).
- Tests: snapshots of unified output; GNU `patch` interop where the CI
  image has it.

**Exit criteria.**

- Where GNU `patch` is available, it applies `diff_unified()`'s output to
  `old` and gives `new` for every interop fixture.
- The no-newline marker round-trips in both directions.
- `R CMD check` passes on the quick profile.

**Design.** §5, §6.5 (output), Q3.

## Stage 6 — Patches and benchmarks

**Issue.** [#8](https://github.com/pedrobtz/zudiff/issues/8), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zudiff/issues/1).

**CI.** `quick`.

**Goal.** Unified diffs read back and apply with exact context, every §9
test passes, and the §10 targets are measured.

**Work.**

- `patch_parse()`: the GNU format plus git's `diff --git` and `index`
  lines, into a list of file patches.
- `patch_apply()` with exact context; a mismatch is a
  `zudiff_patch_error` naming the hunk.
- The full round trip, `patch_apply(old, patch_parse(diff_unified(d)))`,
  in the property test.
- Interop: `patch_apply()` applies `git diff --no-index` output, plain,
  `--minimal` and `--patience`, to give `new`; Myers' edit distance equals
  `--minimal`'s.
- Compare GNU diff's, git's and the RFC's `max_cost` heuristics on the
  benchmark corpus (moved from Stage 3).
- `tools/run-benchmarks` over every §10 row, recorded in
  `.agents/benchmarks.md`, with the 5× target revised if Stage 1's
  baseline showed `diffobj` already that fast.

**Exit criteria.**

- Every §9 test passes, including the full round trip on 10⁵ generated
  pairs across all types.
- `.agents/benchmarks.md` records every §10 row against its target.
- `R CMD check` passes on the quick profile.

**Design.** §6.5 (input), §9, §10, §12, D7.

## Stage 7 — Windows runtime

**Issue.** [#9](https://github.com/pedrobtz/zudiff/issues/9), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zudiff/issues/1).

**CI.** `full — Windows-only code path: VirtualAlloc guard pages, a
vectored exception handler and a console control handler`.

**Goal.** The package builds and passes on Windows, so it can go to CRAN.

**Work.**

- Confirm Q5 first. The recommendation is to write the Windows half here,
  unless `zugoose`'s Windows stage has landed, and to offer it to
  `zugoose` and `zugojson` afterwards. Record the answer in the design.
- The Windows half of `goose_r_runtime.c`: `VirtualAlloc` with
  `PAGE_NOACCESS` for the stack gap, a vectored exception handler for the
  fault, and a console control handler for Ctrl-C. Remove the `#error`.
  Record the change in `src/goose_r_runtime.c`'s header comment.
- Drop `OS_type: unix` and update `SystemRequirements`.
- `R-CMD-check.yaml`: restore the default Windows runner and add the
  Windows R-devel row.
- `tools/check-symbols.sh` and `goose.yaml`'s symbol job on Windows too.

**Exit criteria.**

- A full-profile run is green on the pull request, Windows legs included.
- The runtime and interrupt tests pass on Windows.

**Design.** D10, Q5, §12 (Windows).

## Stage 8 — Full CI

**Issue.** [#10](https://github.com/pedrobtz/zudiff/issues/10), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zudiff/issues/1).

**CI.** `full`.

**Goal.** Everything the full r-actions profile finds is fixed. No new
features.

**Work.**

- Run the full profile with the `full-ci` label: gctorture at the sensitive
  step, valgrind, ASan, rchk, every platform leg, `nosuggests`, `nold` and
  cran-special. Fix what it finds.
- Collect the failures commented on this issue by earlier merges and fix
  them.

**Exit criteria.**

- A full-profile run is green on the pull request and on its merge commit.

**Design.** §12.

## Stage 9 — v0.1.0 readiness

**Issue.** [#11](https://github.com/pedrobtz/zudiff/issues/11), sub-issue of
[v0.1.0](https://github.com/pedrobtz/zudiff/issues/1).

**CI.** `full`.

**Goal.** Only the submission itself is left.

**Work.**

- `README.Rmd` and one article, with its examples chosen from design
  §16's candidates.
- Check that the tarball carries `tools/goose/`, the source of the
  generated C (design Q4).
- `Version: 0.1.0` and the matching `NEWS.md` heading.
- `cran-comments.md` listing the r-actions CI legs as test environments.
- The `pkg-critical-review` skill, with its blocking and required findings
  fixed; then the `pkg-cran-review` skill, with every finding resolved.
- `urlchecker::url_check()` and `spelling::spell_check_package()` clean.

**Exit criteria.**

- Every §12 acceptance criterion holds.
- `pkg-critical-review` and `pkg-cran-review` have no open finding.
- A full-profile run is green on the release commit.

**Design.** §12.

## After 0.1.0

From design §14, in the expected order:

- Integer vector results from the core, when Goose allows them, replacing
  §7's packing.
- Word and character diff inside changed lines.
- Histogram diff, if users ask.
- Patch fuzz and offsets.
- Three-way merge with conflict markers.
- Diffs of files and directories, with `zufs`.
- Moving to `use_zugoose()`, once `zugoose` v0.1.0 covers borrowed
  vectors, raw results, interrupts and Windows.
- A newer Goose pin than `zugojson`'s, when a release compiles the source
  and the runtime interface change is absorbed.

## Open questions

The design records a recommendation for each (2026-10-26). These are the
stages that confirm them.

- **D3, equality through `match()`**: kept, with ids from `match(x, x)`.
  Stage 2 builds on it.
- **Q1**, the `max_cost` default: settled in Stage 3, GNU diff's rule,
  checked against the sources (design Q1).
- **Q2**, a tolerance for doubles: settled, no; callers round first.
- **Q3**, line endings: settled, compared exactly; `strip_cr` is after
  0.1.0.
- **Q4**, CRAN or GitHub: CRAN recommended, since siblings will import
  `zudiff`. The board's `CRAN intent` records it.
- **Q5**, Windows: written in `zudiff` and offered upstream, confirmed at
  the start of Stage 7.
- **Design §16**: ranges, hunk fields and printing are settled in design
  §5.1; the article's examples are chosen in Stage 9.
