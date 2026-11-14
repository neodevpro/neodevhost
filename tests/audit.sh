#!/usr/bin/env bash
#
# Audit the pipeline: what every upstream source contributes, and why the rest
# of its lines are dropped. Also re-checks the published block list.
#
#   bash tests/audit.sh
#
# Requires network. Reuses the same stages as host.sh, so the numbers match the
# build exactly.

set -Eeuo pipefail
export LC_ALL=C

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091  # path is resolved at runtime
source "$ROOT_DIR/host.sh"

check_requirements
setup_work_dir
detect_tools
stage_reference_data

printf '\n%-40s %8s %9s %8s   %s\n' "source" "lines" "cand" "valid" "top rejects"
printf '%s\n' "------------------------------------------------------------------------------------------------"

audit_source() { # url mode
  local url="$1" mode="$2"
  local page="$WORK_DIR/audit.page" cands="$WORK_DIR/audit.cands" ok="$WORK_DIR/audit.ok" rej="$WORK_DIR/audit.rej"
  local reject_suffix=0 raw cand valid reasons

  [[ "$mode" == "allow" ]] && reject_suffix=1
  rm -f "$page" "$cands" "$ok" "$rej"

  if ! download "$url" "$page" || [[ ! -s "$page" ]]; then
    printf '%-40s %8s %9s %8s   %s\n' "${url##*/}" "-" "-" "-" "DOWNLOAD FAILED"
    return 0
  fi

  raw=$(count_lines "$page")
  awk -f "$LIB_DIR/extract.awk" "$page" | sort -u > "$cands"
  cand=$(count_lines "$cands")
  awk -v tlds="$TLD_LIST" -v psl_rules="$WORK_DIR/psl.rules" -v reject_suffix="$reject_suffix" \
      -v reason_file="$rej" -f "$LIB_DIR/psl.awk" -f "$LIB_DIR/validate.awk" "$cands" > "$ok"
  valid=$(count_lines "$ok")

  reasons=""
  if [[ -f "$rej" ]]; then
    reasons=$(awk -F'\t' '{ print $1 }' "$rej" | sort | uniq -c | sort -rn | head -3 |
      awk '{ printf "%s=%s ", $2, $1 }')
  fi
  printf '%-40s %8s %9s %8s   %s\n' "${url##*/} (${mode:0:1})" "$raw" "$cand" "$valid" "$reasons"
}

if [[ "${AUDIT_SKIP_SOURCES:-0}" != "1" ]]; then
  printf '%s\n' "-- blocklists --"
  while IFS= read -r url; do audit_source "$url" block; done < <(read_urls blocklist)
  printf '\n%s\n' "-- allowlists --"
  while IFS= read -r url; do audit_source "$url" allow; done < <(read_urls allowlist)
fi

# ---------------------------------------------------------------------------
# Published list invariants
# ---------------------------------------------------------------------------

fails=0
check() { # label expected actual
  if [[ "$2" == "$3" ]]; then
    printf '  ok    %s (%s)\n' "$1" "$3"
  else
    fails=$((fails + 1))
    printf '  FAIL  %s (expected %s, got %s)\n' "$1" "$2" "$3"
  fi
}

BLOCK="$ROOT_DIR/block"
if [[ ! -f "$BLOCK" ]]; then
  printf '\nNo published block list found; skipping invariants.\n'
  exit 0
fi

total=$(count_lines "$BLOCK")
printf '\n%s\n' "-- published block list: $total domains --"

dups=$(sort "$BLOCK" | uniq -d | count_lines)
check "no duplicates" 0 "$dups"

invalid=$(awk -v tlds="$TLD_LIST" -v psl_rules="$WORK_DIR/psl.rules" -v reject_suffix=0 \
  -f "$LIB_DIR/psl.awk" -f "$LIB_DIR/validate.awk" "$BLOCK" | count_lines)
check "every entry passes validation" "$total" "$invalid"

redundant=$(awk -f "$LIB_DIR/psl.awk" -f "$LIB_DIR/reduce.awk" "$BLOCK" | sort -u | count_lines)
printf '  note  entries covered by a parent in the same list: %s (own-list overrides)\n' "$(( total - redundant ))"

cat "$ROOT_DIR/allow" "$ROOT_DIR/deadblock" | sort -u > "$WORK_DIR/pub.exclusions"
survivors=$(awk -v psl_rules="$WORK_DIR/psl.rules" -v excluded_file="$WORK_DIR/pub.exclusions" \
  -f "$LIB_DIR/psl.awk" -f "$LIB_DIR/exclude.awk" "$BLOCK" | count_lines)
printf '  note  entries also matched by allow/deadblock: %s (should all be ownblocklist ones)\n' "$(( total - survivors ))"

cat > "$WORK_DIR/classify-suffixes.awk" <<'AWK'
BEGIN { psl_load() }
{
  if (PSL_ICANN[$0]) print "icann\t" $0
  else if (PSL_SUFFIX[$0] || PSL_WILDCARD[$0]) print "private\t" $0
}
AWK
awk -v psl_rules="$WORK_DIR/psl.rules" -f "$LIB_DIR/psl.awk" -f "$WORK_DIR/classify-suffixes.awk" "$BLOCK" \
  > "$WORK_DIR/block.suffixes"
icann=$(awk -F'\t' '$1 == "icann"' "$WORK_DIR/block.suffixes" | count_lines)
private=$(awk -F'\t' '$1 == "private"' "$WORK_DIR/block.suffixes" | count_lines)
check "no ICANN public suffix is blocked" 0 "$icann"
printf '  note  blocked entries that are private public suffixes: %s' "$private"
if (( private > 0 )); then
  printf ' (e.g. %s)' "$(awk -F'\t' '$1 == "private" { print $2 }' "$WORK_DIR/block.suffixes" | head -n 3 | tr '\n' ' ')"
fi
printf '\n'

printf '\n%d invariant(s) failed\n' "$fails"
(( fails == 0 ))