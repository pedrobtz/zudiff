# zudiff: the Goose fork

How zudiff's Goose runtime is to be replaced by patches to Goose itself,
tried in the fork `pedrobtz/goose` and proposed upstream once they work.
Moved here on 2026-10-31 from `pedrobtz/zugojson`'s runtime research plan,
which is no longer pursued. This file is a research plan: design.md still
decides what v0.1.0 ships, and nothing here blocks it.

## Hosts

The same Goose core, `tools/goose/zudiff.goose`, runs in two hosts:

- **zudiff** (R), this package. Its runtime is
  `src/goose_r_runtime.c`, 509 lines, with a Windows half.
- **zugodiff** (Python), `pedrobtz/py-zugodiff`. It takes zudiff's
  generated C unchanged (`tools/sync-zudiff.sh`) and has its own runtime,
  `goose_py_runtime.c`, about 300 lines, POSIX only.

A patch reaches **go** when both hosts pass with it:

- zudiff: `devtools::test(shuffle = TRUE)` with `ZUDIFF_EXHAUSTIVE=true`,
  `devtools::check()` clean, `tools/check-symbols.sh`, `tools/wine/run`,
  and the r-actions Windows legs;
- zudiff: no `tools/run-benchmarks` row more than 5% slower than at the
  previous patch, and design §10 still met;
- zugodiff: `pytest`, its CI (Linux, macOS, UBSan), and `bench/bench.py`.

## Rules

- **v0.1.0 comes first.** zudiff's `main` takes only what has reached go,
  and not before v0.1.0 is on CRAN. Until then a patch lives on a zudiff
  branch, `goose-<patch>`, pinning the fork commit it measures.
- **One fork branch per patch,** stacked in the order below on upstream
  `master`. Each is then a patch series that upstream can take in order,
  or stop after any one.
- **Rebase on upstream `master`** before each patch starts, before each
  recorded benchmark, and before anything is proposed. Drop what upstream
  now does. Record the upstream commit each result was measured on.
- **Propose upstream only after go,** one proposal per patch. Every post to
  `aardappel/goose` needs the user's approval.
- **zugodiff follows zudiff's generated C.** Regenerate in zudiff, then
  `tools/sync-zudiff.sh` in zugodiff; never edit the C there.
- **Tracking:** #23 lists the patches and their state.

## Before any patch

These need no change to Goose and are worth doing on their own:

- **#22, layer 1:** port zugojson's Piece 0 (`goose_r_run()` inside
  `R_UnwindProtect`), and poll `R_CheckUserInterrupt()` from
  `zudiff_check_interrupt()`. It deletes the SIGINT and console control
  handlers. zugodiff already works this way, with `PyErr_CheckSignals()`.
- **#24:** bisect the 4–6% slowdown on integer ids between `e76d5c9` and
  `2ed1a63d`, so that patches are measured against a known base.

## What every host needed

The Python port tested what is specific to R. The same five needs came
back unchanged. Only the glue differs: `SEXP` against `PyObject *`,
`R_UnwindProtect` against an exception already set.

1. **A failure is the host's error, not a process exit.** Rewind the data
   stacks, keep the message, return.
2. **Fault handlers only while Goose runs.** R and CPython both own
   SIGSEGV.
3. **Interrupts belong to the host:** `R_CheckUserInterrupt()`,
   `PyErr_CheckSignals()`. Both may run host code inside the call.
4. **A call inside a call must be safe.** A Python signal handler run by
   the poll called back into zugodiff. Today the only safe answer is to
   refuse it.
5. **No stdout, stderr, setvbuf, sigaltstack or exit.**

The copied runtimes have drifted from upstream, too. Upstream's error
table has 20 entries and ours 17. So at the fork pin, "invalid array
length", "slice not within this array" and "slice pool span tree is
corrupt" print as "runtime error".

## What Goose already has

From the source at `b362b5a5`, upstream `2ed1a63d` plus the `--header`
fix:

- **Contained failures.** `gs_fail()` `longjmp`s to a thread-local
  `gs_contain` when one is set, keeping the message, instead of printing
  and ending the process. Contained workers use it. `gs_panic()`,
  `gs_exit()`, `gs_stack_overflow()` and the fault handler bypass it.
- **An in-process host.** `goose run` runs programs inside the compiler
  (`jit_runtime.c`, `GS_HOSTED_JIT`). There `gs_end()` `longjmp`s back to
  the compiler, and the fault handlers' installation is recorded so they
  can be removed, the Windows vectored handler included.
- **Globals behind one pointer.** Threaded builds reach `gs_globals_t`
  through the thread-local `gs_gl`, and the data stacks through
  `gs_stks`. Single-threaded builds use a static `gs_globals_main`
  (`codegen.h:1548`).
- **Memory given back:** `gs_trim_memory()`.
- **One checked growth site:** `gs_stack_overflow()`, for a bulk append
  past `GS_STACK_RESERVE` (`0e62366f`).

## Patches

### 0: small fixes

- `__extension__` on the `unsigned __int128` typedef. That removes the
  `sed` patch in `tools/regenerate.sh`.
- `GS_API` wrapped in `#ifndef GS_API`, so the runtime object can be built
  with hidden symbols.
- Done: `--header` declares the alignment types (`b362b5a5`), offered
  upstream when aardappel/goose#125 was closed.

### 1: `GS_HOSTED`, a host mode

Generalize `GS_HOSTED_JIT` into a mode any host can use, built on
`gs_contain`. The runtime object (`goose --emit-runtime --hosted`) offers:

```c
/* Runs body(data) as a contained call: any failure in it, a data stack
   overflow included, rewinds every data stack, stores the message and
   returns 1, or 2 when the host's poll asked to stop. Fault handlers are
   installed for the call only. A call during another is refused with 1
   until contexts (patch 2) allow it. */
int gs_host_call(void (*body)(void *), void *data, const uint8_t **msg, int64_t *len);

typedef struct {
    void (*out)(int stream, const uint8_t *p, int64_t len); /* print, eprint */
    int (*poll)(void);  /* nonzero: stop the call */
} gs_host;
void gs_host_set(const gs_host *host);
```

Under `GS_HOSTED`:

- `gs_panic()`, `gs_exit()`, `gs_stack_overflow()` and the fault handler's
  overflow branch go through `gs_fail()`, and so reach `gs_contain`. The
  jump out of the fault handler must restore the signal mask
  (`sigsetjmp`, not the `_setjmp` used today).
- `gs_host_call()` installs the fault handler and removes it on return,
  as the JIT's already is. On Windows the vectored handler is added once
  and removed by `gs_host_unload()`, as zudiff's `R_unload_zudiff()` does.
- There is no `setvbuf`, `sigaltstack` or `_setmode`. `print` goes to
  `host.out`.
- `gs_host_poll()`, callable from Goose, fails the call with an interrupt
  when `host.poll` returns nonzero. It replaces `zudiff_check_interrupt`.

**Deleted:**
- zudiff: `goose_r_runtime.c` shrinks to the glue's few lines.
  `goose_vendor.c`, the anchor ranges in `tools/regenerate.sh` and the
  error-table drift go.
- zugodiff: `goose_py_runtime.c` goes the same way.

zugojson's plan had proposed `fail`, `out` and `reserve` hooks. `fail`
needs no hook, because `gs_contain` does it. `reserve` is not needed,
because only the signals conflict with R and CPython, not reserved
address space.

### 2: contexts

Behind `--context`, a single-threaded build also reaches globals through
`gs_gl`, and the runtime offers:

```c
gs_ctx *gs_ctx_new(void);         /* fresh globals and stack block */
gs_ctx *gs_ctx_swap(gs_ctx *ctx); /* gs_gl, gs_stks, gs_nstks; returns the old */
void gs_ctx_reset(gs_ctx *ctx);   /* globals re-initialized, tops rewound */
void gs_ctx_free(gs_ctx *ctx);    /* regions released */
```

`gs_ctx_new()` does what `gs_program_init()` and a worker's entry thunk
already do. The region registry (`gs_regions`, thread-local today)
becomes per context.

**Gives:**
- a nested call that works instead of being refused;
- no "every export clears its globals first" invariant (CLAUDE.md);
- in zugodiff, one context per thread, so a long diff can release the GIL.
  That is the only way to free-threaded CPython.

**Cost to measure:** `GS_GL` through a pointer. Threaded builds already
pay it.

### 3: checked growth

`--checked-stacks` checks capacity before stack space is claimed, and
calls `gs_stack_overflow()` instead of relying on the guard gap. On POSIX
patch 1's fault handler is enough, since only overflow needs it. On
Windows, growth itself needs the vectored handler to commit pages (design
D10). This patch removes it, and with it the last handler from both
hosts. It is the patch that decides whether Goose packages can be plain C
extensions everywhere, and the one most likely to stop. Go also requires
deleting zudiff's Windows half with the Windows legs green.

### 4: numeric slice results from exports

Goose spec §7.11 allows only `const u8[:]`. Allowing `const i32[:]` the
same way (a pointer plus `int64_t *out_len`) removes the packed script
(design §7, D4) and its unpacking in R and Python. This is a language
change: propose it upstream as a request with zudiff as the example, not
as a finished patch.

## Not proposed

- **Equality or hashing in Goose.** Turning values into ids dominates in
  both hosts: R's `match()` is 65% of the §10 text row, and Python's
  `dict` is 45 of zugodiff's 48 ms. The host's equality must stay (D3),
  so that speed-up is host C, not Goose.
- **A Goose-side R or Python API.** Values cross only at the export
  boundary.

## Order

| Patch | Size | Unblocks |
| --- | --- | --- |
| 0 small fixes | hours | `regenerate.sh` without patches |
| 1 `GS_HOSTED` | days | the stock runtime in both hosts |
| 2 contexts | days | re-entry; no clear-globals rule; GIL release |
| 3 checked growth | weeks, uncertain | Windows without handlers |
| 4 numeric results | upstream's call | no packed script |
