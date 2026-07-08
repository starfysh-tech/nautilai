#!/usr/bin/env bash
# Tests for commitcraft-pr-template.sh — PR-template detection and GitHub's
# resolution order. Self-contained: builds throwaway fixture dirs in a tmpdir
# (deliberately NOT git repos, so the script's git-root lookup falls back to the
# fixture dir). Offline, no stubs.
#
# COVERAGE NOTE: this exercises the mechanical detection only. Semantic template
# FILLING and the "infer which of several templates from the PR title" step live in
# workflows/pr.md (they need the diff and the title) and are not unit-testable here.
#
# Run: bash commitcraft/tests/pr-template.test.sh   (exit 0 = all pass)
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/commitcraft-pr-template.sh"

PASS=0
FAIL=0

# status_of <dir> -> echoes STATUS value (FOUND|MULTIPLE|NONE)
status_of() {
    ( cd "$1" && bash "$SCRIPT" ) | sed -n 's/^STATUS: //p'
}
# path_of <dir> -> echoes the first PATH value
path_of() {
    ( cd "$1" && bash "$SCRIPT" ) | sed -n 's/^PATH: //p' | head -n 1
}
# npaths <dir> -> echoes the count of PATH lines
npaths() {
    ( cd "$1" && bash "$SCRIPT" ) | grep -c '^PATH: ' || true
}

assert() {  # assert <name> <expected> <actual>
    if [ "$2" = "$3" ]; then
        PASS=$((PASS + 1)); printf '  ok   %-46s -> %s\n' "$1" "$3"
    else
        FAIL=$((FAIL + 1)); printf '  FAIL %-46s expected %s, got %s\n' "$1" "$2" "$3"
    fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "pr-template tests"

# 1. No template anywhere -> NONE
d="$TMP/none"; mkdir -p "$d"
assert "none: empty repo" NONE "$(status_of "$d")"

# 2. .github/ single file -> FOUND
d="$TMP/dotgithub"; mkdir -p "$d/.github"; touch "$d/.github/pull_request_template.md"
assert "found: .github single file" FOUND "$(status_of "$d")"
assert "found: .github path" ".github/pull_request_template.md" "$(path_of "$d")"

# 3. repo root single file -> FOUND
d="$TMP/root"; mkdir -p "$d"; touch "$d/pull_request_template.md"
assert "found: root single file" FOUND "$(status_of "$d")"
assert "found: root path" "pull_request_template.md" "$(path_of "$d")"

# 4. docs/ single file -> FOUND
d="$TMP/docs"; mkdir -p "$d/docs"; touch "$d/docs/pull_request_template.md"
assert "found: docs single file" FOUND "$(status_of "$d")"

# 5. precedence: .github/ wins when a root copy also exists
d="$TMP/prec"; mkdir -p "$d/.github"; touch "$d/pull_request_template.md" "$d/.github/pull_request_template.md"
assert "precedence: .github over root" ".github/pull_request_template.md" "$(path_of "$d")"

# 6. case-insensitive filename (GitHub matches PULL_REQUEST_TEMPLATE.md)
d="$TMP/case"; mkdir -p "$d"; touch "$d/PULL_REQUEST_TEMPLATE.md"
assert "found: uppercase filename" FOUND "$(status_of "$d")"

# 7. PULL_REQUEST_TEMPLATE/ dir with >1 file -> MULTIPLE, all listed
d="$TMP/multi"; mkdir -p "$d/.github/PULL_REQUEST_TEMPLATE"
touch "$d/.github/PULL_REQUEST_TEMPLATE/feature.md" "$d/.github/PULL_REQUEST_TEMPLATE/bugfix.md"
assert "multiple: dir of two templates" MULTIPLE "$(status_of "$d")"
assert "multiple: both paths listed" 2 "$(npaths "$d")"

# 8. PULL_REQUEST_TEMPLATE/ dir with exactly one file -> degrades to FOUND
d="$TMP/multi_one"; mkdir -p "$d/.github/PULL_REQUEST_TEMPLATE"
touch "$d/.github/PULL_REQUEST_TEMPLATE/only.md"
assert "found: dir with a single template" FOUND "$(status_of "$d")"

# 9. a dir of choices outranks a lone single file (author put effort into choices)
d="$TMP/mixed"; mkdir -p "$d/.github/PULL_REQUEST_TEMPLATE"
touch "$d/.github/pull_request_template.md"
touch "$d/.github/PULL_REQUEST_TEMPLATE/a.md" "$d/.github/PULL_REQUEST_TEMPLATE/b.md"
assert "multiple: dir outranks single file" MULTIPLE "$(status_of "$d")"

echo ""
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
