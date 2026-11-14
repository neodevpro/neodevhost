#!/usr/bin/env bash
#
# Build the neodevhost block lists.
#
# Usage:
#   ./host.sh              fetch, build and publish
#   ./host.sh --dry-run    fetch and build, publish nothing (keeps the work dir)
#   ./host.sh --help
#
# Environment:
#   NEODEV_MIN_BLOCK_RATIO  block list must reach this % of the previous run (90)
#   NEODEV_MIN_ALLOW_RATIO  allow list must reach this % of the previous run (50)
#   NEODEV_MIN_PSL_RULES    minimum public suffix rules expected (5000)
#   NEODEV_MIN_TLDS         minimum IANA TLDs expected (1000)
#   KEEP_WORK_DIR=1         keep the temporary build directory
#
# Pipeline:
#   reference data -> source lists -> allowignore -> prune -> exclusions
#   -> sanity gates -> render -> publish
#
# Each stage writes into $WORK_DIR; the published files are only replaced after
# every gate has passed, so a failed build never leaves a half-written repo.

set -Eeuo pipefail
export LC_ALL=C

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$ROOT_DIR/lib"
cd "$ROOT_DIR"

TLD_URL="https://data.iana.org/TLD/tlds-alpha-by-domain.txt"
PSL_URL="https://publicsuffix.org/list/public_suffix_list.dat"
DEADBLOCK_URL="https://raw.githubusercontent.com/FusionPlmH/dead-block/refs/heads/master/deadblock"

MIN_BLOCK_RATIO="${NEODEV_MIN_BLOCK_RATIO:-90}"
MIN_ALLOW_RATIO="${NEODEV_MIN_ALLOW_RATIO:-50}"
MIN_PSL_RULES="${NEODEV_MIN_PSL_RULES:-5000}"
MIN_TLDS="${NEODEV_MIN_TLDS:-1000}"

PUBLISHED=(title README.md allow block deadblock host adblocker dnsmasq.conf smartdns.conf domain clash)

DRY_RUN=0
FETCH_TOOL=""
IDN_TOOL=""
TLD_LIST=""
WORK_DIR=""
block_count=0
allow_count=0
dead_count=0

log() { printf '%s\n' "$*"; }
warn() { printf 'Warning: %s\n' "$*" >&2; }
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }

count_lines() {
  if (( $# > 0 )); then
    wc -l < "$1" | tr -d '[:space:]'
  else
    wc -l | tr -d '[:space:]'
  fi
}

cleanup() {
  [[ -n "$WORK_DIR" ]] || return 0
  if (( DRY_RUN )) || [[ "${KEEP_WORK_DIR:-0}" == "1" ]]; then
    warn "Build directory kept: $WORK_DIR"
  else
    rm -rf "$WORK_DIR"
  fi
}

parse_args() {
  while (( $# > 0 )); do
    case "$1" in
      -n|--dry-run) DRY_RUN=1 ;;
      -h|--help) usage; exit 0 ;;
      *) fail "Unknown argument: $1 (try --help)" ;;
    esac
    shift
  done
}

usage() {
  cat <<'EOF'
Usage: ./host.sh [--dry-run|--help]

  --dry-run   fetch and build, publish nothing (keeps the work directory)

Environment:
  NEODEV_MIN_BLOCK_RATIO  block list must reach this % of the previous run (90)
  NEODEV_MIN_ALLOW_RATIO  allow list must reach this % of the previous run (50)
  NEODEV_MIN_PSL_RULES    minimum public suffix rules expected (5000)
  NEODEV_MIN_TLDS         minimum IANA TLDs expected (1000)
  KEEP_WORK_DIR=1         keep the temporary build directory
EOF
}

check_requirements() {
  local command file
  for command in awk cat comm cp date grep head mktemp mv sed sort tail tr wc; do
    command -v "$command" >/dev/null 2>&1 || fail "Required command not found: $command"
  done
  for file in allowlist blocklist ownallowlist ownblocklist title README.md; do
    [[ -f "$file" ]] || fail "Required file not found: $file"
  done
  for file in psl.awk extract.awk validate.awk ignore.awk reduce.awk exclude.awk render.awk; do
    [[ -f "$LIB_DIR/$file" ]] || fail "Required library not found: lib/$file"
  done
}

setup_work_dir() {
  WORK_DIR="$(mktemp -d "${RUNNER_TEMP:-/tmp}/neodevhost.XXXXXX")"
  trap cleanup EXIT
  mkdir -p "$WORK_DIR/out"
}

detect_tools() {
  if command -v curl >/dev/null 2>&1; then
    FETCH_TOOL=curl
  elif command -v wget >/dev/null 2>&1; then
    FETCH_TOOL=wget
  else
    fail "Required command not found: curl or wget"
  fi

  local candidate
  for candidate in idn2 idn; do
    if command -v "$candidate" >/dev/null 2>&1; then
      IDN_TOOL="$candidate"
      break
    fi
  done
  [[ -n "$IDN_TOOL" ]] || warn "Neither idn2 nor idn found; non-ASCII domains will be dropped"
}

download() { # url output
  case "$FETCH_TOOL" in
    curl)
      curl --fail --silent --show-error --location --compressed \
        --connect-timeout 10 --max-time 120 --retry 3 --retry-delay 2 \
        --output "$2" "$1" ;;
    wget)
      wget -q --tries=3 --timeout=20 --waitretry=2 -O "$2" "$1" ;;
  esac
}

download_required() { # url output
  download "$1" "$2" || fail "Failed to download $1"
  [[ -s "$2" ]] || fail "Downloaded file is empty: $1"
}

# One source URL per line, ignoring blanks and comments.
read_urls() {
  awk '{ sub(/\r$/, ""); sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, ""); if ($0 != "" && $0 !~ /^#/) print }' "$1"
}

# --------------------------------------------------------------------------
# Stage: reference data
# --------------------------------------------------------------------------

stage_reference_data() {
  log "Fetching TLD, PSL and deadblock data..."
  download_required "$TLD_URL" "$WORK_DIR/tlds.raw"
  download_required "$PSL_URL" "$WORK_DIR/psl.raw"
  download_required "$DEADBLOCK_URL" "$WORK_DIR/deadblock.raw"

  TLD_LIST=$(tail -n +2 "$WORK_DIR/tlds.raw" | tr '[:upper:]' '[:lower:]' | tr '\n' ' ')
  local tld_count
  tld_count=$(printf '%s' "$TLD_LIST" | tr ' ' '\n' | grep -c '[a-z0-9]' || true)
  (( tld_count >= MIN_TLDS )) || fail "IANA TLD list looks truncated ($tld_count entries)"

  # Normalize to "<e|w> <suffix>" (e = exact, w = wildcard base) so every awk
  # pass reads the same cheap representation.
  awk -v out="$WORK_DIR/psl.rules" '
    /^\/\// { next }
    {
      sub(/\r$/, "")
      if ($0 == "" || $0 ~ /^!/) next
      if (substr($0, 1, 2) == "*.") print "w " substr($0, 3) > out
      else print "e " $0 > out
    }
  ' "$WORK_DIR/psl.raw"

  local psl_count
  psl_count=$(count_lines "$WORK_DIR/psl.rules")
  (( psl_count >= MIN_PSL_RULES )) || fail "Public suffix list looks truncated ($psl_count rules)"
}

# --------------------------------------------------------------------------
# Stage: source lists
# --------------------------------------------------------------------------

# extract.awk -> validate.awk -> sort -u
normalize_candidates() { # input output [mode]
  local input="$1" output="$2" mode="${3:-}"
  local reject_suffix=0
  [[ "$mode" == "allow" ]] && reject_suffix=1

  if [[ -n "$IDN_TOOL" ]]; then
    if ! "$IDN_TOOL" --quiet < "$input" > "$WORK_DIR/idn.out" 2>/dev/null; then
      cp "$input" "$WORK_DIR/idn.out"
    fi
    input="$WORK_DIR/idn.out"
  fi

  awk -f "$LIB_DIR/extract.awk" "$input" \
    | awk -v tlds="$TLD_LIST" -v psl_rules="$WORK_DIR/psl.rules" -v reject_suffix="$reject_suffix" \
        -f "$LIB_DIR/psl.awk" -f "$LIB_DIR/validate.awk" \
    | sort -u > "$output"
}

# Download every URL of a list file, then normalize the merged result.
build_list() { # list-file output-name mode
  local source_file="$1" name="$2" mode="$3"
  local raw="$WORK_DIR/$name.raw" urls_file="$WORK_DIR/$name.urls" page="$WORK_DIR/$name.page"
  local url fetched=0 expected

  read_urls "$source_file" > "$urls_file"
  expected=$(count_lines "$urls_file")

  : > "$raw"
  while IFS= read -r url || [[ -n "$url" ]]; do
    if download "$url" "$page" && [[ -s "$page" ]]; then
      cat "$page" >> "$raw"
      printf '\n' >> "$raw"
      fetched=$((fetched + 1))
    else
      warn "source unavailable, skipped: $url"
    fi
  done < "$urls_file"

  (( fetched > 0 )) || fail "No sources could be downloaded from $source_file"
  (( fetched == expected )) || warn "$source_file: only $fetched/$expected sources downloaded"

  normalize_candidates "$raw" "$WORK_DIR/$name" "$mode"
  [[ -s "$WORK_DIR/$name" ]] || fail "No valid domains extracted from $source_file"
}

# Upstream allowlists must not be able to whitelist the brands in allowignore.
apply_allowignore() {
  [[ -f allowignore ]] || return 0

  local before after
  before=$(count_lines "$WORK_DIR/allow")

  awk -v psl_rules="$WORK_DIR/psl.rules" -v ignore_file="allowignore" \
    -f "$LIB_DIR/psl.awk" -f "$LIB_DIR/ignore.awk" "$WORK_DIR/allow" > "$WORK_DIR/allow.filtered"

  after=$(count_lines "$WORK_DIR/allow.filtered")
  if (( after < before )); then
    log "allowignore: dropped $((before - after)) upstream allow entries"
  fi
  mv "$WORK_DIR/allow.filtered" "$WORK_DIR/allow"
}

# The project's own lists are read from this checkout, so local edits take
# effect immediately instead of waiting for a push to GitHub.
build_own_lists() {
  normalize_candidates ownallowlist "$WORK_DIR/own.allow"
  normalize_candidates ownblocklist "$WORK_DIR/own.block"
  [[ -s "$WORK_DIR/own.allow" ]] || fail "No valid domains found in ownallowlist"
  [[ -s "$WORK_DIR/own.block" ]] || fail "No valid domains found in ownblocklist"

  sort -u "$WORK_DIR/allow" "$WORK_DIR/own.allow" > "$WORK_DIR/allow.merged"
  mv "$WORK_DIR/allow.merged" "$WORK_DIR/allow"
}

stage_sources() {
  build_list allowlist allow allow
  apply_allowignore
  build_list blocklist block block
  build_own_lists
  normalize_candidates "$WORK_DIR/deadblock.raw" "$WORK_DIR/deadblock"
  [[ -s "$WORK_DIR/deadblock" ]] || fail "Downloaded deadblock list contains no valid domains"
}

# --------------------------------------------------------------------------
# Stage: prune and exclude
# --------------------------------------------------------------------------

stage_prune() {
  local list
  for list in allow block deadblock; do
    awk -f "$LIB_DIR/psl.awk" -f "$LIB_DIR/reduce.awk" "$WORK_DIR/$list" \
      | sort -u > "$WORK_DIR/$list.reduced"
    mv "$WORK_DIR/$list.reduced" "$WORK_DIR/$list"
  done
}

apply_exclusions() { # stdin: domains
  awk -v psl_rules="$WORK_DIR/psl.rules" -v excluded_file="$WORK_DIR/exclusions" \
    -f "$LIB_DIR/psl.awk" -f "$LIB_DIR/exclude.awk"
}

stage_exclusions() {
  cat "$WORK_DIR/allow" "$WORK_DIR/deadblock" | sort -u > "$WORK_DIR/exclusions"
  apply_exclusions < "$WORK_DIR/block" | sort -u > "$WORK_DIR/host.domains"

  # ownblocklist wins even when an upstream allowlist covers its parent domain;
  # the conflicts are reported so the sources can be fixed.
  apply_exclusions < "$WORK_DIR/own.block" | sort -u > "$WORK_DIR/own.unblocked"
  local suppressed
  suppressed=$(comm -23 "$WORK_DIR/own.block" "$WORK_DIR/own.unblocked" | count_lines)

  sort -u "$WORK_DIR/host.domains" "$WORK_DIR/own.block" > "$WORK_DIR/host.domains.merged"
  mv "$WORK_DIR/host.domains.merged" "$WORK_DIR/host.domains"

  if (( suppressed > 0 )); then
    warn "$suppressed ownblocklist entries are covered by an allowlist entry; they were kept anyway:"
    comm -23 "$WORK_DIR/own.block" "$WORK_DIR/own.unblocked" | head -n 10 | sed 's/^/  /' >&2
  fi
}

# --------------------------------------------------------------------------
# Stage: sanity gates
# --------------------------------------------------------------------------

guard_shrink() { # published-file current-count min-ratio
  local name="$1" current="$2" min_ratio="$3" previous=0 ratio
  if [[ -f "$name" ]]; then
    previous=$(count_lines "$name")
  fi
  (( previous > 0 )) || return 0

  ratio=$(( current * 100 / previous ))
  if (( ratio < min_ratio )); then
    fail "$name shrank from $previous to $current domains (${ratio}%); refusing to publish" \
      "(intentional? set NEODEV_MIN_${name^^}_RATIO)"
  fi
}

stage_check() {
  block_count=$(count_lines "$WORK_DIR/host.domains")
  allow_count=$(count_lines "$WORK_DIR/allow")
  dead_count=$(count_lines "$WORK_DIR/deadblock")

  (( block_count > 0 )) || fail "Refusing to publish an empty block list"
  guard_shrink block "$block_count" "$MIN_BLOCK_RATIO"
  guard_shrink allow "$allow_count" "$MIN_ALLOW_RATIO"
}

# --------------------------------------------------------------------------
# Stage: render
# --------------------------------------------------------------------------

update_title() { # date
  awk -v date="$1" -v count="$block_count" '
    /^# Last update:/ { print "# Last update: " date; next }
    /^# Number of domains:/ { print "# Number of domains: " count; next }
    { print }
  ' title > "$WORK_DIR/out/title"
}

update_readme() { # date
  awk -v blocked="$block_count" -v allowed="$allow_count" -v dead="$dead_count" -v date="$1" '
    /Total ad \/ tracking block list/ { sub(/[0-9]+$/, blocked); print; next }
    /Total allowlist list/ { sub(/[0-9]+$/, allowed); print; next }
    /Total upstream-non-accessable list/ { sub(/[0-9]+$/, dead); print; next }
    /^Update 更新时间:/ { sub(/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/, date); print; next }
    /^Number of Domain 域名数目：/ { sub(/[0-9]+$/, blocked); print; next }
    { print }
  ' README.md > "$WORK_DIR/out/README.md"

  grep -q "总数: $block_count" "$WORK_DIR/out/README.md" \
    || fail "README.md summary lines could not be updated (did the wording change?)"
}

stage_render() {
  local update_date
  update_date=$(date '+%Y-%m-%d')

  update_title "$update_date"
  awk -v title_file="$WORK_DIR/out/title" -v out_dir="$WORK_DIR/out" \
    -f "$LIB_DIR/render.awk" "$WORK_DIR/host.domains"

  cp "$WORK_DIR/host.domains" "$WORK_DIR/out/block"
  cp "$WORK_DIR/allow" "$WORK_DIR/out/allow"
  cp "$WORK_DIR/deadblock" "$WORK_DIR/out/deadblock"
  update_readme "$update_date"
}

# --------------------------------------------------------------------------
# Stage: publish
# --------------------------------------------------------------------------

stage_publish() {
  local file
  if (( DRY_RUN )); then
    log "Dry run: nothing published."
    return 0
  fi
  for file in "${PUBLISHED[@]}"; do
    [[ -s "$WORK_DIR/out/$file" ]] || fail "Output is missing or empty: $file"
  done
  for file in "${PUBLISHED[@]}"; do
    mv "$WORK_DIR/out/$file" "$ROOT_DIR/$file"
  done
}

main() {
  parse_args "$@"
  check_requirements
  setup_work_dir
  detect_tools

  stage_reference_data
  stage_sources
  stage_prune
  stage_exclusions
  stage_check
  stage_render
  stage_publish

  log "Done! Blocked: $block_count; allowed: $allow_count; deadblock: $dead_count."
}

main "$@"