#!/usr/bin/env bash
# Tests for commitcraft-release-detect-rp.sh — the "is release-please actually
# functional?" gate. Self-contained: builds throwaway fixture repos in a tmpdir,
# stubs `gh` for deterministic/offline history checks, asserts RP_STATUS.
#
# Run: bash commitcraft/tests/detect-rp.test.sh   (exit 0 = all pass)
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/commitcraft-release-detect-rp.sh"
STUBS="$HERE/stubs"

PASS=0
FAIL=0

# status_of <fixture-dir> -> echoes FUNCTIONAL|DISABLED|ABSENT
status_of() {
    ( cd "$1" && bash "$SCRIPT" ) | sed -n 's/^RP_STATUS: //p'
}

# assert <name> <expected> <actual>
assert() {
    if [ "$2" = "$3" ]; then
        PASS=$((PASS + 1)); printf '  ok   %-44s -> %s\n' "$1" "$3"
    else
        FAIL=$((FAIL + 1)); printf '  FAIL %-44s expected %s, got %s\n' "$1" "$2" "$3"
    fi
}

WF_DIR=".github/workflows"
FUNCTIONAL_WF=$'name: Release Please\non:\n  push:\n    branches: [main]\npermissions:\n  contents: write\n  pull-requests: write\njobs:\n  release-please:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: googleapis/release-please-action@v4\n'

mk() {  # mk <dir>  — create a fixture dir with the functional workflow as a base
    local d="$TMP/$1"
    mkdir -p "$d/$WF_DIR"
    printf '%s' "$FUNCTIONAL_WF" > "$d/$WF_DIR/release-please.yml"
    echo "$d"
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "detect-rp tests"

# Covers the main decision branches plus the two regex-guarded ones most prone to
# regression (write-all bypass, commented-out skip flag). Not exhaustive — the gh-
# unavailable and monorepo-mixed-version paths are exercised live, not here.

# 1. No release-please at all -> ABSENT
d="$TMP/absent"; mkdir -p "$d"
assert "absent: no workflow" ABSENT "$(status_of "$d")"

# 2. Functional config + real version -> FUNCTIONAL
d="$(mk functional)"; echo '{".": "1.4.2"}' > "$d/.release-please-manifest.json"
assert "functional: write perms + real version" FUNCTIONAL "$(PATH="$STUBS:$PATH" status_of "$d")"

# 3. skip-github-* flag -> DISABLED
d="$(mk skip_release)"; printf '%s\n' "          skip-github-release: true" >> "$d/$WF_DIR/release-please.yml"
assert "disabled: skip-github flag" DISABLED "$(status_of "$d")"

# 4. permissions block without contents: write -> DISABLED
d="$TMP/readonly"; mkdir -p "$d/$WF_DIR"
printf 'name: RP\non:\n  push:\n    branches: [main]\npermissions:\n  contents: read\njobs:\n  release-please:\n    steps:\n      - uses: googleapis/release-please-action@v4\n' > "$d/$WF_DIR/release-please.yml"
assert "disabled: permissions lack contents:write" DISABLED "$(status_of "$d")"

# 5. manifest 0.0.0 + no release-please history -> DISABLED (never cut a release)
d="$(mk manifest_zero)"; echo '{".": "0.0.0"}' > "$d/.release-please-manifest.json"
assert "disabled: 0.0.0 + no RP history" DISABLED "$(PATH="$STUBS:$PATH" STUB_GH_LABELS="" status_of "$d")"

# 6. manifest 0.0.0 BUT autorelease labels exist -> FUNCTIONAL (don't hijack a working RP)
d="$(mk zero_but_history)"; echo '{".": "0.0.0"}' > "$d/.release-please-manifest.json"
assert "functional: 0.0.0 but RP labels exist" FUNCTIONAL "$(PATH="$STUBS:$PATH" STUB_GH_LABELS="autorelease: pending" status_of "$d")"

# 7. permissions: write-all -> FUNCTIONAL (grants contents:write without naming it)
d="$TMP/write_all"; mkdir -p "$d/$WF_DIR"
printf 'name: RP\non:\n  push:\n    branches: [main]\npermissions: write-all\njobs:\n  release-please:\n    steps:\n      - uses: googleapis/release-please-action@v4\n' > "$d/$WF_DIR/release-please.yml"
echo '{".": "1.4.2"}' > "$d/.release-please-manifest.json"
assert "functional: permissions write-all" FUNCTIONAL "$(PATH="$STUBS:$PATH" status_of "$d")"

# 8. commented-out skip flag must NOT match (the [^#]* guard) -> FUNCTIONAL
d="$(mk commented_skip)"; printf '%s\n' "          # skip-github-release: true" >> "$d/$WF_DIR/release-please.yml"
echo '{".": "1.4.2"}' > "$d/.release-please-manifest.json"
assert "functional: skip flag is commented out" FUNCTIONAL "$(PATH="$STUBS:$PATH" status_of "$d")"

echo ""
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
