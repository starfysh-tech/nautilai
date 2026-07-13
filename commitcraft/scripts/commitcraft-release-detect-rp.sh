#!/usr/bin/env bash
# commitcraft-release-detect-rp.sh
#
# Decide whether release-please is the ACTUAL release path in this repo, or just
# present-but-disabled. The mere presence of .github/workflows/release-please.yml
# is too weak a signal: release-please can be scaffolded then neutered, in which
# case deferring to it dead-ends (no release PR ever arrives). When it is not
# functional, commitcraft should fall back to its manual tag/release path.
#
# Emits a parseable block on stdout:
#   RP_DETECT_START
#   RP_STATUS: FUNCTIONAL | DISABLED | ABSENT
#   RP_REASON: <one line explaining the decision>
#   RP_DETECT_END
#
#   FUNCTIONAL -> defer to release-please (it will/does cut releases)
#   DISABLED   -> release-please is installed but neutered; use the manual path
#   ABSENT     -> no release-please at all; use the manual path
#
# Runs from the repo root (cwd). Pure bash + grep, with an optional `gh` check to
# corroborate release history. Never hard-fails: any internal error degrades to a
# best-effort decision so `commitcraft release` is never blocked by detection.
set -uo pipefail
# Some agent runtimes (notably Hermes) run tools in a sandbox whose PATH omits
# Homebrew, so a bare `gh` is unfindable even when it is installed. Add the
# well-known locations rather than threading an absolute path through every call
# site. No-op when `gh` is already on PATH, which is the normal case.
if ! command -v gh >/dev/null 2>&1; then
    for _d in /opt/homebrew/bin /usr/local/bin; do
        [ -x "$_d/gh" ] && PATH="$PATH:$_d"
    done
    unset _d
fi

WF=".github/workflows/release-please.yml"
MANIFEST=".release-please-manifest.json"

emit() {
    printf 'RP_DETECT_START\nRP_STATUS: %s\nRP_REASON: %s\nRP_DETECT_END\n' "$1" "$2"
    exit 0
}

# 0. Not installed at all -> manual path.
[ -f "$WF" ] || emit ABSENT "no $WF in this repo"

# 1. Explicitly neutered via skip flags (runs green every push, produces nothing).
#    `[^#]*` keeps a commented-out flag (`# skip-github-release: true`) from matching.
grep -Eq '^[[:space:]]*[^#]*skip-github-release:[[:space:]]*true' "$WF" \
    && emit DISABLED "release-please.yml sets skip-github-release: true (creates no GitHub release)"
grep -Eq '^[[:space:]]*[^#]*skip-github-pull-request:[[:space:]]*true' "$WF" \
    && emit DISABLED "release-please.yml sets skip-github-pull-request: true (opens no release PR)"

# 2. Lacks write permission to create tags/PRs. Only flag when a permissions:
#    block exists but omits `contents: write` — an absent block leaves repo/org
#    defaults, which we do not second-guess.
# `permissions: write-all` grants contents:write without naming it — don't flag it.
if grep -Eq '^[[:space:]]*permissions:' "$WF" && ! grep -Eq '^[[:space:]]*permissions:[[:space:]]*write-all' "$WF"; then
    grep -Eq '^[[:space:]]*contents:[[:space:]]*write' "$WF" \
        || emit DISABLED "release-please.yml permissions block lacks contents: write (cannot tag/release)"
fi

# 3. Scaffolded but never produced a release: manifest missing or every tracked
#    package still at 0.0.0. Corroborate with release-please history (autorelease
#    labels) when gh is available so a freshly-installed-but-functional RP is not
#    mistaken for a disabled one.
manifest_never_released() {
    [ -f "$MANIFEST" ] || return 0   # missing manifest
    # Released if ANY package has a non-0.0.0 version — a monorepo can mix a freshly
    # added 0.0.0 package with already-released ones.
    grep -E '"[0-9]+\.[0-9]+\.[0-9]+"' "$MANIFEST" | grep -vq '"0\.0\.0"' && return 1
    return 0   # only 0.0.0 (or no parseable version) -> never released
}

if manifest_never_released; then
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        if gh label list --limit 100 --json name -q '.[].name' 2>/dev/null | grep -q '^autorelease'; then
            emit FUNCTIONAL "manifest at 0.0.0 but release-please labels exist (it has run here before)"
        fi
        emit DISABLED "manifest at 0.0.0 and no release-please history (no autorelease label) — never cut a release"
    fi
    # gh unavailable: cannot confirm history, so do not hijack a possibly-functional
    # RP on the manifest alone — defer, but say why the signal was inconclusive.
    emit FUNCTIONAL "config looks functional; manifest at 0.0.0 but gh unavailable to confirm release-please history"
fi

emit FUNCTIONAL "release-please.yml present with write permission and no skip flags"
