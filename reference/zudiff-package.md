# zudiff: Shortest Edit Scripts, Unified Diffs and Patches

Computes the shortest edit script between two sequences (atomic vectors,
raw vectors or the lines of two strings) and returns it as data, with
Myers' algorithm (E. W. Myers (1986)
[doi:10.1007/BF01840446](https://doi.org/10.1007/BF01840446) ) or
patience diff. Builds hunks with context, writes and parses unified
diffs, and applies an edit script or a unified diff. Equality is that of
match(), so missing values, signed zeros, encodings and factor labels
compare as R users expect. The algorithms are written in the 'Goose'
programming language (<https://github.com/aardappel/goose>) and compiled
ahead of time to C, which the package bundles.

## See also

Useful links:

- <https://github.com/pedrobtz/zudiff>

- <https://pedrobtz.github.io/zudiff/>

- Report bugs at <https://github.com/pedrobtz/zudiff/issues>

## Author

**Maintainer**: Pedro Baltazar <pedrobtz@gmail.com> \[copyright holder\]

Authors:

- Pedro Baltazar <pedrobtz@gmail.com> \[copyright holder\]

Other contributors:

- Wouter van Oortmerssen (author of the 'Goose' language and compiler;
  the runtime code the generated C inlines and the runtime pieces in
  src/goose_vendor.c) \[contributor, copyright holder\]
