/* goose_r_runtime.c -- the part of the Goose runtime that zudiff's
   generated C needs, rewritten to live inside an R process. First-party
   code; it replaces goose's src/runtime/runtime_impl.h, which is not
   vendored.

   Copied from zugojson (https://github.com/pedrobtz/zugojson), file
   src/goose_r_runtime.c at commit 4220db519825f9a4aca837d9d44f55170c7f54f4,
   for the same Goose pin. Changes from that copy, newest last:
   - goose_r_stack_used(), so the tests can check that a failure rewinds
     the data stacks (2026-10-27).
   - Ctrl-C (2026-10-27): goose_r_run_interruptible() installs a SIGINT
     handler while Goose code runs, which sets a flag; zudiff_check_interrupt(), which the Goose code
     polls, then fails the call, and goose_r_run() returns 2 so the glue
     can raise the interrupt in R. goose_r_test_raise_after() raises a real
     SIGINT from inside a run, for the tests. Mirrors RFC 0044 §6.2.
     goose_r_run() itself does not touch SIGINT, as in zugojson: the two
     sigaction() calls cost about a microsecond, a third of an empty call.
     A Ctrl-C during it reaches R's own handler and R acts on it after the
     call returns.
   - Windows (2026-10-27, design D10): data stacks are reserved with
     VirtualAlloc and committed a chunk at a time by a vectored exception
     handler, as goose's runtime_impl.h does; a fault in the guard gap
     becomes a failure instead of ending the process, by pointing the
     faulting thread at a function that jumps back to goose_r_run(). The
     jump is __builtin_setjmp/__builtin_longjmp, which unwind no SEH
     frames. The handler is installed once and removed by
     goose_r_unload(). Ctrl-C is a console control handler during
     interruptible runs; R never sees the event, so goose_r_run_
     interruptible() reports it (returns 2) and the R side raises the
     interrupt.

   Differences from the stock runtime (goose src/runtime/runtime_impl.h):
   - Nothing ends the process. Every runtime failure jumps back to
     goose_r_run(), which rewinds the data stacks and hands the message to
     the caller, who raises an ordinary R error.
   - No stdout, stderr, setvbuf, sigaltstack or threads.
   - The guard-page fault handler is installed only while Goose code runs
     inside goose_r_run(). R's own handlers are restored afterwards, and a
     fault outside the data stacks is passed back to them.
   - POSIX and Windows. On Windows the vectored exception handler is
     installed for the life of the DLL, since adding and removing one per
     call takes a lock; it passes on every fault outside the data stacks.

   Byte search and number formatting live in goose_vendor.c, copied
   verbatim from the stock runtime by tools/regenerate.sh. */

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#else
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <setjmp.h>
#include <sys/mman.h>
#include <unistd.h>
#endif
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <R_ext/Error.h>

#include "goose_r_runtime.h"
#include "goose_version.h"

#define GS_API
#define GS_NORETURN __attribute__((noreturn))
#define GS_CAT_(a, b) a##b
#define GS_CAT(a, b) GS_CAT_(a, b)
#define gs_rt_start GS_CAT(gs_rt_start_, GS_RUNTIME_VERSION)

typedef struct gs_stack { uint8_t *top; } gs_stack;

/* The jump back to goose_r_run(). POSIX restores the signal mask, which a
   signal handler leaves blocked. Windows has no signal to return from, and
   mingw's longjmp would unwind SEH frames, so GCC's builtins are used. */
#ifdef _WIN32
typedef void *gs_jmp[5];
#define GS_SETJMP(b) __builtin_setjmp(b)
#define GS_LONGJMP(b) __builtin_longjmp(b, 1)
#else
typedef sigjmp_buf gs_jmp;
#define GS_SETJMP(b) sigsetjmp(b, 1)
#define GS_LONGJMP(b) siglongjmp(b, 1)
#endif

/* --- data stack regions -------------------------------------------------- */

#define GS_R_MAX_REGIONS 64

typedef struct {
    uint8_t *base;
    size_t size;      /* usable part plus the PROT_NONE guard gap */
    gs_stack *stack;  /* whose top goose_r_run saves and rewinds */
    uint8_t *saved;
    uint8_t *committed; /* Windows: the end of what is committed */
} gs_r_region;

static gs_r_region regions[GS_R_MAX_REGIONS];
static long nregions;
static size_t region_usable, region_gap;

/* --- failures: jump back to goose_r_run ---------------------------------- */

static gs_jmp *active_jump;
static char failure[512];

/* Ctrl-C while Goose runs: the handler only sets the flag; the Goose code
   polls it through zudiff_check_interrupt(). */
static volatile sig_atomic_t interrupt_pending;
static int interrupt_failed;
static long raise_after;

static GS_NORETURN void gs_r_fail(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(failure, sizeof failure, fmt, ap);
    va_end(ap);
    if (active_jump) GS_LONGJMP(*active_jump);
    /* Goose code ran outside goose_r_run: a bug in the glue. Nothing has
       been rewound, but R can still report it. */
    Rf_error("goose runtime error outside goose_r_run: %s", failure);
}

GS_API GS_NORETURN void gs_panic(const char *msg) { gs_r_fail("%s", msg); }

static const char *const errmsgs[] = {
    "limited array capacity exceeded",
    "slice bounds out of range",
    "relative reference offset overflow",
    "assert failed",
    "invalid capacity",
    "resize growth requires a fill value",
    "resize to a negative length",
    "pop on empty array",
    "thread_wait on an unknown thread id",
    "a worker cannot wait for itself",
    "corrupt ADT tag",
    "serialization needs a little-endian host",
    "invalid slice length",
    "slice not from this pool",
    "non-null relative reference encodes as null",
    "pop_n count negative or beyond the array's length",
    "queue limit of zero or less",
};

GS_API GS_NORETURN void gs_abort(int err, const char *file, int line) {
    const char *m = err >= 0 && err < (int)(sizeof errmsgs / sizeof *errmsgs)
                        ? errmsgs[err] : "runtime error";
    gs_r_fail("%s (%s:%d)", m, file, line);
}

GS_API GS_NORETURN void gs_abort_msg(const uint8_t *msg, int64_t len, const char *file,
                                     int line) {
    gs_r_fail("%.*s (%s:%d)", (int)(len > 400 ? 400 : len), (const char *)msg, file, line);
}

GS_API GS_NORETURN void gs_exit(int64_t code) {
    gs_r_fail("exit(%lld) called", (long long)code);
}

GS_API GS_NORETURN void gs_idxfail(int64_t i, int64_t n, const char *file, int line) {
    gs_r_fail("index %lld out of bounds (length %lld) (%s:%d)", (long long)i,
              (long long)n, file, line);
}

GS_API GS_NORETURN void gs_divfail(const char *file, int line) {
    gs_r_fail("division by zero (%s:%d)", file, line);
}

GS_API GS_NORETURN void gs_divovf(const char *file, int line) {
    gs_r_fail("division overflow (%s:%d)", file, line);
}

GS_API GS_NORETURN void gs_ovf(int64_t a, const char *op, int64_t b, const char *type,
                               const char *file, int line) {
    gs_r_fail("%s overflow: %lld %s %lld (%s:%d)", type, (long long)a, op, (long long)b,
              file, line);
}

GS_API GS_NORETURN void gs_ovf_neg(int64_t a, const char *type, const char *file, int line) {
    gs_r_fail("%s overflow: -%lld (%s:%d)", type, (long long)a, file, line);
}

GS_API GS_NORETURN void gs_asfail_i(const char *why, int64_t v, const char *type,
                                    const char *file, int line) {
    gs_r_fail("%lld as %s: %s (%s:%d)", (long long)v, type, why, file, line);
}

GS_API GS_NORETURN void gs_asfail_u(const char *why, uint64_t v, const char *type,
                                    const char *file, int line) {
    gs_r_fail("%llu as %s: %s (%s:%d)", (unsigned long long)v, type, why, file, line);
}

GS_API GS_NORETURN void gs_asfail_f(const char *why, double d, int f32, const char *type,
                                    const char *file, int line) {
    (void)f32;
    gs_r_fail("%g as %s: %s (%s:%d)", d, type, why, file, line);
}

/* --- interrupts ---------------------------------------------------------- */

GS_API void zudiff_check_interrupt(void) {
#ifdef _WIN32
    /* No SIGINT reaches a console control handler, so the hook sets the
       flag the handler would. */
    if (raise_after > 0 && --raise_after == 0) interrupt_pending = 1;
#else
    if (raise_after > 0 && --raise_after == 0) raise(SIGINT);
#endif
    if (interrupt_pending) {
        interrupt_pending = 0;
        interrupt_failed = 1;
        gs_r_fail("interrupted");
    }
}

/* Test hook: the n-th poll of the next run raises SIGINT (on Windows, acts
   as a Ctrl-C would). */
void goose_r_test_raise_after(long n) { raise_after = n; }

#ifdef _WIN32
static BOOL WINAPI interrupt_handler(DWORD type) {
    if (type != CTRL_C_EVENT && type != CTRL_BREAK_EVENT) return FALSE;
    interrupt_pending = 1;
    return TRUE;
}
#else
static void interrupt_handler(int sig) {
    (void)sig;
    interrupt_pending = 1;
}
#endif

#ifdef _WIN32

/* --- start-up and regions ------------------------------------------------ */

static size_t page_size;
#define GS_R_COMMIT_CHUNK ((size_t)1 << 20)

GS_API void gs_rt_start(int argc, char **argv, uint64_t reserve, uint64_t gap,
                        uint64_t budget, int64_t mainregions, int64_t workerregions) {
    (void)argc; (void)argv; (void)budget; (void)workerregions;
    SYSTEM_INFO si;
    GetSystemInfo(&si);
    page_size = si.dwPageSize;
    if (mainregions > GS_R_MAX_REGIONS) gs_r_fail("too many data stacks");
    region_usable = (size_t)reserve - (size_t)reserve % page_size;
    region_gap = ((size_t)gap + page_size - 1) / page_size * page_size;
    if (!region_usable || !region_gap) gs_r_fail("bad data stack sizes");
}

/* Address space for one data stack, all of it reserved and none committed:
   the fault handler commits the usable part as it is touched, and never
   the gap after it, so runaway growth faults there. */
GS_API uint8_t *gs_reserve_region(gs_stack *stack) {
    if (nregions >= GS_R_MAX_REGIONS) gs_r_fail("too many data stack regions");
    size_t size = region_usable + region_gap;
    uint8_t *p = (uint8_t *)VirtualAlloc(NULL, size, MEM_RESERVE, PAGE_READWRITE);
    if (!p) gs_r_fail("cannot reserve data stack address space");
    regions[nregions].base = p;
    regions[nregions].size = size;
    regions[nregions].stack = stack;
    regions[nregions].committed = p;
    nregions++;
    return p;
}

/* --- running Goose code -------------------------------------------------- */

static PVOID fault_filter_handle;

/* Where a faulting thread is sent: a fresh frame, from which the jump back
   to goose_r_run() is an ordinary longjmp. */
static GS_NORETURN void fault_jump(void) {
    GS_LONGJMP(*active_jump);
}

static LONG WINAPI fault_filter(EXCEPTION_POINTERS *ep) {
    if (ep->ExceptionRecord->ExceptionCode != STATUS_ACCESS_VIOLATION)
        return EXCEPTION_CONTINUE_SEARCH;
    uint8_t *hit = (uint8_t *)ep->ExceptionRecord->ExceptionInformation[1];
    for (long i = 0; i < nregions; i++) {
        gs_r_region *r = &regions[i];
        if ((uintptr_t)hit - (uintptr_t)r->base >= r->size) continue;
        if (hit < r->base + region_usable) {
            /* Growth: commit the next chunk, clamped to the usable part. */
            uint8_t *page = (uint8_t *)((uintptr_t)hit & ~(uintptr_t)(page_size - 1));
            size_t n = GS_R_COMMIT_CHUNK;
            if (page + n > r->base + region_usable)
                n = (size_t)(r->base + region_usable - page);
            if (VirtualAlloc(page, n, MEM_COMMIT, PAGE_READWRITE)) {
                if (page + n > r->committed) r->committed = page + n;
                return EXCEPTION_CONTINUE_EXECUTION;
            }
            snprintf(failure, sizeof failure, "out of memory growing a data stack");
        } else {
            snprintf(failure, sizeof failure, "data stack overflow");
        }
        if (!active_jump) return EXCEPTION_CONTINUE_SEARCH;
        /* Resume in fault_jump, on a stack aligned as at a function's
           entry. */
#if defined(_M_X64) || defined(__x86_64__)
        ep->ContextRecord->Rsp = (ep->ContextRecord->Rsp & ~(DWORD64)15) - 8;
        ep->ContextRecord->Rip = (DWORD64)(uintptr_t)fault_jump;
#elif defined(_M_ARM64) || defined(__aarch64__)
        ep->ContextRecord->Sp &= ~(DWORD64)15;
        ep->ContextRecord->Pc = (DWORD64)(uintptr_t)fault_jump;
#else
#error "goose_r_runtime.c: unsupported Windows architecture"
#endif
        return EXCEPTION_CONTINUE_EXECUTION;
    }
    return EXCEPTION_CONTINUE_SEARCH;
}

static void install_fault_filter(void) {
    if (!fault_filter_handle)
        fault_filter_handle = AddVectoredExceptionHandler(1, fault_filter);
}

void goose_r_unload(void) {
    if (fault_filter_handle) {
        RemoveVectoredExceptionHandler(fault_filter_handle);
        fault_filter_handle = NULL;
    }
}

static int run(void (*body)(void *), void *data, char *err, size_t errlen, int catch_int) {
    gs_jmp jump;
    gs_jmp *outer = active_jump;
    long i;

    install_fault_filter();
    for (i = 0; i < nregions; i++) regions[i].saved = regions[i].stack->top;
    if (catch_int) SetConsoleCtrlHandler(interrupt_handler, TRUE);
    interrupt_pending = 0;
    interrupt_failed = 0;

    int failed = 0;
    if (GS_SETJMP(jump) == 0) {
        active_jump = &jump;
        body(data);
    } else {
        failed = 1;
        for (i = 0; i < nregions; i++)
            if (regions[i].saved) regions[i].stack->top = regions[i].saved;
        if (err && errlen) snprintf(err, errlen, "%s", failure);
        if (interrupt_failed) failed = 2;
    }
    active_jump = outer;
    raise_after = 0;

    if (catch_int) SetConsoleCtrlHandler(interrupt_handler, FALSE);
    /* R saw no Ctrl-C, the handler took it: report one the Goose code did
       not notice too, so the R side can raise it. */
    if (catch_int && interrupt_pending) {
        interrupt_pending = 0;
        if (err && errlen) snprintf(err, errlen, "interrupted");
        failed = 2;
    }
    return failed;
}

#else /* POSIX */

/* --- start-up and regions ------------------------------------------------ */

GS_API void gs_rt_start(int argc, char **argv, uint64_t reserve, uint64_t gap,
                        uint64_t budget, int64_t mainregions, int64_t workerregions) {
    (void)argc; (void)argv; (void)budget; (void)workerregions;
    size_t page = (size_t)sysconf(_SC_PAGESIZE);
    if (mainregions > GS_R_MAX_REGIONS) gs_r_fail("too many data stacks");
    region_usable = (size_t)reserve - (size_t)reserve % page;
    region_gap = ((size_t)gap + page - 1) / page * page;
    if (!region_usable || !region_gap) gs_r_fail("bad data stack sizes");
}

/* Address space for one data stack: the usable part read-write, committed
   by the kernel as it is touched (overcommit, as the stock runtime does on
   Linux), then a PROT_NONE gap that turns runaway growth into a fault. */
GS_API uint8_t *gs_reserve_region(gs_stack *stack) {
    if (nregions >= GS_R_MAX_REGIONS) gs_r_fail("too many data stack regions");
    size_t size = region_usable + region_gap;
    int flags = MAP_PRIVATE | MAP_ANONYMOUS;
#ifdef MAP_NORESERVE
    flags |= MAP_NORESERVE;
#endif
    void *p = mmap(NULL, size, PROT_READ | PROT_WRITE, flags, -1, 0);
    if (p == MAP_FAILED) gs_r_fail("cannot reserve data stack address space");
    if (mprotect((uint8_t *)p + region_usable, region_gap, PROT_NONE)) {
        munmap(p, size);
        gs_r_fail("cannot protect data stack guard gap");
    }
    regions[nregions].base = (uint8_t *)p;
    regions[nregions].size = size;
    regions[nregions].stack = stack;
    nregions++;
    return (uint8_t *)p;
}

/* --- running Goose code -------------------------------------------------- */

static struct sigaction prev_segv, prev_bus, prev_int;

static void fault_handler(int sig, siginfo_t *info, void *ctx) {
    (void)ctx;
    uintptr_t hit = (uintptr_t)info->si_addr;
    for (long i = 0; i < nregions; i++) {
        if (hit - (uintptr_t)regions[i].base < regions[i].size && active_jump) {
            snprintf(failure, sizeof failure, "data stack overflow");
            GS_LONGJMP(*active_jump);
        }
    }
    /* Not ours: put R's handler back; the access faults again under it. */
    sigaction(sig, sig == SIGSEGV ? &prev_segv : &prev_bus, NULL);
}

static int run(void (*body)(void *), void *data, char *err, size_t errlen, int catch_int) {
    gs_jmp jump;
    gs_jmp *outer = active_jump;
    struct sigaction sa;
    long i;

    for (i = 0; i < nregions; i++) regions[i].saved = regions[i].stack->top;

    memset(&sa, 0, sizeof sa);
    sa.sa_sigaction = fault_handler;
    sa.sa_flags = SA_SIGINFO;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGSEGV, &sa, &prev_segv);
#ifdef SIGBUS
    sigaction(SIGBUS, &sa, &prev_bus);
#endif
    if (catch_int) {
        struct sigaction si;
        memset(&si, 0, sizeof si);
        si.sa_handler = interrupt_handler;
        sigemptyset(&si.sa_mask);
        sigaction(SIGINT, &si, &prev_int);
    }
    interrupt_pending = 0;
    interrupt_failed = 0;

    int failed = 0;
    if (GS_SETJMP(jump) == 0) {
        active_jump = &jump;
        body(data);
    } else {
        failed = 1;
        /* Stacks that existed before the call go back to their old tops;
           regions made during it (goose_init) are left as they are. */
        for (i = 0; i < nregions; i++)
            if (regions[i].saved) regions[i].stack->top = regions[i].saved;
        if (err && errlen) snprintf(err, errlen, "%s", failure);
        if (interrupt_failed) failed = 2;
    }
    active_jump = outer;
    raise_after = 0;

    if (catch_int) sigaction(SIGINT, &prev_int, NULL);
    sigaction(SIGSEGV, &prev_segv, NULL);
#ifdef SIGBUS
    sigaction(SIGBUS, &prev_bus, NULL);
#endif
    /* A Ctrl-C during the run goes on to R's own handler, now back in
       place, whether the Goose code noticed it or not. */
    if (catch_int && (interrupt_pending || failed == 2)) {
        interrupt_pending = 0;
        raise(SIGINT);
    }
    return failed;
}

void goose_r_unload(void) {}

#endif

int goose_r_run(void (*body)(void *), void *data, char *err, size_t errlen) {
    return run(body, data, err, errlen, 0);
}

int goose_r_run_interruptible(void (*body)(void *), void *data, char *err, size_t errlen) {
    return run(body, data, err, errlen, 1);
}

/* Bytes in use across all data stacks, for the tests: after any call,
   failed or not, it must be back where it was before. */
size_t goose_r_stack_used(void) {
    size_t used = 0;
    for (long i = 0; i < nregions; i++)
        used += (size_t)(regions[i].stack->top - regions[i].base);
    return used;
}

#ifdef GOOSE_R_TEST
/* For a harness built without R: the first byte of the first data stack's
   guard gap, so that the fault path can be tested without filling the
   stack. Never compiled into the package. */
uint8_t *goose_r_test_gap(void) {
    return nregions ? regions[0].base + region_usable : NULL;
}
#endif
