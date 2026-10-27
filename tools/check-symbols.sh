#!/bin/sh
# Fails if the built shared object links a symbol CRAN's compiled-code
# check rejects: anything that can end the R process or write to the
# process's own streams. The stock Goose runtime uses all of these, and
# goose_r_runtime.c exists to keep them out, so a Goose bump or a new
# runtime piece in goose_vendor.c must not bring one back.
#
#   tools/check-symbols.sh path/to/zudiff.so      # Linux, macOS
#   tools/check-symbols.sh src/*.o                # Windows, after building

set -eu
[ $# -ge 1 ] || { echo "usage: $0 <shared object or objects>..." >&2; exit 2; }
# On Windows pass the package's object files (src/*.o), not the DLL: every
# MinGW DLL links the C runtime's start-up code, which imports abort and
# fwrite whatever the package does.
status=0
for so in "$@"; do
  # MinGW imports through __imp_ names, and writes printf as
  # __mingw_vfprintf on __acrt_iob_func's streams.
  bad=$(nm -u "$so" | awk '{print $NF}' | sed -e 's/@.*//' -e 's/^__imp_//' |
    grep -E '^_?(abort|exit|_exit|_Exit|quick_exit|stdout|stderr|__stdoutp|__stderrp|__iob_func|__acrt_iob_func|printf|puts|putchar|fprintf|vprintf|vfprintf|__mingw_v?f?printf|fputs|fputc|fwrite|sprintf|vsprintf|__mingw_v?sprintf|rand|srand|random|srandom)$' || true)
  if [ -n "$bad" ]; then
    echo "forbidden symbols in $so:" >&2
    echo "$bad" >&2
    status=1
  else
    echo "no forbidden symbols in $so"
  fi
done
exit "$status"
