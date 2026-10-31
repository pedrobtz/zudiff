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
// - patience (algorithm 1, design §6.4): elements unique to a stretch on
//   both sides anchor it, the longest increasing run of anchors fixes the
//   alignment, and stretches with no anchors fall back to Myers.
// - greedy (§3, algorithm 9), one snapshot of the furthest-reaching
//   diagonals per edit step, O(D^2) memory. It is the tests' reference.

// --- the edit script -----------------------------------------------------

let OP_EQUAL: i32 = 0;
let OP_DELETE: i32 = 1;
let OP_INSERT: i32 = 2;
let FORMAT_VERSION: i32 = 1;
let ALGORITHM_PATIENCE: i32 = 1;
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

// Goose's hosted runtime asks the host whether to stop: the R glue checks
// for Ctrl-C (src/zudiff_r.c), and a yes ends the call as an interrupt.
extern fn goose_host_poll() = "goose_host_poll";

fn poll() {
    polls++;
    if (polls & 1023) == 0 { goose_host_poll(); }
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

// --- snakes --------------------------------------------------------------
//
// The hot loops: follow equal elements forward from (x, y), or backward to
// (x, y), and return where the run ends in old. They are checkfree, so the
// compiler must prove every index in range rather than check it per
// element; the explicit bounds against a.len and b.len are what it proves
// them from, and cost nothing next to the checks they replace.

// Most snakes end at once, so a few elements are compared one by one
// first; a run that survives them is followed CHUNK elements at a time
// with slice equality (memcmp), and finished one by one.
let CHUNK: i64 = 64;

checkfree fn snake_fwd(a, b, x0: i64, y0: i64, xlim: i64, ylim: i64) -> i64 {
    var x = x0;
    var y = y0;
    var k: i64 = 0;
    while k < 4 && x >= 0 && y >= 0 && x < xlim && y < ylim && x < a.len && y < b.len && a[x] == b[y] {
        x++;
        y++;
        k++;
    }
    if k < 4 { return x; }
    while x >= 0 && y >= 0 {
        let xe = x + CHUNK;
        let ye = y + CHUNK;
        if x > xe || y > ye || xe > xlim || ye > ylim || xe > a.len || ye > b.len { break; }
        if a[x..xe] != b[y..ye] { break; }
        x = xe;
        y = ye;
    }
    while x >= 0 && y >= 0 && x < xlim && y < ylim && x < a.len && y < b.len && a[x] == b[y] {
        x++;
        y++;
    }
    return x;
}

checkfree fn snake_bwd(a, b, x0: i64, y0: i64, xoff: i64, yoff: i64) -> i64 {
    var x = x0;
    var y = y0;
    var k: i64 = 0;
    while k < 4 && x > xoff && y > yoff && x > 0 && y > 0 && x <= a.len && y <= b.len {
        let i = x - 1;
        let j = y - 1;
        if a[i] != b[j] { return x; }
        x = i;
        y = j;
        k++;
    }
    if k < 4 { return x; }
    while x <= a.len && y <= b.len {
        let xs = x - CHUNK;
        let ys = y - CHUNK;
        if xs < xoff || ys < yoff || xs < 0 || ys < 0 || xs > x || ys > y { break; }
        if a[xs..x] != b[ys..y] { break; }
        x = xs;
        y = ys;
    }
    while x > xoff && y > yoff && x > 0 && y > 0 && x <= a.len && y <= b.len {
        let i = x - 1;
        let j = y - 1;
        if a[i] != b[j] { break; }
        x = i;
        y = j;
    }
    return x;
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
            x = snake_fwd(a, b, x, y, n, m);
            y = x - k;
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
            x = snake_fwd(a, b, x, y, xlim, ylim);
            y = x - d;
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
            x = snake_bwd(a, b, x, y, xoff, yoff);
            y = x - d;
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

// Runs the task stack until it is empty: kind 0 is a Myers stretch,
// kind 1 a run of moves, kind 2 a patience stretch.
fn run_tasks(a, b, too_expensive: i64) {
    let n = a.len;
    let m = b.len;
    let off = m + 1;
    fd.resize(n + m + 3, 0);
    bd.resize(n + m + 3, 0);
    while tasks.len > 0 {
        let t = tasks.pop();
        if t.kind == 1 {
            step(t.xoff, t.xlim);
            continue;
        }
        if t.kind == 2 {
            patience_step(a, b, t.xoff, t.xlim, t.yoff, t.ylim, too_expensive);
            continue;
        }
        var xoff: i64 = t.xoff;
        var xlim: i64 = t.xlim;
        var yoff: i64 = t.yoff;
        var ylim: i64 = t.ylim;
        let x0 = xoff;
        let xs = snake_fwd(a, b, xoff, yoff, xlim, ylim);
        yoff += xs - xoff;
        xoff = xs;
        let pre = xoff - x0;
        let x1 = xlim;
        let xe = snake_bwd(a, b, xlim, ylim, xoff, yoff);
        ylim -= xlim - xe;
        xlim = xe;
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

// --- patience diff --------------------------------------------------------

// Occurrence counts and last positions per id, over one stretch of each
// side. Ids are below max(N + M + 1, 256), so these are flat arrays. Only
// the entries a stretch touched are reset after it.
var cnta: i32[>..] = [];
var cntb: i32[>..] = [];
var posb: i32[>..] = [];

// The anchors of one stretch, in old order, and the patience-sorting state
// that finds their longest increasing subsequence in new order.
var anc_x: i32[>..] = [];
var anc_y: i32[>..] = [];
var prev: i32[>..] = [];   // the anchor before this one in its best chain
var tops: i32[>..] = [];   // per pile, the anchor on top
var keep: i32[>..] = [];   // the chosen anchors, last first

fn push_patience(xoff: i64, xlim: i64, yoff: i64, ylim: i64) {
    tasks.push(Task { kind: 2, xoff: xoff as i32, xlim: xlim as i32, yoff: yoff as i32, ylim: ylim as i32, find_minimal: false });
}

// One stretch: elements unique to it on both sides become anchors, the
// longest run of anchors in order on both sides fixes the alignment, and
// each gap between chosen anchors is diffed the same way. A stretch with
// no anchors is diffed with Myers, under the same cost limit.
fn patience_step(a, b, xoff: i64, xlim: i64, yoff: i64, ylim: i64, too_expensive: i64) {
    poll();
    for i in xoff..xlim { cnta[a[i]] += 1; }
    for j in yoff..ylim {
        cntb[b[j]] += 1;
        posb[b[j]] = j as i32;
    }
    anc_x.clear();
    anc_y.clear();
    for i in xoff..xlim {
        let id = a[i];
        if cnta[id] == 1 && cntb[id] == 1 {
            anc_x.push(i as i32);
            anc_y.push(posb[id]);
        }
    }
    for i in xoff..xlim { cnta[a[i]] = 0; }
    for j in yoff..ylim { cntb[b[j]] = 0; }
    if anc_x.len == 0 {
        push_range(xoff, xlim, yoff, ylim, too_expensive == NO_LIMIT);
        return;
    }
    // Patience sorting: each anchor goes on the leftmost pile whose top has
    // a larger new position, linked to the top of the pile before it.
    prev.clear();
    tops.clear();
    for k in anc_y.len {
        let y = anc_y[k];
        var lo: i64 = 0;
        var hi: i64 = tops.len;
        while lo < hi {
            let mid = (lo + hi) / 2;
            if anc_y[tops[mid]] < y { lo = mid + 1; } else { hi = mid; }
        }
        if lo > 0 { prev.push(tops[lo - 1]); } else { prev.push(-1); }
        if lo == tops.len { tops.push(k as i32); } else { tops[lo] = k as i32; }
    }
    keep.clear();
    var k: i64 = tops[tops.len - 1];
    while k >= 0 {
        keep.push(k as i32);
        k = prev[k];
    }
    // keep is last anchor first, which is the order the task stack wants:
    // the gap after the last anchor is pushed first.
    var hx = xlim;
    var hy = ylim;
    for c in keep {
        let ax: i64 = anc_x[c];
        let ay: i64 = anc_y[c];
        push_patience(ax + 1, hx, ay + 1, hy);
        push_moves(OP_EQUAL, 1);
        hx = ax;
        hy = ay;
    }
    push_patience(xoff, hx, yoff, hy);
}

// --- discarding unmatched elements ---------------------------------------
//
// An element that occurs nowhere in the other sequence can be in no common
// subsequence, so a minimal script deletes or inserts it whatever else
// happens. GNU diff drops such lines before its search (discard_confusing_
// lines, the part of it that keeps minimality) and puts them back after.
// The search then sees only elements that can match: on two versions of a
// file, where most changed lines are new, far fewer edits.

var ka: i32[>..] = [];      // kept elements of old, compacted
var kb: i32[>..] = [];
var pa: i32[>..] = [];      // their positions in old
var pb: i32[>..] = [];
var csteps: Step[>..] = []; // the moves over the compacted sequences

// ids is the number of distinct values an element can take.
fn myers_discarding(a, b, too_expensive: i64, ids: i64) {
    cnta.resize(ids, 0);
    cntb.resize(ids, 0);
    for x in a { cnta[x] += 1; }
    for y in b { cntb[y] += 1; }
    // Count first: when nothing can be dropped, as with bytes nearly
    // always, compacting would only copy both inputs.
    var dropped: i64 = 0;
    for x in a { if cntb[x] == 0 { dropped++; } }
    for y in b { if cnta[y] == 0 { dropped++; } }
    if dropped == 0 {
        push_range(0, a.len, 0, b.len, too_expensive == NO_LIMIT);
        run_tasks(a, b, too_expensive);
        return;
    }
    for x, i in a {
        if cntb[x] > 0 { ka.push(x); pa.push(i as i32); }
    }
    for y, j in b {
        if cnta[y] > 0 { kb.push(y); pb.push(j as i32); }
    }
    push_range(0, ka.len, 0, kb.len, too_expensive == NO_LIMIT);
    run_tasks(ka, kb, too_expensive);
    // Back to the original positions: between two equal elements, whatever
    // old and new hold is deleted and inserted.
    for s in steps { csteps.push(s); }
    steps.clear();
    var ci: i64 = 0;
    var cj: i64 = 0;
    var oi: i64 = 0;
    var oj: i64 = 0;
    for s in csteps {
        if s.op == OP_DELETE { ci += s.len; continue; }
        if s.op == OP_INSERT { cj += s.len; continue; }
        for e in s.len {
            let x: i64 = pa[ci + e];
            let y: i64 = pb[cj + e];
            step(OP_DELETE, x - oi);
            step(OP_INSERT, y - oj);
            step(OP_EQUAL, 1);
            oi = x + 1;
            oj = y + 1;
        }
        ci += s.len;
        cj += s.len;
    }
    step(OP_DELETE, a.len - oi);
    step(OP_INSERT, b.len - oj);
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

// ids bounds the element values: N + M + 1 for match() ids, 256 for bytes.
fn diff(a, b, algorithm: i32, max_cost: i64, ids: i64) -> const u8[:] {
    steps.clear();
    runs.clear();
    out.clear();
    trace.clear();
    v.clear();
    back.clear();
    fd.clear();
    bd.clear();
    tasks.clear();
    cnta.clear();
    cntb.clear();
    posb.clear();
    anc_x.clear();
    anc_y.clear();
    prev.clear();
    tops.clear();
    keep.clear();
    ka.clear();
    kb.clear();
    pa.clear();
    pb.clear();
    csteps.clear();
    polls = 0;
    minimal = true;
    if algorithm == ALGORITHM_GREEDY {
        myers_greedy(a, b);
    } else {
        var cost = max_cost;
        if cost < 0 { cost = default_cost(a.len, b.len); }
        if algorithm == ALGORITHM_PATIENCE {
            cnta.resize(ids, 0);
            cntb.resize(ids, 0);
            posb.resize(ids, 0);
            push_patience(0, a.len, 0, b.len);
            // Patience is not minimal in general (design §6.4).
            minimal = false;
            run_tasks(a, b, cost);
        } else {
            myers_discarding(a, b, cost, ids);
        }
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
// Myers, 1 for patience and 9 for the greedy reference; max_cost is the cost limit, -1 for
// the default and NO_LIMIT for a minimal script.
export fn zudiff_diff_ids(a: const i32[:], b: const i32[:], algorithm: i32, max_cost: i64) -> const u8[:] {
    return diff(a, b, algorithm, max_cost, a.len + b.len + 1);
}

export fn zudiff_diff_bytes(a: const u8[:], b: const u8[:], algorithm: i32, max_cost: i64) -> const u8[:] {
    return diff(a, b, algorithm, max_cost, 256);
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
// array's release, so only goose_host_call()'s rewind returns the stack to
// where it was.
export fn zudiff_probe_stack(n: i64, fail: bool) -> i64 {
    var v: i64[>..] = [];
    for i in n { v.push(i); }
    if fail { return v[n]; }
    return v[n - 1];
}
