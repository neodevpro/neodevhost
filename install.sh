#!/usr/bin/env bash
# Adds the published NEODEV allowlist to Pi-hole.
# The list holds >100k domains, which cannot fit into a single command line
# (ARG_MAX), so it is fed to `pihole allow` in chunks.
set -Eeuo pipefail

LIST_URL="${NEODEV_ALLOWLIST_URL:-https://raw.githubusercontent.com/neodevpro/neodevhost/master/allow}"
CHUNK_SIZE=1000

fail() { echo "Error: $*" >&2; exit 1; }

command -v pihole >/dev/null 2>&1 || fail "pihole command not found; is Pi-hole installed?"
[[ "${EUID:-$(id -u)}" -eq 0 ]] || fail "Run as root, e.g. sudo bash install.sh"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "Downloading allowlist..."
if command -v curl >/dev/null 2>&1; then
  curl --fail --silent --show-error --location --compressed --retry 3 --max-time 180 \
    --output "$WORK_DIR/allow" "$LIST_URL" || fail "Failed to download $LIST_URL"
elif command -v wget >/dev/null 2>&1; then
  wget -q -O "$WORK_DIR/allow" "$LIST_URL" || fail "Failed to download $LIST_URL"
else
  fail "curl or wget is required"
fi
[[ -s "$WORK_DIR/allow" ]] || fail "Downloaded allowlist is empty"
# Mirrors may still serve CRLF; strip it so every argument is a valid domain.
tr -d '\r' < "$WORK_DIR/allow" | sort -u > "$WORK_DIR/allow.clean"
mv "$WORK_DIR/allow.clean" "$WORK_DIR/allow"

# Pi-hole v6 uses `pihole allow`, v5 the legacy `pihole -w`.
if pihole allow --help >/dev/null 2>&1; then
  allow_cmd=(pihole allow --quiet)
else
  allow_cmd=(pihole -w -q)
fi

total=$(wc -l < "$WORK_DIR/allow" | tr -d '[:space:]')
echo "Allowlisting $total domains (this takes a few minutes)..."
xargs -d '\n' -n "$CHUNK_SIZE" "${allow_cmd[@]}" < "$WORK_DIR/allow" >/dev/null

# Allowlisting does not change gravity; `pihole allow` already reloads DNS.
echo "Done! Allowlisted $total domains."