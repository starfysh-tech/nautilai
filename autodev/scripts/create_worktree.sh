#!/usr/bin/env bash
# Create (or reuse) the scripted worktree for a lane. Prints the worktree path.
set -euo pipefail
SLUG="${1:?slug required}"
BASE_BRANCH="${2:-$(git rev-parse --abbrev-ref HEAD)}"
ROOT="$(git rev-parse --show-toplevel)"
WT_PARENT="$ROOT/.autodev-worktrees"
WT_ROOT="$WT_PARENT/$SLUG"
BRANCH="autodev/$SLUG"
mkdir -p "$ROOT/.autodev/$SLUG" "$WT_PARENT"
# Keep in-repo worktrees out of the user's git status.
[[ -f "$WT_PARENT/.gitignore" ]] || printf '*\n' > "$WT_PARENT/.gitignore"
if [[ -d "$WT_ROOT/.git" || -f "$WT_ROOT/.git" ]]; then
  echo "$WT_ROOT"
  exit 0
fi
if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  # Branch survived a previous cleanup; reattach instead of failing on -b.
  git worktree add "$WT_ROOT" "$BRANCH" >/dev/null
else
  git worktree add -b "$BRANCH" "$WT_ROOT" "$BASE_BRANCH" >/dev/null
fi
echo "$WT_ROOT"
