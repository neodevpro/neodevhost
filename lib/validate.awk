# Keep only syntactically valid, resolvable domains.
#
# Input : candidate tokens from extract.awk
# Output: lowercased domains, one per line (deduplicated by the caller)
#
# Checks: RFC label rules, punycode, IANA TLD membership, public suffix match.
# With reject_suffix=1 (used for allowlists) a bare public suffix such as
# "com.br" or "cloudfront.net" is discarded: it would let one entry suppress a
# whole namespace.

BEGIN {
  psl_load()

  count = split(tlds, tld, " ")
  for (i = 1; i <= count; i++) valid_tld[tld[i]] = 1

  split("example.com example.net example.org test localhost invalid local", values, " ")
  for (i in values) reserved[values[i]] = 1
}

{
  domain = tolower($0)
  sub(/\r$/, "", domain)
  sub(/^[[:space:]]+/, "", domain)
  sub(/[[:space:]]+$/, "", domain)
  sub(/\.$/, "", domain)
  if (domain == "" || length(domain) > 253 || domain ~ /[^a-z0-9.-]/ ||
      domain ~ /\.\./ || domain ~ /^\.|\.$/) next

  n = split(domain, label, ".")
  if (n < 2 || !valid_tld[label[n]]) next

  valid = 1
  for (i = 1; i <= n; i++) {
    if (label[i] == "" || length(label[i]) > 63 || label[i] ~ /^-/ || label[i] ~ /-$/) { valid = 0; break }
    if (substr(label[i], 3, 2) == "--" && label[i] !~ /^xn--/) { valid = 0; break }
  }
  if (!valid) next

  if (reject_suffix && (PSL_SUFFIX[domain] || PSL_WILDCARD[domain])) next

  psl_parents(domain, label, part)
  has_suffix = 0
  for (i = 1; i <= n; i++) {
    if (PSL_SUFFIX[part[i]] || (i < n && PSL_WILDCARD[part[i+1]])) { has_suffix = 1; break }
  }
  if (!has_suffix) next

  for (parent in reserved) {
    if (domain == parent ||
        (length(domain) > length(parent) &&
         substr(domain, length(domain) - length(parent), 1) == "." &&
         substr(domain, length(domain) - length(parent) + 1) == parent)) next
  }
  print domain
}
