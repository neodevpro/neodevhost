# Turn any supported list format into one candidate hostname per line.
#
# Handles plain domain lists, hosts files, dnsmasq.conf, Adblock/AdGuard network
# rules (including @@ exceptions), URL lists, and anything separated by spaces
# or commas. Purely cosmetic rules are dropped: they carry no DNS information
# and would otherwise block a whole site because of one banner selector.

{
  sub(/\r$/, "")
  line = $0
  sub(/^[[:space:]]+/, "", line)
  sub(/[[:space:]]+$/, "", line)
  if (line == "" || line ~ /^#/ || line ~ /^!/ || line ~ /^\/\// || line ~ /^\[/) next
  if (line ~ /##/ || line ~ /#@#/ || line ~ /#\?#/ || line ~ /#\$#/) next
  sub(/[[:space:]]#.*$/, "", line)

  if (line ~ /^(address|server)=\//) {
    sub(/^(address|server)=\//, "", line)
    sub(/\/.*$/, "", line)
  } else {
    sub(/^(0\.0\.0\.0|127\.[0-9.]+|::1|::)[[:space:]]+/, "", line)
    sub(/^@@/, "", line)
    sub(/^\|\|/, "", line)
    sub(/^\|/, "", line)
  }

  count = split(line, fields, /[[:space:],]+/)
  for (i = 1; i <= count; i++) {
    candidate = fields[i]
    if (candidate == "" || candidate ~ /^#/ || candidate ~ /^!/) continue
    sub(/^@@/, "", candidate)
    sub(/^\|\|/, "", candidate)
    sub(/^\|/, "", candidate)

    # Full URLs: keep the host, drop scheme, credentials, path, query, fragment.
    if (candidate ~ /^[[:alpha:]][[:alnum:].+-]*:\/\//) sub(/^[[:alpha:]][[:alnum:].+-]*:\/\//, "", candidate)
    else if (candidate ~ /^\/\//) sub(/^\/\//, "", candidate)
    if (candidate ~ /@/) sub(/^.*@/, "", candidate)
    sub(/[\/?#].*$/, "", candidate)
    sub(/:[0-9]+$/, "", candidate)
    sub(/[\^$|;,].*$/, "", candidate)
    sub(/^\*\./, "", candidate)
    sub(/^\./, "", candidate)
    sub(/[.]$/, "", candidate)
    if (candidate != "" && candidate !~ /^#/ && candidate !~ /^!/) print candidate
  }
}
