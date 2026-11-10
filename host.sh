#!/usr/bin/env bash
set -Eeuo pipefail

export LC_ALL=C

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/neodevhost.XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT

fail() {
  echo "Error: $*" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "Required file not found: $1"
}

for command in wget awk sort comm sed grep wc date mktemp; do
  command -v "$command" >/dev/null 2>&1 || fail "Required command not found: $command"
done

require_file allowlist
require_file blocklist
require_file title
require_file README.md

echo "Clean..."

# Download the upstream non-accessible domain list on every run.
DEADBLOCK_URL="https://raw.githubusercontent.com/FusionPlmH/dead-block/refs/heads/master/deadblock"
wget -q --tries=3 --timeout=15 -O "$WORK_DIR/deadblock" "$DEADBLOCK_URL" || fail "Failed to download deadblock from $DEADBLOCK_URL"
[[ -s "$WORK_DIR/deadblock" ]] || fail "Downloaded deadblock list is empty"

# Fetch and validate the TLD and Public Suffix List data before processing.
TLD_URL="https://data.iana.org/TLD/tlds-alpha-by-domain.txt"
PSL_URL="https://publicsuffix.org/list/public_suffix_list.dat"
wget -q --tries=3 --timeout=15 -O "$WORK_DIR/tlds" "$TLD_URL" || fail "Failed to download IANA TLD list"
wget -q --tries=3 --timeout=15 -O "$WORK_DIR/public_suffix_list.dat" "$PSL_URL" || fail "Failed to download Public Suffix List"
grep -qv '^#\|^$' "$WORK_DIR/tlds" || fail "Downloaded IANA TLD list is empty"
grep -qv '^//\|^$' "$WORK_DIR/public_suffix_list.dat" || fail "Downloaded Public Suffix List is empty"
TLD_LIST=$(tail -n +2 "$WORK_DIR/tlds" | tr '[:upper:]' '[:lower:]' | tr '\n' ' ')

# Fetch each source independently so parallel downloads cannot interleave data.
process_list() {
    local input_list=$1 output_file=$2 raw_file="$WORK_DIR/${2}.raw" url_file="$WORK_DIR/${2}.urls"
    echo "Merging $output_file..."
    : > "$raw_file"
    sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^#/d' -e '/^$/d' "$input_list" > "$url_file"
    while IFS= read -r url; do
        if ! wget -q --tries=2 --timeout=15 -O "$WORK_DIR/source" "$url"; then
            echo "Warning: failed to fetch $url; skipping" >&2
            continue
        fi
        cat "$WORK_DIR/source" >> "$raw_file"
    done < "$url_file"

    sed -E '/^[[:space:]]*#/d; /:/d; s/[0-9.]+[[:space:]]+//g; /^[^[:space:]]+\.[^[:space:]]+$/!d' "$raw_file" |
      awk -F. -v tlds="$TLD_LIST" 'BEGIN { n=split(tlds, arr, " "); for (i=1; i<=n; i++) validTLD[arr[i]]=1 }
        { if (validTLD[tolower($NF)]) print tolower($0) }' |
      sort -u > "$WORK_DIR/$output_file"
}

process_list "allowlist" "allow"
process_list "blocklist" "block"

RESERVED_DOMAINS="example.com example.net example.org test localhost invalid local"
echo "Validating domain format (RFC, IDN, PSL, reserved)..."

idn_convert() {
  if command -v idn >/dev/null 2>&1; then
    idn --quiet
  else
    cat
  fi
}

domain_name_regex='^([a-zA-Z0-9]+(-[a-zA-Z0-9]+)*\.)+([a-zA-Z]{2,}|xn--[a-zA-Z0-9-]+)$'

validate_psl() {
  awk -v psl_file="$WORK_DIR/public_suffix_list.dat" '
    BEGIN {
      while ((getline line < psl_file) > 0) {
        sub(/\r$/, "", line)
        if (line ~ /^\/\// || line ~ /^$/) continue
        psl[tolower(line)] = 1
      }
      close(psl_file)
    }
    {
      n = split($0, labels, ".")
      for (i = 2; i <= n; i++) {
        suffix = ""
        for (j = i; j <= n; j++) suffix = suffix (suffix == "" ? "" : ".") labels[j]
        if (psl[tolower(suffix)]) { print $0; break }
      }
    }'
}

filter_reserved_blocked() {
  awk -v reserved="$RESERVED_DOMAINS" '
    BEGIN { count=split(reserved, values, " "); for (i=1; i<=count; i++) blocked[values[i]]=1 }
    {
      reject=0
      for (domain in blocked) {
        if ($0 == domain || (length($0) > length(domain) && substr($0, length($0)-length(domain), 1) == "." && substr($0, length($0)-length(domain)+1) == domain)) {
          reject=1; break
        }
      }
      if (!reject) print
    }'
}

filter_domains() {
  awk '
    length($0) <= 253 && $0 !~ /[^a-zA-Z0-9.-]/ && $0 !~ /\.\./ &&
    $0 !~ /^\.|\.$/ && $0 !~ /\.local$|\.localhost$|\.invalid$|\.test$/ {
      n=split($0, labels, "."); valid=1
      for (i=1; i<=n; i++) {
        if (labels[i] == "" || length(labels[i]) > 63 || labels[i] ~ /^-/ || labels[i] ~ /-$/) { valid=0; break }
        if (substr(labels[i], 3, 2) == "--" && labels[i] !~ /^xn--/) { valid=0; break }
      }
      if (labels[n] ~ /^[0-9]+$/) valid=0
      if (valid) print $0
    }'
}

normalize_domains() {
  awk '{ d=tolower($0); sub(/\r$/, "", d); sub(/\.$/, "", d); print d }'
}

clean_domains() {
  idn_convert |
    normalize_domains |
    grep -E "$domain_name_regex" |
    filter_domains |
    filter_reserved_blocked |
    validate_psl |
    sort -u
}

clean_domains < "$WORK_DIR/allow" > "$WORK_DIR/clean_allow"
clean_domains < "$WORK_DIR/block" > "$WORK_DIR/clean_block"
clean_domains < "$WORK_DIR/deadblock" > "$WORK_DIR/clean_deadblock"

# Keep a domain only if no parent domain is present in the same list.
remove_redundant_subdomains() {
  awk -F. '
    { domains[$0]=1; lines[NR]=$0 }
    END {
      for (line=1; line<=NR; line++) {
        domain=lines[line]; n=split(domain, labels, "."); redundant=0
        for (i=2; i<=n; i++) {
          parent=""
          for (j=i; j<=n; j++) parent=parent (parent == "" ? "" : ".") labels[j]
          if (domains[parent]) { redundant=1; break }
        }
        if (!redundant) print domain
      }
    }' | sort -u
}

remove_redundant_subdomains < "$WORK_DIR/clean_allow" > "$WORK_DIR/allow"
remove_redundant_subdomains < "$WORK_DIR/clean_block" > "$WORK_DIR/block"
remove_redundant_subdomains < "$WORK_DIR/clean_deadblock" > "$WORK_DIR/deadblock"

# Exclude allowed and upstream-non-accessible domains from the block set.
sort -u "$WORK_DIR/allow" "$WORK_DIR/deadblock" > "$WORK_DIR/excluded"
comm -23 "$WORK_DIR/block" "$WORK_DIR/excluded" > "$WORK_DIR/host"

block_count=$(wc -l < "$WORK_DIR/host" | tr -d ' ')
allow_count=$(wc -l < "$WORK_DIR/allow" | tr -d ' ')
dead_count=$(wc -l < "$WORK_DIR/deadblock" | tr -d ' ')
update_date=$(date '+%Y-%m-%d')

# Update the generated title using a temporary copy, preserving the checked-in source.
cp title "$WORK_DIR/title"
sed -i "9c# Last update: ${update_date}" "$WORK_DIR/title"
sed -i "11c# Number of domains: ${block_count}" "$WORK_DIR/title"
header_lines=$(wc -l < "$WORK_DIR/title" | tr -d ' ')
data_line=$((header_lines + 1))

# Generate each output from the same canonical host set.
for file in host adblocker dnsmasq.conf smartdns.conf domain clash block; do
  cat "$WORK_DIR/title" "$WORK_DIR/host" > "$WORK_DIR/$file"
done

# Apply each consumer's rule format only to domain lines.
sed -i -e "${data_line},\$s/^/||&/" -e "${data_line},\$s/\$ /\^/" -e "${data_line},\$s/\$/\^/" adblocker
sed -i -e "${data_line},\$s/^/0.0.0.0  &/" host
sed -i -e "${data_line},\$s/^/address=\\//" -e "${data_line},\$s/\$/\\/0.0.0.0/" dnsmasq.conf
sed -i -e "${data_line},\$s/^/address \\/" -e "${data_line},\$s/\$/\\/#/" smartdns.conf
clash_payload_line=$((data_line))
sed -i -e "${clash_payload_line}i payload:" -e "$((clash_payload_line + 1)),\$s/^/  - '/" -e "$((clash_payload_line + 1)),\$s/\$/ '/" clash

# Publish the refreshed download and validated lists after successful processing.
cp "$WORK_DIR/deadblock" deadblock.downloaded
mv deadblock.downloaded deadblock
cp "$WORK_DIR/allow" allow
cp "$WORK_DIR/block" block
cp "$WORK_DIR/title" title
cp "$WORK_DIR/host" host.domains

# Update README statistics.
sed -i -e "14cTotal ad / tracking block list 屏蔽追踪广告总数: ${block_count}" \
       -e "16cTotal allowlist list 允许名单总数: ${allow_count}" \
       -e "18cTotal upstream-non-accessable list 上游无法访问域名总数: ${dead_count}" \
       -e "20cUpdate 更新时间: ${update_date}" \
       -e "46cNumber of Domain 域名数目： ${block_count}" README.md

echo "Done! Blocked: ${block_count}; allowed: ${allow_count}; deadblock: ${dead_count}."
