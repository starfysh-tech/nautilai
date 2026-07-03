#!/usr/bin/env bash
# Remove a lane's worktree and its autodev/<slug> branch.
set -euo pipefail
SLUG="${1:?slug required}"
ROOT="$(git rev-parse --show-toplevel)"
WT_ROOT="$ROOT/.autodev-worktrees/$SLUG"
BRANCH="autodev/$SLUG"
if [[ -d "$WT_ROOT" ]]; then
  git worktree remove "$WT_ROOT" --force >/dev/null || true
fi
git worktree prune >/dev/null 2>&1 || true
# An unregistered leftover dir survives `git worktree remove`; this script's
# contract is full cleanup, so finish the job.
rm -rf "$WT_ROOT"
if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  git branch -D "$BRANCH" >/dev/null || true
fi
