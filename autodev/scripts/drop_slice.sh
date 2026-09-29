#!/usr/bin/env bash
# Drop the current slice after the advisor keeps the current rule on a spec gap.
#   drop_slice.sh <worktree> <lane-dir> "<reason>"
#   drop_slice.sh --checkpoint <lane-dir> "<reason>"
# --checkpoint: a scenario dropped at the launch checkpoint; logs the reason to
# <lane-dir>/dropped.md and changes nothing else.
# Otherwise: discards the worker's uncommitted attempt, restores every file the slice's red
# commits changed to the last green commit (base_sha before any green), commits
# that as a revert through commit_lane.sh (which moves red_sha), prunes vanished
# red tests from red_tests.txt, resets the slice cap and status, and appends the
# reason to <lane-dir>/dropped.md.
# Exit 0: dropped. Exit 1: the revert commit failed. Exit 2: nothing to drop.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${1:-}" == "--checkpoint" ]]; then
  LANE_DIR="$(cd "${2:?lane dir required}" && pwd)"
  {
    echo "## $(date -u +%Y-%m-%dT%H:%M:%SZ) — scenario dropped at the launch checkpoint"
    echo "- reason: ${3:?reason required}"
  } >> "$LANE_DIR/dropped.md"
  exit 0
fi
WORKTREE="$(cd "${1:?worktree required}" && pwd)"
LANE_DIR="$(cd "${2:?lane dir required}" && pwd)"
REASON="${3:?reason required}"
SLUG="$(basename "$LANE_DIR")"
MAIN_ROOT="$(dirname "$(dirname "$LANE_DIR")")"
ctl() { (cd "$MAIN_ROOT" && bash "$SCRIPT_DIR/controller.sh" "$@"); }

since="$(ctl get "$SLUG" green_sha)"
[[ -n "$since" ]] || since="$(ctl get "$SLUG" base_sha)"
[[ -n "$since" ]] || { echo "drop_slice: no green_sha or base_sha for $SLUG" >&2; exit 2; }

git -C "$WORKTREE" reset -q --hard HEAD
git -C "$WORKTREE" clean -fdq
files=()
while IFS= read -r f; do [[ -n "$f" ]] && files+=("$f"); done < <(git -C "$WORKTREE" diff --name-only "$since" HEAD)
[[ "${#files[@]}" -gt 0 ]] || { echo "drop_slice: no red commits since $since" >&2; exit 2; }

for f in "${files[@]}"; do
  if git -C "$WORKTREE" cat-file -e "$since:$f" 2>/dev/null; then
    git -C "$WORKTREE" checkout -q "$since" -- "$f"
  else
    rm -f "$WORKTREE/$f"
  fi
done
# commit_lane.sh stages the named files itself and refuses pre-staged ones.
git -C "$WORKTREE" reset -q
bash "$SCRIPT_DIR/commit_lane.sh" "$WORKTREE" "$LANE_DIR" red "revert(autodev): drop slice after spec gap" "${files[@]}" >/dev/null || exit 1

if [[ -f "$LANE_DIR/red_tests.txt" ]]; then
  kept=""
  while IFS= read -r t; do
    [[ -n "$t" && -f "$WORKTREE/$t" ]] && kept="$kept$t"$'\n'
  done < "$LANE_DIR/red_tests.txt"
  printf '%s' "$kept" > "$LANE_DIR/red_tests.txt"
fi
ctl record-slice-green "$SLUG" >/dev/null
ctl set "$SLUG" status pending >/dev/null
{
  echo "## $(date -u +%Y-%m-%dT%H:%M:%SZ) — slice dropped"
  echo "- reason: $REASON"
  echo "- restored to: $since"
  echo "- files: ${files[*]}"
  echo "- revert commit: $(git -C "$WORKTREE" rev-parse HEAD)"
} >> "$LANE_DIR/dropped.md"
