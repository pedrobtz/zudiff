# An O(NM) edit-distance reference, independent of the core: the distance
# with insertions and deletions only is length(a) + length(b) - 2 LCS. Each
# row of the LCS table is one vectorised step, using
# L[i, j] = cummax_j(max(L[i - 1, j], L[i - 1, j - 1] + match)).

reference_distance <- function(a, b) {
  n <- length(a)
  m <- length(b)
  if (n == 0L || m == 0L) {
    return(n + m)
  }
  ids <- match(c(a, b), c(a, b))
  ia <- ids[seq_len(n)]
  ib <- ids[n + seq_len(m)]
  prev <- integer(m + 1L)
  for (i in seq_len(n)) {
    hit <- ia[[i]] == ib
    cand <- pmax(prev[-1L], ifelse(hit, prev[-(m + 1L)] + 1L, 0L))
    prev <- c(0L, cummax(cand))
  }
  n + m - 2L * prev[[m + 1L]]
}

greedy_distance <- function(a, b) {
  zudiff:::diff_vec_impl(a, b, "myers", 9L, Inf)$distance
}
