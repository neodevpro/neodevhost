# Keep only syntactically valid, resolvable domains.
#
# Input : candidate tokens from extract.awk
# Output: lowercased domains, one per line (deduplicated by the caller)
#
# Checks: RFC label rules, punycode, IANA TLD membership, public suffix match.
# With reject_suffix=1 (used for allowlists) a bare public suffix such as
# "com.br" or "cloudfront.net" is discarded: it would let one entry suppress a
# whole namespace.
#
# Set reason_file to also log every rejected candidate as "<reason>\t<domain>";
# tests/audit.sh uses it to explain what each upstream source contributes.

BEGIN {
  psl_load()

  count = split(tlds, tld, " ")
  for (i = 1; i <= count; i++) valid_tld[tld[i]] = 1

  split("example.com example.net example.org test localhost invalid local", values, " ")
  for (i in values) reserved[values[i]] = 1
}

# Empty string when the domain is acceptable, otherwise the reason it is not.
function rejection(domain,   n, i, has, parent) {
  if (domain == "" || length(domain) > 253 || domain ~ /[^a-z0-9.-]/ ||
      domain ~ /\.\./ || domain ~ /^\.|\.$/) return "invalid-chars"

  n = split(domain, label, ".")
  if (n < 2) return "single-label"
  if (!valid_tld[label[n]]) return "unknown-tld"

  for (i = 1; i <= n; i++) {
    if (label[i] == "" || length(label[i]) > 63 || label[i] ~ /^-/ || label[i] ~ /-$/) return "invalid-label"
    if (substr(label[i], 3, 2) == "--" && label[i] !~ /^xn--/) return "invalid-label"
  }

  # A bare ICANN suffix (com.br, co.uk, ...) is always a data error: blocking it
  # would take down a whole country namespace. Private suffixes are kept, since
  # blocking e.g. a dynamic-DNS platform is a legitimate choice.
  if (PSL_ICANN[domain]) return "icann-suffix"
  if (reject_suffix && (PSL_SUFFIX[domain] || PSL_WILDCARD[domain])) return "public-suffix"

  psl_parents(domain, label, part)
  has = 0
  for (i = 1; i <= n; i++) {
    if (PSL_SUFFIX[part[i]] || (i < n && PSL_WILDCARD[part[i+1]])) { has = 1; break }
  }
  if (!has) return "no-public-suffix"

  for (parent in reserved) {
    if (domain == parent ||
        (length(domain) > length(parent) &&
         substr(domain, length(domain) - length(parent), 1) == "." &&
         substr(domain, length(domain) - length(parent) + 1) == parent)) return "reserved"
  }
  return ""
}

{
  domain = tolower($0)
  sub(/\r$/, "", domain)
  sub(/^[[:space:]]+/, "", domain)
  sub(/[[:space:]]+$/, "", domain)
  sub(/\.$/, "", domain)

  reason = rejection(domain)
  if (reason == "") {
    print domain
  } else if (reason_file != "") {
    print reason "\t" domain > reason_file
  }
}