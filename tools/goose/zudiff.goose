// zudiff's diff core, written in Goose (https://github.com/aardappel/goose)
// and compiled to C by tools/regenerate.sh. The generated C is what the
// package builds; this file is its source. Never edit src/zudiff_goose.c
// by hand.
//
// Stage 1 holds only test hooks. The diff algorithms arrive in Stage 2
// (.agents/roadmap.md).

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
