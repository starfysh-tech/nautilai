#!/usr/bin/env bash
# Print the handoff directory for a working directory:
#   ~/.claude/handoffs/<slug>
# The slug is taken from the git toplevel of <dir> when there is one, so a
# session that cd'd into a subdirectory still writes where the pickup hook
# reads. A worktree has its own toplevel, so worktrees stay separate. Outside
# a repo, <dir> itself is used.
set -euo pipefail

dir="${1:-$PWD}"
root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$dir")
printf '%s/.claude/handoffs/%s\n' "$HOME" "$(printf '%s' "$root" | tr '/.' '-')"
