// zudiff's diff core, written in Goose (https://github.com/aardappel/goose)
// and compiled to C by tools/regenerate.sh. The generated C is what the
// package builds; this file is its source. Never edit src/zudiff_goose.c
// by hand.
//
// The core diffs two sequences of integer ids or bytes, where equality is
// `==`; the R layer has already turned R values into ids (design §6.1).
// The result is the packed edit script of design §7: a header of four
// little-endian i32 (format version, number of runs, minimal flag, edit
// distance), then one record of four i32 per run (operation 0 equal,
// 1 delete, 2 insert; start in old; start in new; length). Starts are
// 0-based here; the R layer reports them 1-based.
//
// Two Myers implementations (Myers 1986):
//
// - linear space (§4b, algorithm 0), the one users get. It follows the
//   structure of GNU diffutils' compareseq() and diag(): trim what is equal
//   at both ends, find the middle snake searching from both ends at once,
//   split there. When a search costs max_cost steps without meeting, it
//   splits at the furthest point either direction reached, as GNU diff
//   does, and the script is no longer minimal. Subproblems go on an
//   explicit task stack rather than the C stack.
// - greedy (§3, algorithm 9), one snapshot of the furthest-reaching
//   diagonals per edit step, O(D^2) memory. It is the tests' reference.

// --- the edit script -----------------------------------------------------

let OP_EQUAL: i32 = 0;
let OP_DELETE: i32 = 1;
let OP_INSERT: i32 = 2;
let FORMAT_VERSION: i32 = 1;
let ALGORITHM_GREEDY: i32 = 9;
let NO_LIMIT: i64 = 9223372036854775807;
let FAR: i32 = 2147483647;

struct Run { op: i32, o: i32, n: i32, len: i32 }
struct Step { op: i32, len: i32 }

var steps: Step[>..] = [];  // the moves, in order
var runs: Run[>..] = [];    // the script, in order
var out: u8[>..] = [];      // the packed script
var polls: i64 = 0;         // search steps since the call began
var minimal: bool = true;   // false once a cost cut-off splits

// The runtime (src/goose_r_runtime.c) ends the call if Ctrl-C was pressed
// since it began; the R glue then raises the interrupt in R.
extern fn zudiff_check_interrupt() = "zudiff_check_interrupt";

fn poll() {
    polls++;
    if (polls & 1023) == 0 { zudiff_check_interrupt(); }
}

fn step(op: i32, len: i64) {
    if len > 0 { steps.push(Step { op: op, len: len as i32 }); }
}

fn put_i32(x: i32) {
    out.push((x & 255) as u8);
    out.push(((x >> 8) & 255) as u8);
    out.push(((x >> 16) & 255) as u8);
    out.push(((x >> 24) & 255) as u8);
}

fn emit(op: i32, o: i64, n: i64, len: i64) {
    if len == 0 { return; }
    if runs.len > 0 {
        let last = &runs[runs.len - 1];
        if op == OP_EQUAL && last.op == OP_EQUAL && last.o + last.len == o && last.n + last.len == n {
            last.len += len as i32;
            return;
        }
    }
    runs.push(Run { op: op, o: o as i32, n: n as i32, len: len as i32 });
}

fn flush(bo: i64, bn: i64, del: i64, ins: i64) {
    emit(OP_DELETE, bo, bn, del);
    emit(OP_INSERT, bo + del, bn, ins);
}

// Turns the moves into maximal runs, with every block of changes between
// two equal runs written as one delete, then one insert. Returns the edit
// distance.
fn build_runs() -> i64 {
    var oi: i64 = 0;
    var ni: i64 = 0;
    var del: i64 = 0;
    var ins: i64 = 0;
    var bo: i64 = 0;
    var bn: i64 = 0;
    var dist: i64 = 0;
    for s in steps {
        if s.op == OP_EQUAL {
            flush(bo, bn, del, ins);
            dist += del + ins;
            del = 0;
            ins = 0;
            emit(OP_EQUAL, oi, ni, s.len);
            oi += s.len;
            ni += s.len;
        } else {
            if del == 0 && ins == 0 { bo = oi; bn = ni; }
            if s.op == OP_DELETE { del += s.len; oi += s.len; } else { ins += s.len; ni += s.len; }
        }
    }
    flush(bo, bn, del, ins);
    dist += del + ins;
    return dist;
}

// --- greedy Myers, the test reference ------------------------------------

var trace: i32[>..] = [];   // V snapshots, d(d+1)/2 + (k+d)/2
var v: i32[>..] = [];       // furthest x on each diagonal, offset by max
var back: Step[>..] = [];   // backtrack moves, last move first

fn snap(d: i64, k: i64) -> i32 {
    return trace[d * (d + 1) / 2 + (k + d) / 2];
}

fn myers_greedy(a, b) {
    let n = a.len;
    let m = b.len;
    let max = n + m;
    if max == 0 { return; }
    v.resize(2 * max + 2, 0);
    var dist: i64 = -1;
    var d: i64 = 0;
    while dist < 0 {
        poll();
        var k = -d;
        while k <= d {
            var x: i64 = 0;
            if k == -d || (k != d && v[max + k - 1] < v[max + k + 1]) {
                x = v[max + k + 1];
            } else {
                x = v[max + k - 1] + 1;
            }
            var y = x - k;
            while x < n && y < m && a[x] == b[y] { x++; y++; }
            v[max + k] = x as i32;
            if x >= n && y >= m { dist = d; }
            k += 2;
        }
        var j = -d;
        while j <= d { trace.push(v[max + j]); j += 2; }
        d++;
    }
    var x = n;
    var y = m;
    var e = dist;
    while e > 0 {
        let k = x - y;
        var pk: i64 = 0;
        if k == -e || (k != e && snap(e - 1, k - 1) < snap(e - 1, k + 1)) { pk = k + 1; } else { pk = k - 1; }
        let px: i64 = snap(e - 1, pk);
        let py = px - pk;
        // The edit ends at old position mx; from there to x is an equal snake.
        var mx = px;
        if pk == k - 1 { mx = px + 1; }
        if x > mx { back.push(Step { op: OP_EQUAL, len: (x - mx) as i32 }); }
        if pk == k + 1 {
            back.push(Step { op: OP_INSERT, len: 1 });
        } else {
            back.push(Step { op: OP_DELETE, len: 1 });
        }
        x = px;
        y = py;
        e--;
    }
    if x > 0 { back.push(Step { op: OP_EQUAL, len: x as i32 }); }
    var i = back.len - 1;
    while i >= 0 { steps.push(back[i]); i--; }
}

// --- linear-space Myers --------------------------------------------------

// Furthest-reaching x per diagonal k = x - y, forward and backward,
// indexed k + off. Diagonals run from -m - 1 to n + 1.
var fd: i32[>..] = [];
var bd: i32[>..] = [];

// A task: a subproblem a[xoff..xlim] against b[yoff..ylim] (kind 0), or a
// run of moves to record (kind 1: op in xoff, length in xlim).
struct Task { kind: i32, xoff: i32, xlim: i32, yoff: i32, ylim: i32, find_minimal: bool }
var tasks: Task[>..] = [];

struct Part { xmid: i64, ymid: i64, lo_minimal: bool, hi_minimal: bool }

// The middle snake of a[xoff..xlim] against b[yoff..ylim], both non-empty
// and differing at both ends; or, past too_expensive steps without
// find_minimal, the furthest point either search reached.
fn diag(a, b, off: i64, xoff: i64, xlim: i64, yoff: i64, ylim: i64, find_minimal: bool, too_expensive: i64) -> Part {
    let dmin = xoff - ylim;
    let dmax = xlim - yoff;
    let fmid = xoff - yoff;
    let bmid = xlim - ylim;
    var fmin = fmid;
    var fmax = fmid;
    var bmin = bmid;
    var bmax = bmid;
    let odd = ((fmid - bmid) & 1) != 0;
    fd[off + fmid] = xoff as i32;
    bd[off + bmid] = xlim as i32;
    var c: i64 = 1;
    while true {
        poll();
        // Forward, one more step.
        if fmin > dmin { fmin--; fd[off + fmin - 1] = -1; } else { fmin++; }
        if fmax < dmax { fmax++; fd[off + fmax + 1] = -1; } else { fmax--; }
        var d = fmax;
        while d >= fmin {
            let tlo: i64 = fd[off + d - 1];
            let thi: i64 = fd[off + d + 1];
            var x: i64 = thi;
            if tlo >= thi { x = tlo + 1; }
            var y = x - d;
            while x < xlim && y < ylim && a[x] == b[y] { x++; y++; }
            fd[off + d] = x as i32;
            if odd && bmin <= d && d <= bmax && bd[off + d] <= x {
                return Part { xmid: x, ymid: y, lo_minimal: true, hi_minimal: true };
            }
            d -= 2;
        }
        // Backward, one more step.
        if bmin > dmin { bmin--; bd[off + bmin - 1] = FAR; } else { bmin++; }
        if bmax < dmax { bmax++; bd[off + bmax + 1] = FAR; } else { bmax--; }
        d = bmax;
        while d >= bmin {
            let tlo: i64 = bd[off + d - 1];
            let thi: i64 = bd[off + d + 1];
            var x: i64 = thi - 1;
            if tlo < thi { x = tlo; }
            var y = x - d;
            while xoff < x && yoff < y && a[x - 1] == b[y - 1] { x--; y--; }
            bd[off + d] = x as i32;
            if !odd && fmin <= d && d <= fmax && x <= fd[off + d] {
                return Part { xmid: x, ymid: y, lo_minimal: true, hi_minimal: true };
            }
            d -= 2;
        }
        if !find_minimal && c >= too_expensive {
            // Give up: split at whichever search got further.
            var fxybest: i64 = -1;
            var fxbest: i64 = 0;
            d = fmax;
            while d >= fmin {
                var x: i64 = fd[off + d];
                if x > xlim { x = xlim; }
                var y = x - d;
                if ylim < y { x = ylim + d; y = ylim; }
                if fxybest < x + y { fxybest = x + y; fxbest = x; }
                d -= 2;
            }
            var bxybest: i64 = NO_LIMIT;
            var bxbest: i64 = 0;
            d = bmax;
            while d >= bmin {
                var x: i64 = bd[off + d];
                if x < xoff { x = xoff; }
                var y = x - d;
                if y < yoff { x = yoff + d; y = yoff; }
                if x + y < bxybest { bxybest = x + y; bxbest = x; }
                d -= 2;
            }
            minimal = false;
            if (xlim + ylim) - bxybest < fxybest - (xoff + yoff) {
                return Part { xmid: fxbest, ymid: fxybest - fxbest, lo_minimal: true, hi_minimal: false };
            }
            return Part { xmid: bxbest, ymid: bxybest - bxbest, lo_minimal: false, hi_minimal: true };
        }
        c++;
    }
    return Part { xmid: xoff, ymid: yoff, lo_minimal: true, hi_minimal: true };
}

fn push_range(xoff: i64, xlim: i64, yoff: i64, ylim: i64, find_minimal: bool) {
    tasks.push(Task { kind: 0, xoff: xoff as i32, xlim: xlim as i32, yoff: yoff as i32, ylim: ylim as i32, find_minimal: find_minimal });
}

fn push_moves(op: i32, len: i64) {
    if len > 0 {
        tasks.push(Task { kind: 1, xoff: op, xlim: len as i32, yoff: 0, ylim: 0, find_minimal: true });
    }
}

fn myers_linear(a, b, too_expensive: i64) {
    let n = a.len;
    let m = b.len;
    let off = m + 1;
    fd.resize(n + m + 3, 0);
    bd.resize(n + m + 3, 0);
    push_range(0, n, 0, m, too_expensive == NO_LIMIT);
    while tasks.len > 0 {
        let t = tasks.pop();
        if t.kind == 1 {
            step(t.xoff, t.xlim);
            continue;
        }
        var xoff: i64 = t.xoff;
        var xlim: i64 = t.xlim;
        var yoff: i64 = t.yoff;
        var ylim: i64 = t.ylim;
        let x0 = xoff;
        while xoff < xlim && yoff < ylim && a[xoff] == b[yoff] { xoff++; yoff++; }
        let pre = xoff - x0;
        let x1 = xlim;
        while xoff < xlim && yoff < ylim && a[xlim - 1] == b[ylim - 1] { xlim--; ylim--; }
        let suf = x1 - xlim;
        // Last in, first out: push what comes last first.
        push_moves(OP_EQUAL, suf);
        if xoff == xlim {
            push_moves(OP_INSERT, ylim - yoff);
        } else if yoff == ylim {
            push_moves(OP_DELETE, xlim - xoff);
        } else {
            let p = diag(a, b, off, xoff, xlim, yoff, ylim, t.find_minimal, too_expensive);
            push_range(p.xmid, xlim, p.ymid, ylim, p.hi_minimal);
            push_range(xoff, p.xmid, yoff, p.ymid, p.lo_minimal);
        }
        push_moves(OP_EQUAL, pre);
    }
}

// GNU diff's default cost limit: about the square root of the input size,
// a power of two, and at least 4096 (diffutils src/analyze.c).
fn default_cost(n: i64, m: i64) -> i64 {
    var diags = n + m + 3;
    var lg: i64 = 0;
    while diags > 1 { diags = diags >> 1; lg++; }
    var cost: i64 = 1 << ((lg >> 1) + 1);
    if cost < 4096 { cost = 4096; }
    return cost;
}

fn diff(a, b, algorithm: i32, max_cost: i64) -> const u8[:] {
    steps.clear();
    runs.clear();
    out.clear();
    trace.clear();
    v.clear();
    back.clear();
    fd.clear();
    bd.clear();
    tasks.clear();
    polls = 0;
    minimal = true;
    if algorithm == ALGORITHM_GREEDY {
        myers_greedy(a, b);
    } else {
        var cost = max_cost;
        if cost < 0 { cost = default_cost(a.len, b.len); }
        myers_linear(a, b, cost);
    }
    let dist = build_runs();
    put_i32(FORMAT_VERSION);
    put_i32(runs.len as i32);
    if minimal { put_i32(1); } else { put_i32(0); }
    put_i32(dist as i32);
    for r in runs {
        put_i32(r.op);
        put_i32(r.o);
        put_i32(r.n);
        put_i32(r.len);
    }
    return out;
}

// --- the exported API ----------------------------------------------------
//
// Every export clears the globals it uses before anything else. After a
// runtime failure the R glue rewinds the data stacks but not the globals,
// so an export must never rely on what an earlier call left in them.

// The diff of two vectors of integer ids, and of two byte vectors. Inputs
// are at most 2^31 - 1 long together, checked in R. algorithm is 0 for
// Myers and 9 for the greedy reference; max_cost is the cost limit, -1 for
// the default and NO_LIMIT for a minimal script.
export fn zudiff_diff_ids(a: const i32[:], b: const i32[:], algorithm: i32, max_cost: i64) -> const u8[:] {
    return diff(a, b, algorithm, max_cost);
}

export fn zudiff_diff_bytes(a: const u8[:], b: const u8[:], algorithm: i32, max_cost: i64) -> const u8[:] {
    return diff(a, b, algorithm, max_cost);
}

// Test hook: a bounds-check failure on demand, so the tests can exercise
// the runtime's error path.
export fn zudiff_probe_index(i: i64) -> i64 {
    var a: i64[3] = [10, 20, 30];
    return a[i];
}

// Test hook: reads a borrowed integer vector, the shape diff_ids() takes.
export fn zudiff_probe_sum(a: const i32[:]) -> i64 {
    var s: i64 = 0;
    for x in a { s += x; }
    return s;
}

// Test hook: fills a local dynamic array, which lives on a Goose data
// stack, then optionally fails with a bounds error. A failure skips the
// array's release, so only goose_r_run()'s rewind returns the stack to
// where it was.
export fn zudiff_probe_stack(n: i64, fail: bool) -> i64 {
    var v: i64[>..] = [];
    for i in n { v.push(i); }
    if fail { return v[n]; }
    return v[n - 1];
}
