#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"
WORK_DIR="$(mktemp -d "${RUNNER_TEMP:-/tmp}/neodevhost.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

fail() { echo "Error: $*" >&2; exit 1; }
for command in awk cat date grep mktemp mv sort tail tr wc wget; do
  command -v "$command" >/dev/null 2>&1 || fail "Required command not found: $command"
done
for file in allowlist blocklist title README.md; do
  [[ -f "$file" ]] || fail "Required file not found: $file"
done

fetch_required() {
  local url="$1" output="$2"
  wget -q --tries=3 --timeout=20 --waitretry=2 -O "$output" "$url" || fail "Failed to download $url"
  [[ -s "$output" ]] || fail "Downloaded file is empty: $url"
}

echo "Downloading TLD, PSL, and deadblock data..."
fetch_required "https://data.iana.org/TLD/tlds-alpha-by-domain.txt" "$WORK_DIR/tlds"
fetch_required "https://publicsuffix.org/list/public_suffix_list.dat" "$WORK_DIR/psl"
fetch_required "https://raw.githubusercontent.com/FusionPlmH/dead-block/refs/heads/master/deadblock" "$WORK_DIR/deadblock.raw"
TLD_LIST=$(tail -n +2 "$WORK_DIR/tlds" | tr '[:upper:]' '[:lower:]' | tr '\n' ' ')
[[ -n "${TLD_LIST// /}" ]] || fail "IANA TLD list contains no TLDs"

# Parse common plain-domain, hosts, dnsmasq, and adblock list formats.
extract_candidates() {
  awk '
    {
      sub(/\r$/, "")
      line=$0
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line == "" || line ~ /^#/ || line ~ /^!/ || line ~ /^\[/) next

      if (line ~ /^address=\//) {
        sub(/^address=\//, "", line)
        sub(/\/[^/]*$/, "", line)
      } else if (line ~ /^\|\|/) {
        sub(/^\|\|/, "", line)
        sub(/[\^$].*$/, "", line)
      } else {
        sub(/^(0\.0\.0\.0|127\.[0-9.]+|::)[[:space:]]+/, "", line)
      }

      count=split(line, fields, /[[:space:]]+/)
      for (i=1; i<=count; i++) {
        candidate=fields[i]
        sub(/[\^$].*$/, "", candidate)
        if (candidate != "" && candidate !~ /^#/ && candidate !~ /^!/ && candidate !~ /^\[/) print candidate
      }
    }
  '
}

normalize_and_validate() {
  local input="$1" output="$2"
  if command -v idn >/dev/null 2>&1; then
    idn --quiet < "$input" > "$WORK_DIR/idn.out" || cp "$input" "$WORK_DIR/idn.out"
    input="$WORK_DIR/idn.out"
  fi

  awk -v tlds="$TLD_LIST" -v psl_file="$WORK_DIR/psl" '
    BEGIN {
      count=split(tlds, tld, " ")
      for (i=1; i<=count; i++) valid_tld[tld[i]]=1
      while ((getline rule < psl_file) > 0) {
        sub(/\r$/, "", rule)
        if (rule == "" || rule ~ /^\/\//) continue
        if (substr(rule,1,2) == "*.") wildcard[substr(rule,3)]=1
        else if (substr(rule,1,1) != "!") suffix[rule]=1
      }
      close(psl_file)
      split("example.com example.net example.org test localhost invalid local", values, " ")
      for (i in values) reserved[values[i]]=1
    }
    {
      domain=tolower($0)
      sub(/\r$/, "", domain)
      sub(/^[[:space:]]+/, "", domain)
      sub(/[[:space:]]+$/, "", domain)
      sub(/\.$/, "", domain)
      if (domain == "" || length(domain)>253 || domain ~ /[^a-z0-9.-]/ || domain ~ /\.\./ || domain ~ /^\.|\.$/) next
      n=split(domain, label, ".")
      if (n<2 || !valid_tld[label[n]]) next
      valid=1
      for (i=1; i<=n; i++) {
        if (label[i]=="" || length(label[i])>63 || label[i] ~ /^-/ || label[i] ~ /-$/) { valid=0; break }
        if (substr(label[i],3,2)=="--" && label[i] !~ /^xn--/) { valid=0; break }
      }
      if (!valid) next

      has_suffix=0
      for (i=1; i<=n; i++) {
        part=""
        for (j=i; j<=n; j++) part=part (part=="" ? "" : ".") label[j]
        if (suffix[part]) has_suffix=1
        if (i<n) {
          base=""
          for (j=i+1; j<=n; j++) base=base (base=="" ? "" : ".") label[j]
          if (wildcard[base]) has_suffix=1
        }
      }
      if (!has_suffix) next
      reject=0
      for (parent in reserved) {
        if (domain==parent || (length(domain)>length(parent) && substr(domain,length(domain)-length(parent),1)=="." && substr(domain,length(domain)-length(parent)+1)==parent)) { reject=1; break }
      }
      if (!reject) print domain
    }
  ' "$input" | sort -u > "$output"
}

process_source_file() {
  local source_file="$1" name="$2"
  local raw="$WORK_DIR/${name}.raw" url_file="$WORK_DIR/${name}.urls" download="$WORK_DIR/${name}.download"
  local url fetched=0
  awk '{sub(/\r$/, ""); sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, ""); if ($0!="" && $0 !~ /^#/) print}' "$source_file" > "$url_file"
  : > "$raw"
  while IFS= read -r url || [[ -n "$url" ]]; do
    if wget -q --tries=2 --timeout=20 --waitretry=2 -O "$download" "$url" && [[ -s "$download" ]]; then
      cat "$download" >> "$raw"
      printf '\n' >> "$raw"
      fetched=$((fetched + 1))
    else
      echo "Warning: source unavailable, skipped: $url" >&2
    fi
  done < "$url_file"
  (( fetched > 0 )) || fail "No sources could be downloaded from $source_file"
  extract_candidates < "$raw" > "$WORK_DIR/${name}.candidates"
  normalize_and_validate "$WORK_DIR/${name}.candidates" "$WORK_DIR/$name"
}

process_source_file allowlist allow
process_source_file blocklist block
extract_candidates < "$WORK_DIR/deadblock.raw" > "$WORK_DIR/deadblock.candidates"
normalize_and_validate "$WORK_DIR/deadblock.candidates" "$WORK_DIR/deadblock"
[[ -s "$WORK_DIR/deadblock" ]] || fail "Downloaded deadblock list contains no valid domains"

remove_redundant_subdomains() {
  awk -F. '
    { present[$0]=1; row[NR]=$0 }
    END {
      for (r=1; r<=NR; r++) {
        domain=row[r]; n=split(domain, label, "."); redundant=0
        for (i=2; i<=n; i++) {
          parent=""
          for (j=i; j<=n; j++) parent=parent (parent=="" ? "" : ".") label[j]
          if (present[parent]) { redundant=1; break }
        }
        if (!redundant) print domain
      }
    }
  ' | sort -u
}
for list in allow block deadblock; do
  remove_redundant_subdomains < "$WORK_DIR/$list" > "$WORK_DIR/$list.reduced"
  mv "$WORK_DIR/$list.reduced" "$WORK_DIR/$list"
done

# Exclude blocked entries covered by an allowlist or upstream dead-domain entry.
cat "$WORK_DIR/allow" "$WORK_DIR/deadblock" | sort -u > "$WORK_DIR/exclusions"
awk '
  FNR==NR { excluded[$0]=1; next }
  {
    domain=$0; omit=0
    while (domain!="") {
      if (excluded[domain]) { omit=1; break }
      if (domain !~ /\./) break
      sub(/^[^.]+\./, "", domain)
    }
    if (!omit) print
  }
' "$WORK_DIR/exclusions" "$WORK_DIR/block" | sort -u > "$WORK_DIR/host.domains"

block_count=$(wc -l < "$WORK_DIR/host.domains" | tr -d '[:space:]')
allow_count=$(wc -l < "$WORK_DIR/allow" | tr -d '[:space:]')
dead_count=$(wc -l < "$WORK_DIR/deadblock" | tr -d '[:space:]')
update_date=$(date '+%Y-%m-%d')

awk -v date="$update_date" -v count="$block_count" '
  /^# Last update:/ { print "# Last update: " date; next }
  /^# Number of domains:/ { print "# Number of domains: " count; next }
  { print }
' title > "$WORK_DIR/title"

make_output() {
  local filename="$1" mode="$2" domain
  {
    cat "$WORK_DIR/title"
    case "$mode" in clash) printf 'payload:\n';; esac
    while IFS= read -r domain; do
      case "$mode" in
        host) printf '0.0.0.0  %s\n' "$domain" ;;
        adblocker) printf '||%s^\n' "$domain" ;;
        dnsmasq) printf 'address=/%s/0.0.0.0\n' "$domain" ;;
        smartdns) printf 'address /%s/#\n' "$domain" ;;
        domain) printf '%s\n' "$domain" ;;
        clash) printf "  - '%s'\n" "$domain" ;;
      esac
    done < "$WORK_DIR/host.domains"
  } > "$WORK_DIR/$filename"
}
make_output host host
make_output adblocker adblocker
make_output dnsmasq.conf dnsmasq
make_output smartdns.conf smartdns
make_output domain domain
make_output clash clash
cp "$WORK_DIR/host.domains" "$WORK_DIR/block"

awk -v blocked="$block_count" -v allowed="$allow_count" -v dead="$dead_count" -v date="$update_date" '
  /Total ad \/ tracking block list/ { sub(/[0-9]+$/, blocked); print; next }
  /Total allowlist list/ { sub(/[0-9]+$/, allowed); print; next }
  /Total upstream-non-accessable list/ { sub(/[0-9]+$/, dead); print; next }
  /^Update 更新时间:/ { sub(/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/, date); print; next }
  /^Number of Domain 域名数目：/ { sub(/[0-9]+$/, blocked); print; next }
  { print }
' README.md > "$WORK_DIR/README.md"

# Publish only after all inputs and outputs have been validated/generated.
for file in title README.md allow block deadblock host adblocker dnsmasq.conf smartdns.conf domain clash; do
  mv "$WORK_DIR/$file" "$ROOT_DIR/$file"
done

echo "Done! Blocked: $block_count; allowed: $allow_count; deadblock: $dead_count."
