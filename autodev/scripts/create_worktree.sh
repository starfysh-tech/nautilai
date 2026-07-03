#!/usr/bin/env bash
# Create (or reuse) the scripted worktree for a lane. Prints the worktree path.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SLUG="${1:?slug required}"
BASE_BRANCH="${2:-$(git rev-parse --abbrev-ref HEAD)}"
ROOT="$(git rev-parse --show-toplevel)"
WT_PARENT="$ROOT/.autodev-worktrees"
WT_ROOT="$WT_PARENT/$SLUG"
BRANCH="autodev/$SLUG"
mkdir -p "$ROOT/.autodev/$SLUG" "$WT_PARENT"
# Keep in-repo worktrees out of the user's git status.
[[ -f "$WT_PARENT/.gitignore" ]] || printf '*\n' > "$WT_PARENT/.gitignore"
if [[ ! -d "$WT_ROOT/.git" && ! -f "$WT_ROOT/.git" ]]; then
  git worktree prune >/dev/null 2>&1 || true
  if [[ -d "$WT_ROOT" ]]; then
    # A dir without a .git marker isn't a worktree — likely an interrupted
    # run. It may hold unharvested work, so never delete it silently.
    echo "error: $WT_ROOT exists but is not a git worktree; inspect and remove it, then retry" >&2
    exit 1
  fi
  if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    # Branch survived a previous cleanup; reattach instead of failing on -b.
    git worktree add "$WT_ROOT" "$BRANCH" >/dev/null
  else
    git worktree add -b "$BRANCH" "$WT_ROOT" "$BASE_BRANCH" >/dev/null
  fi
fi
bash "$SCRIPT_DIR/controller.sh" set "$SLUG" worktree_path "$WT_ROOT"
echo "$WT_ROOT"
