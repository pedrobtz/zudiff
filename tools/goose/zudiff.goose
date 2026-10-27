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
// Myers is greedy here (Myers 1986, §3): one snapshot of the furthest-
// reaching diagonals per edit step, O(D^2) memory for edit distance D.
// Stage 3 replaces it with the linear-space version and keeps this one
// as the test reference.

// --- the edit script -----------------------------------------------------

let OP_EQUAL: i32 = 0;
let OP_DELETE: i32 = 1;
let OP_INSERT: i32 = 2;
let FORMAT_VERSION: i32 = 1;

struct Run { op: i32, o: i32, n: i32, len: i32 }
struct Step { op: i32, len: i32 }

var trace: i32[>..] = [];   // V snapshots, d(d+1)/2 + (k+d)/2
var v: i32[>..] = [];       // furthest x on each diagonal, offset by max
var steps: Step[>..] = [];  // backtrack moves, last move first
var runs: Run[>..] = [];    // the script, in order
var out: u8[>..] = [];      // the packed script

fn put_i32(x: i32) {
    out.push((x & 255) as u8);
    out.push(((x >> 8) & 255) as u8);
    out.push(((x >> 16) & 255) as u8);
    out.push(((x >> 24) & 255) as u8);
}

// Appends a run, merging it into the last one where both are equal runs
// that meet. Delete and insert runs are only ever emitted by flush(), one
// of each per block, so they never need merging.
fn emit(op: i32, o: i32, n: i32, len: i32) {
    if len == 0 { return; }
    if runs.len > 0 {
        let last = &runs[runs.len - 1];
        if op == OP_EQUAL && last.op == OP_EQUAL && last.o + last.len == o && last.n + last.len == n {
            last.len += len;
            return;
        }
    }
    runs.push(Run { op: op, o: o, n: n, len: len });
}

fn snap(d: i64, k: i64) -> i32 {
    return trace[d * (d + 1) / 2 + (k + d) / 2];
}

// The greedy forward pass over a[lo_a..hi_a] and b[lo_b..hi_b], then the
// backtrack into steps (last move first). Returns the edit distance.
fn myers_greedy(a, b, lo_a: i64, hi_a: i64, lo_b: i64, hi_b: i64) -> i64 {
    let n = hi_a - lo_a;
    let m = hi_b - lo_b;
    let max = n + m;
    if max == 0 { return 0; }
    v.resize(2 * max + 2, 0);
    var dist: i64 = -1;
    var d: i64 = 0;
    while dist < 0 {
        var k = -d;
        while k <= d {
            var x: i64 = 0;
            if k == -d || (k != d && v[max + k - 1] < v[max + k + 1]) {
                x = v[max + k + 1];
            } else {
                x = v[max + k - 1] + 1;
            }
            var y = x - k;
            while x < n && y < m && a[lo_a + x] == b[lo_b + y] { x++; y++; }
            v[max + k] = x as i32;
            if x >= n && y >= m { dist = d; }
            k += 2;
        }
        var j = -d;
        while j <= d { trace.push(v[max + j]); j += 2; }
        d++;
    }
    // Backtrack from (n, m) to (0, 0).
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
        if x > mx { steps.push(Step { op: OP_EQUAL, len: (x - mx) as i32 }); }
        if pk == k + 1 {
            steps.push(Step { op: OP_INSERT, len: 1 });
        } else {
            steps.push(Step { op: OP_DELETE, len: 1 });
        }
        x = px;
        y = py;
        e--;
    }
    if x > 0 { steps.push(Step { op: OP_EQUAL, len: x as i32 }); }
    return dist;
}

// Turns steps (last move first) into maximal runs with every block of
// changes between two equal runs written as one delete, then one insert.
fn build_runs(pre: i64, suf: i64, n: i64, m: i64) {
    emit(OP_EQUAL, 0, 0, pre as i32);
    var oi = pre;
    var ni = pre;
    var del: i64 = 0;
    var ins: i64 = 0;
    var bo = oi;
    var bn = ni;
    var i = steps.len - 1;
    while i >= 0 {
        let s = steps[i];
        if s.op == OP_EQUAL {
            flush(bo, bn, del, ins);
            del = 0;
            ins = 0;
            emit(OP_EQUAL, oi as i32, ni as i32, s.len);
            oi += s.len;
            ni += s.len;
        } else {
            if del == 0 && ins == 0 { bo = oi; bn = ni; }
            if s.op == OP_DELETE { del++; oi++; } else { ins++; ni++; }
        }
        i--;
    }
    flush(bo, bn, del, ins);
    emit(OP_EQUAL, (n - suf) as i32, (m - suf) as i32, suf as i32);
}

fn flush(bo: i64, bn: i64, del: i64, ins: i64) {
    emit(OP_DELETE, bo as i32, bn as i32, del as i32);
    emit(OP_INSERT, (bo + del) as i32, bn as i32, ins as i32);
}

fn diff(a, b) -> const u8[:] {
    trace.clear();
    v.clear();
    steps.clear();
    runs.clear();
    out.clear();
    let n = a.len;
    let m = b.len;
    var pre: i64 = 0;
    while pre < n && pre < m && a[pre] == b[pre] { pre++; }
    var suf: i64 = 0;
    while suf < n - pre && suf < m - pre && a[n - 1 - suf] == b[m - 1 - suf] { suf++; }
    let dist = myers_greedy(a, b, pre, n - suf, pre, m - suf);
    build_runs(pre, suf, n, m);
    put_i32(FORMAT_VERSION);
    put_i32(runs.len as i32);
    put_i32(1);
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

// The diff of two vectors of integer ids, and of two byte vectors. Inputs
// are at most 2^31 - 1 long, checked in R. algorithm and max_cost are
// fixed until Stages 3 and 4 use them (0, Myers; and ignored).
export fn zudiff_diff_ids(a: const i32[:], b: const i32[:], algorithm: i32, max_cost: i64) -> const u8[:] {
    return diff(a, b);
}

export fn zudiff_diff_bytes(a: const u8[:], b: const u8[:], algorithm: i32, max_cost: i64) -> const u8[:] {
    return diff(a, b);
}
