# Public Suffix List helpers shared by every pass.
#
# host.sh pre-normalizes the list into "<flags> <suffix>" lines:
#   i  com.br    exact rule from the ICANN section
#   iw ck        wildcard rule (*.ck) from the ICANN section
#   p  github.io exact rule from the PRIVATE section
#   pw run.app   wildcard rule from the PRIVATE section
#
# The rule file is passed in `psl_rules`; call psl_load() from BEGIN.
# Arrays must be supplied by the caller because awk passes them by reference.

function psl_load(   rule, fields) {
  if (psl_loaded) return
  while ((getline rule < psl_rules) > 0) {
    split(rule, fields, " ")
    PSL_SUFFIX[fields[2]] = 1
    if (fields[1] ~ /w$/) PSL_WILDCARD[fields[2]] = 1
    if (fields[1] ~ /^i/) PSL_ICANN[fields[2]] = 1
  }
  close(psl_rules)
  psl_loaded = 1
}

# Fill PARTS[1..n] with every label suffix of `domain` (PARTS[1] is the domain
# itself, PARTS[n] the TLD) and return the label count.
function psl_parents(domain, LABELS, PARTS,   n, i) {
  n = split(domain, LABELS, ".")
  for (i = n; i >= 1; i--) {
    PARTS[i] = (i == n) ? LABELS[i] : LABELS[i] "." PARTS[i+1]
  }
  return n
}

# Number of labels of the longest matching public suffix; 0 when nothing matches.
function psl_suffix_labels_of(PARTS, n,   i) {
  for (i = 1; i <= n; i++) {
    if (PSL_SUFFIX[PARTS[i]]) return n - i + 1
    if (i < n && PSL_WILDCARD[PARTS[i+1]]) return n - i + 1
  }
  return 0
}

function psl_suffix_labels(domain, LABELS, PARTS,   n) {
  n = psl_parents(domain, LABELS, PARTS)
  return psl_suffix_labels_of(PARTS, n)
}

# Label count of the registrable domain (eTLD+1).
function psl_registrable_labels(domain, LABELS, PARTS) {
  return psl_suffix_labels(domain, LABELS, PARTS) + 1
}