# zudiff: benchmarks

Measured by `tools/run-benchmarks` (design §10) with `bench::mark()`,
median of at least five iterations. Machine: Intel Core i5-8500B at
3.0 GHz, macOS 15.7.9, R 4.5.2, `diffobj` 0.3.6, clang at R's default
`-O2`.

## Stage 1 baseline, 2026-10-27

No diff code exists yet. These are the numbers the §10 targets are
measured against.

| Operation | What | Median | Memory |
| --- | --- | --- | --- |
| 10^5 lines, 1 % changed | `diffobj::ses()` | 262 ms | 26.5 MB |
| 10^5 lines, 1 % changed | `match(x, x)` | 12.3 ms | 5.82 MB |
| identical 10^6 integers | `match(x, x)` | 98 ms | 38.9 MB |
| identical 10^5 strings | `diffobj::ses()` | 24.6 ms | 11.5 MB |
| empty call | `zudiff:::probe_index(1)` | 5.75 µs | 8.02 KB |
| empty call | `zugojson:::index_probe(1)` | 5.17 µs | 4.64 KB |

What this says about the targets:

- **10^5-line texts, 5× faster than `diffobj::ses()`**: about 52 ms.
  `match()` alone takes 12.3 ms of that budget (D3), so the core has
  about 40 ms. The target stands.
- **Two identical 10^6-element vectors, under 10 ms beyond `match()`**:
  `match()` itself is 98 ms on the `c(old, new)` of 2 × 10^6 integers.
  The target is on the time beyond it, so prefix trimming must make the
  core near free.
- **Empty call within 10 % of `zugojson`'s**: 11 % over at baseline. The
  probe returns `list(value, error)`, which allocates more than
  `zugojson`'s bare scalar (8.0 KB against 4.6 KB). Stage 6 measures it
  again on the real exports; if it is still over, return the value
  directly and signal failure another way.
- **Two 10 MB raw vectors**: `diffobj` has no byte diff, so there is no
  comparison row; the target is absolute (under 100 ms).

## Stage 6, 2026-10-27

Same machine. `tools/run-benchmarks` now times every §10 row and compares
`max_cost` heuristics. Three runs of the §10 rows after the changes below;
the text row varies with `diffobj`'s own time, which ranged from 192 to
303 ms.

| Operation | Target | Measured | Met |
| --- | --- | --- | --- |
| 10^5 lines, 1 % changed | 5× `diffobj` | 37–41 ms; 4.6×, 6.4×, 7.1× | 2 of 3 |
| same, patience | none | 36–66 ms; 2.9× to 7.3× | |
| same, `match()` share | recorded | 16–24 ms, 39–64 % | |
| 10 MB raw, 100 edits | < 100 ms | 80–87 ms | yes |
| identical 10^6 vectors | < 10 ms past `match()` | 0.4–0.7 ms | yes |
| empty `.Call` | ±10 % of `zugojson` | −9 %, +2 %, +1 % | yes |

What changed to get there, from the Stage 3 interim numbers (80 ms text,
543 ms raw, 113 ms identical beyond `match()`, +166 % empty call):

- **Unmatched elements are set aside before the search** (design §6.3, as
  GNU diff does). The text case fell from 80 to about 40 ms: every changed
  line is new, so the search had nothing left to do.
- **Snakes compare 64 elements at a time** with slice equality, in
  `checkfree` functions (bounds checks proved away: 34 of 129 index checks
  and all 12 slice checks elided, up from 10 of 125). Raw fell from 475 ms
  in the core to about 85 ms; most of the old time was byte-by-byte
  comparison along long equal runs.
- **Identical inputs skip the core.** `identical(old, new)` implies equal
  under `match()`, so the script is one equal run, without `match()`.
- **Entry points return their value, not `list(value, error)`,** and only
  diffs of 4096 elements or more install the Ctrl-C handler. The two
  `sigaction()` calls had cost about 1.1 µs of an empty call: without them
  the entry point measured 3.53 µs against `zugojson`'s 3.48 µs. The R
  test wrappers' `stopifnot()` checks had also been timed, so the benchmark
  now times the `.Call` entry points of both packages.

### max_cost heuristics (design Q1)

The plain-text files that ship with R, each edited at four rates (half the
edits replace lines, a quarter delete, a quarter insert), diffed with each
heuristic's cost limit. "Worst excess" is how much longer than minimal the
worst script was.

Corpus: NEWS, NEWS.1, NEWS.2, NEWS.3, FAQ, COPYRIGHTS (41,497 lines in
all).

| max_cost | lines changed | total ms | minimal | worst excess |
| --- | --- | --- | --- | --- |
| git | 1 % | 9.6 | 6 of 6 | 0.00 % |
| gnu | 1 % | 9.0 | 6 of 6 | 0.00 % |
| rfc | 1 % | 10.3 | 6 of 6 | 0.00 % |
| git | 10 % | 16.3 | 6 of 6 | 0.00 % |
| gnu | 10 % | 15.7 | 6 of 6 | 0.00 % |
| rfc | 10 % | 16.2 | 6 of 6 | 0.00 % |
| git | 30 % | 36.1 | 3 of 6 | 0.06 % |
| gnu | 30 % | 43.0 | 6 of 6 | 0.00 % |
| rfc | 30 % | 43.0 | 6 of 6 | 0.00 % |
| git | 50 % | 51.0 | 2 of 6 | 0.09 % |
| gnu | 50 % | 79.4 | 6 of 6 | 0.00 % |
| rfc | 50 % | 78.3 | 6 of 6 | 0.00 % |

`gnu` is the default (`max_cost = NULL`), `git` is
`max(256, sqrt(N + M + 3))` and `rfc` is the RFC's first guess,
`max(256, 8 * sqrt(N + M))`. GNU's rule kept every script minimal at
under 80 ms for six files at 50 % changed; git's is up to 1.6× faster and
its scripts up to 0.09 % longer. Q1's choice stands. Before unmatched lines
were set aside, the same corpus took GNU's rule 2,182 ms at 50 % and left
one script non-minimal.

## Goose pin b362b5a5, 2026-10-31

Same machine. The pin moved from `e76d5c9` to `b362b5a5`, which is
upstream `2ed1a63d` plus a fix to the `--header` output. Each build was
installed into its own library, and the runs alternated between them.

The core alone: `.Call(zudiff_c_diff, ...)` on 2 × 10^5 integer ids, with
1 % changed. The median of six processes, each the median of at least 20
iterations. `f758863` is `zugojson`'s previous pin: `e76d5c9` with its
own alignment fix.

| Core | e76d5c9 | f758863 | b362b5a5 |
| --- | --- | --- | --- |
| Myers | 22.3 ms | 22.4 ms (+0.5 %, slower in 2 of 6) | 23.7 ms (+6.4 %, slower in 6 of 6) |
| Patience | 74.2 ms | 73.6 ms (−0.8 %, slower in 3 of 6) | 76.9 ms (+3.7 %, slower in 6 of 6) |

On two 10 MB raw vectors with 100 edits, `diff_vec()` took 53.3 ms on both
`e76d5c9` and `b362b5a5`.

Alignment-safe access costs nothing (`f758863`). The integer slowdown
comes from another upstream change between `e76d5c9` and `2ed1a63d`
(#24). The §10 targets are still met. In
the quieter of two `tools/run-benchmarks` runs, `b362b5a5` measured:
- the text row at 27.8 ms, 9.1× `diffobj`;
- the raw row at 53.5 ms;
- identical vectors at 0.47 ms beyond `match()`;
- the empty call 2 % under `zugojson`'s.
