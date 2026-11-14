#!/usr/bin/env bash
#
# Unit tests for the awk stages in lib/.
#
#   bash tests/run.sh
#
# Every stage is exercised directly, so a logic change fails here instead of
# silently changing the published lists.

set -Eeuo pipefail
export LC_ALL=C

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT_DIR/lib"
FIXTURES="$ROOT_DIR/tests/fixtures"
PSL="$FIXTURES/psl.rules"
TLDS="com net org br ck io app np mm jp"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

passes=0
failures=0

assert_eq() { # name expected actual
  if [[ "$2" == "$3" ]]; then
    passes=$((passes + 1))
    printf '  ok   %s\n' "$1"
  else
    failures=$((failures + 1))
    printf '  FAIL %s\n    expected: %s\n    actual  : %s\n' "$1" "$2" "$3"
  fi
}

extract() { awk -f "$LIB/extract.awk"; }

validate() { # reject_suffix(0|1)
  awk -v tlds="$TLDS" -v psl_rules="$PSL" -v reject_suffix="${1:-0}" \
    -f "$LIB/psl.awk" -f "$LIB/validate.awk"
}

reduce() { awk -f "$LIB/psl.awk" -f "$LIB/reduce.awk"; }

exclude() { # exclusions-file
  awk -v psl_rules="$PSL" -v excluded_file="$1" -f "$LIB/psl.awk" -f "$LIB/exclude.awk"
}

ignore() { # allowignore-file
  awk -v psl_rules="$PSL" -v ignore_file="$1" -f "$LIB/psl.awk" -f "$LIB/ignore.awk"
}

echo "extract.awk"
cat > "$WORK/raw.txt" <<'EOF'
# comment
! adblock comment
0.0.0.0 hosts.example
||adblock.example^
@@||allowed.example^
address=/dnsmasq.example/0.0.0.0
https://url.example/path?q=1
example.com##.banner
example.com#@#.banner
0.0.0.0 multi1.example multi2.example
*.wild.example
port.example:8080
0.0.0.0 inline.example # trailing comment
EOF
assert_eq "multi-format extraction" \
  "hosts.example adblock.example allowed.example dnsmasq.example url.example multi1.example multi2.example wild.example port.example inline.example" \
  "$(extract < "$WORK/raw.txt" | tr '\n' ' ' | sed 's/ $//')"

echo "validate.awk"
cat > "$WORK/candidates.txt" <<'EOF'
good.domain.com
UPPER.Domain.COM
trailing.domain.com.
com
bad_chars.domain.com
-lead.domain.com
ab--cd.domain.com
foo.unknown-tld
domain..com
.example.com
example.com
sub.example.com
xn--fiqs8s.com
EOF
assert_eq "accept/reject rules" \
  "good.domain.com upper.domain.com trailing.domain.com xn--fiqs8s.com" \
  "$(validate 0 < "$WORK/candidates.txt" | tr '\n' ' ' | sed 's/ $//')"

cat > "$WORK/suffixes.txt" <<'EOF'
com.br
foo.com.br
github.io
run.app
EOF
assert_eq "public suffixes dropped from allowlists" "foo.com.br" \
  "$(validate 1 < "$WORK/suffixes.txt" | tr '\n' ' ' | sed 's/ $//')"

cat > "$WORK/icann.txt" <<'EOF'
com.br
github.io
foo.com.br
EOF
assert_eq "ICANN suffixes rejected everywhere, private ones kept" "github.io foo.com.br" \
  "$(validate 0 < "$WORK/icann.txt" | tr '\n' ' ' | sed 's/ $//')"



echo "reduce.awk"
assert_eq "parent kept when child sorts first" "foo.com" \
  "$(printf 'a.foo.com\nfoo.com\n' | reduce | tr '\n' ' ' | sed 's/ $//')"
assert_eq "parent kept when parent sorts first" "foo.com" \
  "$(printf 'foo.com\na.foo.com\n' | reduce | tr '\n' ' ' | sed 's/ $//')"
assert_eq "unrelated entries kept" "bar.com foo.com" \
  "$(printf 'a.foo.com\nbar.com\nfoo.com\n' | reduce | tr '\n' ' ' | sed 's/ $//')"

echo "exclude.awk"
cat > "$WORK/exclusions.txt" <<'EOF'
example.com
com.br
foo.github.io
amazonaws.com
EOF
cat > "$WORK/blocked.txt" <<'EOF'
ads.example.com
com.br
ads.com.br
a.foo.github.io
a.github.io
bucket.s3.amazonaws.com
EOF
assert_eq "allow entry covers itself and subdomains, not whole namespaces" \
  "com.br ads.com.br a.github.io bucket.s3.amazonaws.com" \
  "$(exclude "$WORK/exclusions.txt" < "$WORK/blocked.txt" | tr '\n' ' ' | sed 's/ $//')"

echo "ignore.awk"
cat > "$WORK/allowignore.txt" <<'EOF'
# comment
amazon
adobedc.net
doubleclick
EOF
cat > "$WORK/allow.txt" <<'EOF'
amazon.co.jp
data.adobedc.net
ads.doubleclick.net
notamazon.com
example.com
EOF
assert_eq "brand and suffix patterns" "notamazon.com example.com" \
  "$(ignore "$WORK/allowignore.txt" < "$WORK/allow.txt" | tr '\n' ' ' | sed 's/ $//')"

echo "render.awk"
printf '# title line 1\n# title line 2\n' > "$WORK/title"
mkdir -p "$WORK/out"
printf 'a.example\nb.example\n' | awk -v title_file="$WORK/title" -v out_dir="$WORK/out" -f "$LIB/render.awk"
assert_eq "host format" "0.0.0.0  a.example" "$(sed -n '3p' "$WORK/out/host")"
assert_eq "adblocker format" "||b.example^" "$(sed -n '4p' "$WORK/out/adblocker")"
assert_eq "dnsmasq format" "address=/a.example/0.0.0.0" "$(sed -n '3p' "$WORK/out/dnsmasq.conf")"
assert_eq "smartdns format" "address /b.example/#" "$(sed -n '4p' "$WORK/out/smartdns.conf")"
assert_eq "domain format" "b.example" "$(sed -n '4p' "$WORK/out/domain")"
assert_eq "clash payload header" "payload:" "$(sed -n '3p' "$WORK/out/clash")"
assert_eq "clash entry" "  - 'a.example'" "$(sed -n '4p' "$WORK/out/clash")"
assert_eq "singbox version" '  "version": 1,' "$(sed -n '2p' "$WORK/out/singbox.json")"
assert_eq "singbox suffix list opens" '      "domain_suffix": [' "$(sed -n '5p' "$WORK/out/singbox.json")"
assert_eq "singbox entry separator" '        "a.example",' "$(sed -n '6p' "$WORK/out/singbox.json")"
assert_eq "singbox last entry without comma" '        "b.example"' "$(sed -n '7p' "$WORK/out/singbox.json")"

printf '\n%d passed, %d failed\n' "$passes" "$failures"
(( failures == 0 ))
