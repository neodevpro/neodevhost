# Drop entries that are already covered by a parent in the same list.
#
# Needs two passes over the input: a single "seen" scan makes the result depend
# on input order and can delete the parent instead of the child.

{ present[$0] = 1; row[NR] = $0 }

END {
  for (r = 1; r <= NR; r++) {
    domain = row[r]
    n = psl_parents(domain, label, part)
    redundant = 0
    for (i = 2; i <= n; i++) {
      if (present[part[i]]) { redundant = 1; break }
    }
    if (!redundant) print domain
  }
}
