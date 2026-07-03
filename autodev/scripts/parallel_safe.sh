#!/usr/bin/env bash
# Conservative text heuristic: tasks touching shared/global surfaces are not
# safe to run in parallel with other lanes. Prints "true" or "false".
set -euo pipefail
TASK_FILE="${1:?task file required}"
text="$(cat "$TASK_FILE" 2>/dev/null || true)"
shopt -s nocasematch
if [[ "$text" =~ (migration|lockfile|package-lock|pnpm-lock|yarn\.lock|poetry\.lock|Cargo\.lock|package\.json|dependenc|schema|generated|codegen|build[[:space:]]config|vite\.config|webpack|tsconfig|settings\.py|dockerfile|compose) ]]; then
  echo false
else
  echo true
fi
