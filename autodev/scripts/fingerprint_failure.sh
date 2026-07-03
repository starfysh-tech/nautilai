#!/usr/bin/env bash
# Stable-ish fingerprint of a failure log: strip digits and hex runs (line
# numbers, addresses, durations) before hashing sorted unique words, so the
# same failure reproduced twice hashes the same.
set -euo pipefail
LOGFILE="${1:?log file required}"
hash_cmd() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256; else sha256sum; fi
}
sed -E 's/0x[0-9a-fA-F]+//g' < "$LOGFILE" \
  | tr -d '0-9' \
  | tr -cs '[:alpha:]' '\n' \
  | tr '[:upper:]' '[:lower:]' \
  | awk 'length($0) > 0 && $0 !~ /^[a-f]{6,}$/' \
  | sort -u \
  | head -n 200 \
  | hash_cmd \
  | awk '{print $1}'
