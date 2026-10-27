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
