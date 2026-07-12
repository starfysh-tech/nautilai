#!/usr/bin/env bash
# Mirror a plugin's runtime resources INTO its skill dir, for Hermes Agent.
#
# Why this exists: Hermes ships the *skill directory* and nothing else. nautilai
# keeps scripts/ and templates/ at the plugin root (siblings of skills/), so Hermes
# would install a skill whose script references all dangle.
#
# Claude Code is the source of truth and is NOT modified: it keeps using
# <plugin>/scripts/ and <plugin>/templates/ exactly as before. The copies under
# <plugin>/skills/<skill>/ exist only for Hermes, are generated, and are inert to
# Claude — no Claude-loaded file references them.
#
#   hermes/sync-resources.sh           regenerate the mirror
#   hermes/sync-resources.sh --check   fail if the mirror is stale (CI gate)
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# plugin:skill pairs whose plugin-root resources are mirrored into the skill dir.
# autodev is deliberately absent — it is Claude-only (subagent fan-out + git
# worktrees have no Hermes equivalent).
PAIRS=("commitcraft:commitcraft")
DIRS=("scripts" "templates")

sync_into() { # $1 = destination root
  local dest_root="$1" pair plugin skill d src dest
  for pair in "${PAIRS[@]}"; do
    plugin="${pair%%:*}"; skill="${pair##*:}"
    for d in "${DIRS[@]}"; do
      src="$ROOT/$plugin/$d"
      dest="$dest_root/$plugin/skills/$skill/$d"
      [ -d "$src" ] || continue
      rm -rf "$dest"
      mkdir -p "$dest"
      # Mode bits are intentionally not preserved: Hermes strips the executable bit
      # on install (verified), so the Hermes adapter invokes scripts via `bash <path>`.
      cp -R "$src/." "$dest/"
    done
  done
}

if [ "${1:-}" = "--check" ]; then
  # Trap first: registering it after mktemp leaves a window where an interrupt
  # leaks the temp dir. `rm -rf ""` is a no-op, so the empty initial value is safe.
  tmp=""
  trap 'rm -rf "$tmp"' EXIT
  tmp="$(mktemp -d)"
  for pair in "${PAIRS[@]}"; do
    plugin="${pair%%:*}"
    mkdir -p "$tmp/$plugin"
    for d in "${DIRS[@]}"; do
      [ -d "$ROOT/$plugin/$d" ] && cp -R "$ROOT/$plugin/$d" "$tmp/$plugin/"
    done
  done
  sync_into "$tmp"

  rc=0
  for pair in "${PAIRS[@]}"; do
    plugin="${pair%%:*}"; skill="${pair##*:}"
    for d in "${DIRS[@]}"; do
      a="$ROOT/$plugin/skills/$skill/$d"
      b="$tmp/$plugin/skills/$skill/$d"
      [ -d "$b" ] || continue
      if ! diff -r "$a" "$b" >/dev/null 2>&1; then
        echo "DRIFT: $plugin/skills/$skill/$d is stale — run hermes/sync-resources.sh" >&2
        rc=1
      fi
    done
  done
  [ "$rc" -eq 0 ] && echo "Hermes resource mirror in sync"
  exit "$rc"
fi

sync_into "$ROOT"
echo "Hermes resource mirror regenerated"
