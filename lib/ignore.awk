# Drop upstream allowlist entries that name a brand listed in `allowignore`.
#
# Upstream whitelists routinely contain vendor root domains (google.com,
# doubleclick.net, ...). Honouring those would make it impossible to block any
# ad host below them, so they are discarded here instead.
#
# Two patterns are supported:
#   <brand>          matches the brand label of the registrable domain, so
#                    `amazon` covers amazon.com, amazon.es, amazon.co.jp
#   <domain>         matches the entry itself or any subdomain of it, so
#                    `adobedc.net` covers data.adobedc.net

BEGIN {
  psl_load()

  while ((getline pattern < ignore_file) > 0) {
    sub(/\r$/, "", pattern)
    sub(/#.*$/, "", pattern)
    sub(/^[[:space:]]+/, "", pattern)
    sub(/[[:space:]]+$/, "", pattern)
    if (pattern != "") ignored[pattern] = 1
  }
  close(ignore_file)
}

{
  n = psl_parents($0, label, part)
  suffix_labels = psl_suffix_labels_of(part, n)

  omit = 0
  if (n - suffix_labels >= 1 && label[n - suffix_labels] in ignored) omit = 1
  if (!omit) {
    for (pattern in ignored) {
      if ($0 == pattern ||
          (length($0) > length(pattern) && substr($0, length($0) - length(pattern)) == "." pattern)) {
        omit = 1
        break
      }
    }
  }
  if (!omit) print
}
