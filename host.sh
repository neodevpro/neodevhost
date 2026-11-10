#!/usr/bin/env bash
set -Eeuo pipefail

export LC_ALL=C

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

WORK_DIR="$(mktemp -d "${RUNNER_TEMP:-/tmp}/neodevhost.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

fail() {
  echo "Error: $*" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "Required file not found: $1"
}

for command in awk cat comm date grep mktemp mv sed sort tr uniq wc wget; do
  command -v "$command" >/dev/null 2>&1 || fail "Required command not found: $command"
done

for file in allowlist blocklist title README.md; do
  require_file "$file"
done

echo "Downloading domain data..."

DEADBLOCK_URL="https://raw.githubusercontent.com/FusionPlmH/dead-block/refs/heads/master/deadblock"
TLD_URL="https://data.iana.org/TLD/tlds-alpha-by-domain.txt"
PSL_URL="https://publicsuffix.org/list/public_suffix_list.dat"

fetch_required() {
  local url="$1"
  local output="$2"
  wget -q --tries=3 --timeout=20 --waitretry=2 -O "$output" "$url" || fail "Failed to download $url"
  [[ -s "$output" ]] || fail "Downloaded file is empty: $url"
}

fetch_required "$DEADBLOCK_URL" "$WORK_DIR/deadblock.raw"
fetch_required "$TLD_URL" "$WORK_DIR/tlds"
fetch_required "$PSL_URL" "$WORK_DIR/public_suffix_list.dat"

TLD_LIST=$(tail -n +2 "$WORK_DIR/tlds" | tr '[:upper:]' '[:lower:]' | tr '\n' ' ')
[[ -n "${TLD_LIST// /}" ]] || fail "IANA TLD list contains no TLDs"
grep -qvE '^(//|[[:space:]]*$)' "$WORK_DIR/public_suffix_list.dat" || fail "Public Suffix List contains no rules"

process_sources() {
  local source_file="$1"
  local output_file="$2"
  local list_file="$WORK_DIR/${2}.list"
  local raw_file="$WORK_DIR/${2}.raw"
  local download_file="$WORK_DIR/${2}.download"
  local url
  local fetched=0

  sed -e 's/\r$//' \
      -e 's/^[[:space:]]*//' \
      -e 's/[[:space:]]*$//' \
      -e '/^#/d' \
      -e '/^$/d' \
      "$source_file" > "$list_file"

  : > "$raw_file"

  while IFS= read -r url || [[ -n "$url" ]]; do
    if wget -q --tries=2 --timeout=20 --waitretry=2 -O "$download_file" "$url" && [[ -s "$download_file" ]]; then
      cat "$download_file" >> "$raw_file"
      printf '\n' >> "$raw_file"
      fetched=$((fetched + 1))
    else
      echo "Warning: unable to fetch source; skipping: $url" >&2
    fi
  done < "$list_file"

  (( fetched > 0 )) || fail "No sources could be downloaded from $source_file"
  [[ -s "$raw_file" ]] || fail "All downloaded sources were empty for $source_file"

  sed -E \
    -e 's/\r$//' \
    -e '/^[[:space:]]*(#|!|\[|$)/d' \
    -e 's/^[[:space:]]*0\.0\.0\.0[[:space:]]+//' \
    -e 's/^[[:space:]]*127\.[0-9.]+[[:space:]]+//' \
    -e 's/^[[:space:]]*::[[:space:]]+//' \
    -e 's/^[[:space:]]*address=\\///' \
    -e 's/\\/0\\.0\\.0\\.0[[:space:]]*$//' \
    -e 's/^\|\|//' \
    -e 's/\^.*$//' \
    -e 's/^[[:space:]]+//' \
    -e 's/[[:space:]].*$//' \
    "$raw_file" > "$WORK_DIR/${2}.candidates"

  normalize_and_validate < "$WORK_DIR/${2}.candidates" > "$WORK_DIR/$output_file"
}

normalize_and_validate() {
  local idn_cmd="cat"
  if command -v idn >/dev/null 2>&1; then
    idn_cmd="idn --quiet"
  fi

  # shellcheck disable=SC2086
  $idn_cmd |
    awk -v tlds="$TLD_LIST" -v psl_file="$WORK_DIR/public_suffix_list.dat" '
      BEGIN {
        ntld = split(tlds, tld_values, " ")
        for (i = 1; i <= ntld; i++) valid_tld[tld_values[i]] = 1

        while ((getline rule < psl_file) > 0) {
          sub(/\r$/, "", rule)
          if (rule == "" || rule ~ /^\/\//) continue
          if (substr(rule, 1, 1) == "!") {
            exception[substr(rule, 2)] = 1
            continue
          }
          if (substr(rule, 1, 2) == "*.") {
            wildcard[substr(rule, 3)] = 1
            continue
          }
          public_suffix[rule] = 1
        }
        close(psl_file)

        split("example.com example.net example.org test localhost invalid local", reserved_values, " ")
        for (i in reserved_values) reserved[reserved_values[i]] = 1
      }

      {
        domain = tolower($0)
        sub(/\r$/, "", domain)
        sub(/^[[:space:]]+|[[:space:]]+$/, "", domain)
        sub(/\.$/, "", domain)

        if (domain == "") next
        if (length(domain) > 253 || domain ~ /[^a-z0-9.-]/ || domain ~ /\.\./ || domain ~ /^\.|\.$/) next

        n = split(domain, labels, ".")
        if (n < 2 || !valid_tld[labels[n]]) next

        valid = 1
        for (i = 1; i <= n; i++) {
          if (labels[i] == "" || length(labels[i]) > 63 || labels[i] ~ /^-/ || labels[i] ~ /-$/) {
            valid = 0
            break
          }
          if (substr(labels[i], 3, 2) == "--" && labels[i] !~ /^xn--/) {
            valid = 0
            break
          }
        }
        if (!valid) next

        suffix_found = 0
        for (i = 1; i <= n; i++) {
          suffix = ""
          for (j = i; j <= n; j++) {
            suffix = suffix (suffix == "" ? "" : ".") labels[j]
          }
          if (public_suffix[suffix]) suffix_found = 1
          if (i < n) {
            wildcard_base = ""
            for (j = i + 1; j <= n; j++) {
              wildcard_base = wildcard_base (wildcard_base == "" ? "" : ".") labels[j]
            }
            if (wildcard[wildcard_base]) suffix_found = 1
          }
        }
        if (!suffix_found) next

        reject = 0
        for (parent in reserved) {
          if (domain == parent || (length(domain) > length(parent) && substr(domain, length(domain) - length(parent), 1) == "." && substr(domain, length(domain) - length(parent) + 1) == parent)) {
            reject = 1
            break
          }
        }
        if (!reject) print domain
      }
    ' | sort -u
}

process_sources allowlist allow
process_sources blocklist block

normalize_and_validate < "$WORK_DIR/deadblock.raw" > "$WORK_DIR/deadblock"
[[ -s "$WORK_DIR/deadblock" ]] || fail "Downloaded deadblock list contains no valid domains"

remove_redundant_subdomains() {
  awk -F. '
    {
      domains[$0] = 1
      entries[NR] = $0
    }
    END {
      for (line = 1; line <= NR; line++) {
        domain = entries[line]
        n = split(domain, labels, ".")
        redundant = 0
        for (i = 2; i <= n; i++) {
          parent = ""
          for (j = i; j <= n; j++) {
            parent = parent (parent == "" ? "" : ".") labels[j]
          }
          if (domains[parent]) {
            redundant = 1
            break
          }
        }
        if (!redundant) print domain
      }
    }
  ' | sort -u
}

for list in allow block deadblock; do
  remove_redundant_subdomains < "$WORK_DIR/$list" > "$WORK_DIR/${list}.reduced"
  mv "$WORK_DIR/${list}.reduced" "$WORK_DIR/$list"
done

cat "$WORK_DIR/allow" "$WORK_DIR/deadblock" | sort -u > "$WORK_DIR/exclusions"

awk '
  FNR == NR {
    excluded[$0] = 1
    next
  }
  {
    domain = $0
    blocked = 0
    while (domain != "") {
      if (excluded[domain]) {
        blocked = 1
        break
      }
      if (domain !~ /\./) break
      sub(/^[^.]+\./, "", domain)
    }
    if (!blocked) print $0
  }
' "$WORK_DIR/exclusions" "$WORK_DIR/block" | sort -u > "$WORK_DIR/host.domains"

block_count=$(wc -l < "$WORK_DIR/host.domains" | tr -d '[:space:]')
allow_count=$(wc -l < "$WORK_DIR/allow" | tr -d '[:space:]')
dead_count=$(wc -l < "$WORK_DIR/deadblock" | tr -d '[:space:]')
update_date=$(date '+%Y-%m-%d')

cp title "$WORK_DIR/title"

awk -v date="$update_date" -v count="$block_count" '
  /^# Last update:/ { print "# Last update: " date; next }
  /^# Number of domains:/ { print "# Number of domains: " count; next }
  { print }
' "$WORK_DIR/title" > "$WORK_DIR/title.updated"

mv "$WORK_DIR/title.updated" "$WORK_DIR/title"

make_output() {
  local file="$1"
  local mode="$2"

  case "$mode" in
    host)
      : > "$WORK_DIR/$file"
      while IFS= read -r domain; do
        printf '0.0.0.0  %s\n' "$domain" >> "$WORK_DIR/$file"
      done < "$WORK_DIR/host.domains"
      ;;
    adblocker)
      : > "$WORK_DIR/$file"
      while IFS= read -r domain; do
        printf '||%s^\n' "$domain" >> "$WORK_DIR/$file"
      done < "$WORK_DIR/host.domains"
      ;;
    dnsmasq)
      : > "$WORK_DIR/$file"
      while IFS= read -r domain; do
        printf 'address=/%s/0.0.0.0\n' "$domain" >> "$WORK_DIR/$file"
      done < "$WORK_DIR/host.domains"
      ;;
    smartdns)
      : > "$WORK_DIR/$file"
      while IFS= read -r domain; do
        printf 'address /%s/#\n' "$domain" >> "$WORK_DIR/$file"
      done < "$WORK_DIR/host.domains"
      ;;
    domain)
      cp "$WORK_DIR/host.domains" "$WORK_DIR/$file"
      ;;
    clash)
      {
        printf 'payload:\n'
        while IFS= read -r domain; do
          printf "  - '%s'\n" "$domain"
        done < "$WORK_DIR/host.domains"
      } > "$WORK_DIR/$file"
      ;;
    *)
      fail "Unknown output mode: $mode"
      ;;
  esac
}

make_output host host
make_output adblocker adblocker
make_output dnsmasq dnsmasq.conf
make_output smartdns smartdns.conf
make_output domain domain
make_output clash clash

cp "$WORK_DIR/host.domains" "$ROOT_DIR/host"
cp "$WORK_DIR/allow" "$ROOT_DIR/allow"
cp "$WORK_DIR/block" "$ROOT_DIR/block"
cp "$WORK_DIR/deadblock" "$ROOT_DIR/deadblock"
cp "$WORK_DIR/title" "$ROOT_DIR/title"
cp "$WORK_DIR/adblocker" "$ROOT_DIR/adblocker"
cp "$WORK_DIR/dnsmasq.conf" "$ROOT_DIR/dnsmasq.conf"
cp "$WORK_DIR/smartdns.conf" "$ROOT_DIR/smartdns.conf"
cp "$WORK_DIR/domain" "$ROOT_DIR/domain"
cp "$WORK_DIR/clash" "$ROOT_DIR/clash"

awk -v blocked="$block_count" -v allowed="$allow_count" -v dead="$dead_count" -v date="$update_date" '
  /Total ad \/ tracking block list/ { sub(/[0-9]+$/, blocked); print; next }
  /Total allowlist list/ { sub(/[0-9]+$/, allowed); print; next }
  /Total upstream-non-accessable list/ { sub(/[0-9]+$/, dead); print; next }
  /^Update 更新时间:/ { sub(/[0-9]{4}-[0-9]{2}-[0-9]{2}$/, date); print; next }
  /^Number of Domain 域名数目：/ { sub(/[0-9]+$/, blocked); print; next }
  { print }
' README.md > "$WORK_DIR/README.md"

cp "$WORK_DIR/README.md" "$ROOT_DIR/README.md"

echo "Done! Blocked: ${block_count}; allowed: ${allow_count}; deadblock: ${dead_count}."
