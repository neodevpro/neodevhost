# Remove blocked domains that an allowlist or dead-domain entry covers.
#
# An entry may suppress itself and any subdomain of itself, but never a whole
# namespace above the registrable domain: `com.br` must not cancel every
# *.com.br ad domain, and `cloudfront.net` must not cancel every hosted one.

BEGIN {
  psl_load()

  while ((getline domain < excluded_file) > 0) excluded[domain] = 1
  close(excluded_file)
}

{
  n = psl_parents($0, label, part)
  suffix_labels = psl_suffix_labels_of(part, n)

  # Lowest level an allow entry may match at: the registrable domain.
  lowest = n - (suffix_labels + 1) + 1

  omit = 0
  for (i = lowest; i >= 1; i--) {
    if (excluded[part[i]]) { omit = 1; break }
  }
  if (!omit) print
}
