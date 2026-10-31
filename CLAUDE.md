# CLAUDE.md

<!-- markdownlint-disable-next-line MD013 -->
This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`zudiff` computes the shortest edit script between two sequences and returns
it as data: runs of the old sequence kept, deleted or inserted. Inputs are two
atomic vectors of the same type, two raw vectors compared byte by byte, or two
strings compared line by line. From the script it builds hunks, writes unified
diffs, and applies a script or a unified diff. Algorithms are Myers (default,
with a cost limit) and patience. Callers are sibling packages (`daffiz`,
`zurds`, `zupdf`, the round-trip tests of `zutoml` and `zuyaml`) and users who
want a diff without `diffobj`'s GPL licence or presentation layer. No
`Imports`, no `LinkingTo`; `Suggests: testthat` only. It is not a presentation
layer (no colours, no side-by-side), not a merge tool, not a structural diff of
lists or data frames, and has no C API.

The specification is [`.agents/design.md`](.agents/design.md), adopted from
[RFC 0045](https://github.com/pedrobtz/packages/blob/main/rfcs/started/0045-zudiff-sequence-diff-in-goose.md).
It outranks this file: `CLAUDE.md` orients, the design doc decides. Its
decisions marked (C) and its open questions (§15) are still open.

## Current state

Scaffolded 2026-10-26 with `create-pkg.sh`. As of 2026-10-27 the whole
v0.1.0 API in design §5 works on Linux and macOS: `diff_vec()` and
`diff_text()` (linear-space Myers with GNU diff's cost limit and discarding,
patience, Ctrl-C; greedy Myers stays as the tests' reference, algorithm 9),
`diff_edits()`, `diff_identical()`, `diff_apply()`, `diff_hunks()`,
`diff_unified()`, printing, `patch_parse()` and `patch_apply()`. Every
design §10 target is met (`.agents/benchmarks.md`), on Linux, macOS and
Windows. The roadmap in `.agents/roadmap.md` takes it to v0.1.0.
It is built by hand on `zugojson`'s pattern, independently of `zugoose`
(design D1, revised 2026-10-26).

## Stage tracking

Progress toward the next version is tracked as GitHub sub-issues, so the
parent issue shows a progress bar such as "6 of 7".

- **One parent issue per target version**, titled with the bare version, for
  example `v0.1.0`. `v0.1.0` issue: created by `pkg-roadmap`.
- **One sub-issue per roadmap stage**, titled as the roadmap titles it, for
  example `Stage 3 — R interface`, and linking to that section. The number of
  stages is whatever the roadmap has; there is no fixed scale.
- **Every tracking issue carries the `stage` label**, so it can be told apart
  from bug and feature issues and left out of open-issue counts.
- **Close a stage by merging its pull request.** Put `Closes #<n>` in the
  body of the stage's pull request. Never close a stage whose exit criteria
  are not met; record a deviation in the roadmap first.
- **The roadmap stays authoritative.** The issues record which stages are
  done, not what a stage requires. Adding, removing or renaming a stage
  means editing the roadmap and the sub-issues in the same change.
- **Each stage has a CI tier, `quick` or `full`.** The roadmap sets it, and
  `quick` is the default. See Continuous integration for what each means.
  The second-to-last stage, `Full CI`, runs the full set and fixes what it
  finds before `v0.1.0 readiness`.
- Close the parent issue when CRAN accepts the version and it is tagged.
  Opening a parent issue implies at least one stage sub-issue; a parent with
  no sub-issues shows no progress on the board.

## Versioning

A new package develops at `0.0.0.9000` and targets `0.1.0` for its first CRAN
release. Set `Version: 0.1.0` and the matching `NEWS.md` heading when the
package enters `Pre-flight`. Bump to `0.1.0.9000` only after CRAN accepts it,
never before: a `.9000` version above an unreleased `0.1.0` heading is wrong.

Until the first release the R API may change freely. Sibling packages can
still depend on this one before CRAN does, through `Remotes:` or `LinkingTo:`.
The design names `daffiz` and `zurds` (calling `diff_vec()`), `zupdf`, and
`zutoml` and `zuyaml` (`Suggests`, for test output). There is no C API, so
only R API changes reach them. A package that others wait on should reach
CRAN first.

## Commands

Run from the package root.

```sh
Rscript -e 'devtools::load_all()'                # compile src/ and load
Rscript -e 'devtools::document()'                # roxygen -> NAMESPACE, man/
Rscript -e 'devtools::test()'                    # full testthat suite
Rscript -e 'devtools::test(filter = "<name>")'   # one test file
Rscript -e 'devtools::test(shuffle = TRUE)'      # order independence
Rscript -e 'devtools::check()'                   # R CMD check
air format .                                     # format R sources
```

Occasional, when the Goose source or the pin changes. The checkout must be
a clone of `tools/goose/REMOTE` at `tools/goose/PIN`, built (`cmake -S . -B
build && cmake --build build`):

```sh
tools/regenerate.sh <goose-checkout>            # rewrite the generated C
tools/regenerate.sh --verify <goose-checkout>   # what CI runs
tools/check-symbols.sh <path>/zudiff.so         # forbidden-symbol check
tools/run-benchmarks                            # design §10, installed pkg
tools/run-sweep [pairs]                         # §12 round trip, 10^5 pairs
```

## Architecture

Design §4 is the specification; [`pedrobtz/zugojson`](https://github.com/pedrobtz/zugojson)
and its `CLAUDE.md` are the working reference. Read design §4.1 before
writing Goose: it points at the Goose evaluations for memory layout.

```text
R/core.R                  core_value(), zudiff_abort(), the probes
src/zudiff_r.c            .Call glue: the only C that uses R's API
───────────────────────── plain C below ─────────────────────────
src/zudiff_goose.{c,h}    generated from tools/goose/zudiff.goose
src/goose_runtime.c       generated: Goose's runtime, built -DGS_HOSTED
src/goose_version.h       generated: runtime interface hash, the pin
```

Every entry point runs its Goose call inside `goose_host_call()` (Goose's
hosted runtime, `.agents/goose-fork.md` patch 1) and returns its value, or
the failure message as a string; `core_value()` raises a string as a
`zudiff_runtime_error`. No entry point returns a string on success, so keep
it that way or change the convention. Ctrl-C: the core calls
`goose_host_poll()` every 1024 steps, whose hook runs
`R_CheckUserInterrupt()` inside `R_ToplevelExec()`; a yes ends the call,
and `core_value()` raises the `interrupt`. Vectors reach
Goose borrowed (`sl_i32` points into `INTEGER(x)`), never copied.
`src/Makevars` compiles with `$(C_VISIBILITY)`, and only `R_init_zudiff` and
`R_unload_zudiff` are marked visible, which `test-abi.R` checks.

## Invariants that are easy to break

- **The shipped C is generated.** `src/zudiff_goose.c` comes from
  `tools/goose/zudiff.goose` through `tools/regenerate.sh`. Edit the Goose
  source and regenerate; CI fails on a hand edit.
- **The pin is a fork commit.** `tools/goose/REMOTE` names
  `pedrobtz/goose`, and `PIN` is upstream `master` plus the patches in
  `.agents/goose-fork.md`: the `--header` types, `-pedantic`, and the
  hosted runtime (`GS_HOSTED`) zudiff now depends on. Change `REMOTE` and
  `PIN` together.
- **Generated on any platform.** Since the pin includes
  [aardappel/goose#122](https://github.com/aardappel/goose/issues/122)'s
  fix, the generated C is the same whether the compiler was built with
  libc++ (macOS) or libstdc++ (Linux). CI's `regenerate` job checks both.
- **The Goose pieces copied in stay Apache-2.0**, while `zudiff`'s own code
  is MIT. Keep the two licences declared in `inst/COPYRIGHTS`.
- **No R error inside `goose_host_call()`.** An R longjmp would skip the
  stack rewind and leave the fault handler installed. The interrupt poll
  is the one call into R, inside `R_ToplevelExec()`. Results are copied
  into R objects after the call returns.
- **Every export clears its globals first.** After a failure the data
  stack tops are rewound but Goose globals are not.
- **Only `R_init_zudiff` and `R_unload_zudiff` are exported.** The
  runtime's `gs_*` names are Goose's and cannot take a package prefix, so
  they must stay hidden or they clash with another package's copy.
- **On Windows the fault handler must not outlive the DLL.**
  `R_unload_zudiff()` calls `goose_host_unload()`, which removes it; a
  vectored handler left in unloaded code crashes R at its next access
  violation. The handler passes on every fault outside the data stacks.
- **The runtime is Goose's.** `src/goose_runtime.c` is generated; a change
  to it is a change to the fork. `tools/goose/PROVENANCE` is written by
  `tools/regenerate.sh`; never edit it.
- **Equality is `match()`'s, computed in R.** The core sees only integer ids
  or bytes and compares with `==`. Moving equality into the core would lose
  R's rules for `NA`, `NaN`, signed zero, encodings and factor labels.
- **No C API** (design D2). Siblings call R functions.
- **The packed script carries a format version** (design §7). Change the
  layout and bump the version together, or the R layer misreads the core.
- **Positions and ids are `i32`.** Inputs longer than 2³¹ − 1 must be a
  `zudiff_input_error`, never a silent overflow.

## Testing conventions

- **Self-sufficient.** Every test builds its own inputs inside the
  `test_that()` block. No file-scope objects.
- **Self-contained.** Global state goes through `withr::local_*()`, randomised
  input through `withr::local_seed()`. Tests write only under `tempdir()`.
- **Assert on condition classes, never message text.** Use
  `expect_error(..., class = "<pkg>_<kind>_error")`. Wording belongs in
  snapshot tests.
- **Order independence.** `devtools::test(shuffle = TRUE)` is part of the
  definition of done.
- **Borrow a conformance suite before writing one.** Mainstream
  implementations in Python, Java, Go or Node usually ship a test corpus.
  Use it as an oracle rather than inventing cases by hand. There is no
  diff corpus to borrow, so git is the oracle where it is installed
  (`git diff --no-index`, `git apply`), and GNU `patch` where it is
  (`helper-patch.R`; macOS's own `patch` is not GNU's, so that test runs
  on Linux). Hunks may differ from git's by tie-breaking, so tests compare
  edit distances, and exact blocks only on chosen fixtures.
- **Helpers live in `tests/testthat/helper-*.R`.** `helper-generate.R`
  draws random pairs of every supported type and defines `exhaustive()`;
  `helper-reference.R` is the O(NM) edit-distance reference and the greedy
  core; `helper-git.R` turns `git diff -U0` and a `zudiff` object into
  comparable change blocks; `helper-patch.R` applies a unified diff with
  GNU `patch` or `git apply` and holds the text fixtures;
  `helper-expect.R` holds `property()` and the round-trip checks.
- **Property loops make one expectation.** One `expect_identical()` costs
  several milliseconds, so a loop of thousands spent the suite's time in
  testthat. Check each case with `identical()` through `property()`
  (`helper-expect.R`), which lists the first failing cases. Helpers go in
  `helper-*.R`, never at file scope: `shuffle = TRUE` reorders tests within
  a file.
- **Keep the suite inside the CRAN time budget.** About 30 s locally on
  2026-10-27, most of it the O(NM) reference. The large sweeps run only
  where `ZUDIFF_EXHAUSTIVE=true`, which the R CMD check caller sets and
  gctorture and valgrind do not; `tools/run-sweep` runs design §12's 10^5
  round trips outside the suite.

## Definition of done

`devtools::document()` and `devtools::check()` clean, meaning 0 errors, 0
warnings and 0 notes. The one allowed note is "New submission" before the first
release. `devtools::test(shuffle = TRUE)` green. CI green at the change's
tier: the quick profile for a `quick` roadmap stage or an ordinary pull
request, the full profile for a `full` stage, `Full CI`, and every release.
A user-facing change also needs a test, roxygen documentation and a `NEWS.md`
entry.

## Releasing to CRAN

- **CI is the pre-submission check.** The `pedrobtz/r-actions` R CMD check runs
  `--as-cran` on the CRAN-like runners and containers, and it replaces
  win-builder, the macOS builder and R-hub. None of them is a release step,
  and `cran-comments.md` lists the CI legs as its test environments.
- **Entering `Pre-flight`.** The roadmap's feature stages are done, the
  version is set as in Versioning, `NEWS.md` and `cran-comments.md` are
  written, and CI is green. Only submission work remains.
- **Before submitting,** run `pkg-critical-review` once the roadmap is
  implemented and fix what it files, then `pkg-cran-review`, and resolve
  every finding. Both skills are in `pedrobtz/r-skills`.
- **The pretest is automated and does not read `cran-comments.md`.** A NOTE
  that is explained but not fixed gets the upload archived. Fix the NOTE, as
  under Vendored native code, instead of justifying it.
- **After acceptance,** `pkg-post-cran` tags the submitted commit with the
  bare version, `0.1.0` (no `v`), publishes the GitHub release, bumps to
  `0.1.0.9000`, closes the version's parent issue and moves the board card.

## Editing rules

- roxygen comments are the source. Never edit `man/` or `NAMESPACE` by hand.
- Edit `README.Rmd`, not the generated `README.md`.
- Keep prose simple and short. One idea per sentence.
- Wrap roxygen text at 80 characters and run `air format .` on R sources.
- Use `lower_snake_case`, and prefix internal native symbols with `<pkg>_`.
- Keep hard runtime dependencies at zero unless a recorded design decision
  says otherwise.
- Export and document public functions. Do not create roxygen topics for
  internal ones.

## Continuous integration

Workflows come from `pedrobtz/r-actions`. Call those reusable workflows instead
of writing bespoke ones, and pin a released tag rather than `main`. Pin a
workflow that holds a write token, such as `coverage.yml`, to a commit, with
the tag in a comment. The `R-CMD-check` workflow must call `r-cmd-check.yml`,
because a hand-rolled one does not count as the pre-submission check. This
package calls `r-cmd-check.yml@v1` (`R-CMD-check.yaml`) and `coverage.yml@v1`
(`coverage.yaml`). `pkgdown.yaml` is the r-lib example, not an r-actions
workflow.

Small edits get a small run. The shared workflows look at the files a pull
request changes, compared with its merge base:

- **Markdown only**, such as `README.md`, `NEWS.md` or `cran-comments.md`,
  skips every check. Only coverage and the pkgdown site run.
- **`DESCRIPTION` or `README.Rmd` as well**, and nothing else, adds one R CMD
  check on Ubuntu R-release.
- **Any other file** runs everything.

So put a README or `DESCRIPTION` touch-up in its own pull request. Once a pull
request changes code, every later push to it runs every workflow.

### Quick by default, full by exception

The full profile is slow. gctorture at step 20 alone has taken 36 to 107
minutes on sibling packages. Waiting on it between roadmap stages was the
main thing slowing roadmaps down, so:

- **Pull requests run the quick profile.** It should finish in under five
  minutes. If it doesn't, raise gctorture's `quick-step` or trim
  `quick-containers` in the caller workflows; never cut the full profile.
- **A `full` roadmap stage takes the `full-ci` label** and merges only on a
  green full run. The roadmap gives the reason in the stage's `**CI.**`
  line, for example first compiled code, a `PROTECT` or finalizer change, a
  vendored library, or a Windows-only path.
- **Don't wait on the full run a merge starts** on the default branch, and
  cancel older full runs it supersedes. A failure that only the full set
  shows goes on the `Full CI` stage issue as a comment with the run link,
  and is fixed there. A failure the quick profile also shows is fixed now.
- **`Full CI` and `v0.1.0 readiness` wait** for a green full run on their
  merge commit, and the release commit always needs one.
- Locally, run `gctorture(TRUE)` on the code a C change touches when it is
  cheap; the full run is the authority.

## Commits and pull requests

Short, imperative, sentence-case commit subjects, optionally scoped. Keep each
commit focused and do not sweep in unrelated files. A pull request explains the
user-visible outcome and the rationale, links related issues, lists the checks
that were run and the tests that were skipped, and flags platform-sensitive or
vendored changes. Performance claims need evidence.

Never commit or push to the default branch. Work on a branch, open a pull
request, and leave it for review. Do not merge a pull request unless you are
told to.

When you find a defect, in this package or in an upstream tool, open an issue
for it rather than only working around it.

## Working with skills

The portfolio's workflow skills live in `pedrobtz/r-skills` (`pkg-init`,
`pkg-roadmap`, `pkg-implement`, `pkg-critical-review`, `pkg-cran-review`,
`pkg-post-cran`, `pkg-readme`); the general process skills are
[Superpowers](https://github.com/obra/superpowers). `building-a-package.md`
in `pedrobtz/packages` walks through them in order. Both sets defer to this
file where they overlap, so the settlements are recorded here.

- **One design.** The specification is `.agents/design.md`, adopted from the
  package's RFC in `pedrobtz/packages/rfcs`. A package with an adopted design
  is past `brainstorming`; a design change goes through the RFC, not a new
  spec. Superpowers' default `docs/superpowers/specs/` is not used.
- **Plans at two levels.** `.agents/roadmap.md` holds the stages, one
  mergeable pull request each, with exit criteria and a CI tier
  (`pkg-roadmap`). Inside a stage, `writing-plans` breaks the work into
  tasks of one test cycle each, saved as `.agents/plans/stage-<n>.md`. The
  roadmap stays authoritative; a plan is scratch and is not kept in sync.
- **Build and merge.** `pkg-implement` runs the stage loop: branch
  `stage-<n>-<slug>` from the stage issue, implement the plan with
  `test-driven-development` (`Rscript -e 'devtools::test(filter = "<name>")'`
  is the red/green command), open the pull request, merge on green at the
  stage's CI tier. The confirmation the user gives at the start of that
  loop is the "told to merge" that Commits and pull requests requires, so
  the `finishing-a-development-branch` menu is not presented for stage
  pull requests. Any other pull request still waits for review.
- **Failures and claims.** A failing check or test goes through
  `systematic-debugging` before a fix. "Green", "done" and "ready for CRAN"
  are claimed only after `verification-before-completion`: run the command,
  read the output.
- **Review.** `requesting-code-review` gates tasks inside a stage.
  `pkg-critical-review` reviews the whole package once the roadmap is
  implemented, with Posit's reviewers, and files issues. CRAN's reviewer
  email and GitHub review threads go through `receiving-code-review`.
- **Keep scratch out of the tarball.** `R CMD build` reads `.Rbuildignore`,
  not `.gitignore`. It must list `^\.agents$`, `^\.superpowers$` (the
  Superpowers task ledger), `^\.worktrees$` (if git worktrees are kept in
  the package directory; a sibling directory avoids the question),
  `^\.claude$`, `^CLAUDE\.md$`, `^AGENTS\.md$`, `^CRAN-SUBMISSION$` and
  `^cran-comments\.md$`. A stray top-level file is a NOTE, and the pretest
  archives on NOTEs.
