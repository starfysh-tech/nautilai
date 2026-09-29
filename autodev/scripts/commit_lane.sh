#!/usr/bin/env bash
# Commit named files on a lane branch, following CommitCraft's rules.
#   commit_lane.sh <worktree> <lane-dir> <red|green|refactor> "<subject>" <file>...
# Stages only the named files (never `git add -A`), runs the repo's hooks, and
# never bypasses them. On success records red_sha / green_sha / refactor_sha;
# a green commit also resets the slice's failure cap.
# Exit 0: committed. Exit 1: git or a hook refused (output on stderr).
# Exit 2: bad subject, bad kind, no files, or foreign files already staged.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKTREE="$(cd "${1:?worktree required}" && pwd)"
LANE_DIR="$(cd "${2:?lane dir required}" && pwd)"
KIND="${3:?kind required: red|green|refactor}"
SUBJECT="${4:?subject required}"
shift 4
SLUG="$(basename "$LANE_DIR")"
MAIN_ROOT="$(dirname "$(dirname "$LANE_DIR")")"
ctl() { (cd "$MAIN_ROOT" && bash "$SCRIPT_DIR/controller.sh" "$@" >/dev/null); }

case "$KIND" in red|green|refactor) ;; *) echo "commit_lane: unknown kind $KIND" >&2; exit 2 ;; esac
[[ "$#" -gt 0 ]] || { echo "commit_lane: no files to commit" >&2; exit 2; }

TYPES='feat|fix|docs|style|refactor|test|chore|perf|ci|revert'
if [[ "${#SUBJECT}" -gt 72 ]] || ! [[ "$SUBJECT" =~ ^($TYPES)(\([a-z0-9._/-]+\))?!?:\ [a-z0-9] ]] || [[ "$SUBJECT" == *. ]]; then
  echo "commit_lane: subject must be '<type>(<scope>): <lowercase imperative>', <= 72 chars, no trailing period: $SUBJECT" >&2
  exit 2
fi

cd "$WORKTREE" || exit 2
foreign="$(git diff --cached --name-only)"
if [[ -n "$foreign" ]]; then
  echo "commit_lane: files already staged; refusing to mix them in:" >&2
  echo "$foreign" >&2
  exit 2
fi
for f in "$@"; do
  git add -- "$f" || { git reset -q; exit 1; }
done
if ! git commit -q -m "$SUBJECT"; then
  git reset -q
  exit 1
fi

sha="$(git rev-parse HEAD)"
ctl set "$SLUG" "${KIND}_sha" "$sha"
[[ "$KIND" == "green" ]] && ctl record-slice-green "$SLUG"
echo "$sha"
