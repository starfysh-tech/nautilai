#!/usr/bin/env bash
# Initialize a task lane: TASK.md, RUNSTATE.md, controller state, parallel-safety flag.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SLUG="${1:?slug required}"
INPUT="${2:-}"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
LANE_DIR="$ROOT/.autodev/$SLUG"
mkdir -p "$LANE_DIR"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
if [[ ! -f "$LANE_DIR/TASK.md" ]]; then
  # python, not sed: task text can hold &, /, backslashes and newlines.
  TASK_TEXT="$INPUT" python3 -c '
import os, sys
sys.stdout.write(open(sys.argv[1]).read().replace("{{TASK}}", os.environ["TASK_TEXT"]))
' "$PLUGIN_ROOT/templates/TASK.md" > "$LANE_DIR/TASK.md"
fi
# Freeze TDD content per role at lane start, so a profile edit mid-run never
# changes a running lane. Scripts read the frozen profile.md, never the live one.
if [[ ! -f "$LANE_DIR/TDD-worker.md" ]]; then
  PROFILE=""
  if [[ -f "$ROOT/.claude/autodev.md" ]]; then
    cp "$ROOT/.claude/autodev.md" "$LANE_DIR/profile.md"
    PROFILE="$LANE_DIR/profile.md"
  fi
  RULES="$PLUGIN_ROOT/skills/autodev/references/tdd.md"
  for role in worker review; do
    python3 "$SCRIPT_DIR/profile.py" cut "$RULES" "$role" "$PROFILE" > "$LANE_DIR/TDD-$role.md.tmp"
    mv "$LANE_DIR/TDD-$role.md.tmp" "$LANE_DIR/TDD-$role.md"
  done
fi
if [[ ! -f "$LANE_DIR/RUNSTATE.md" ]]; then
cat > "$LANE_DIR/RUNSTATE.md" <<'STATE'
# Objective

# Constraints

# Current state

# Attempt history
- attempt 0: lane initialized

# Last failure signature
- none

# Next attempt
- inspect code and define the narrowest passing change
STATE
fi
bash "$SCRIPT_DIR/controller.sh" init-lane "$SLUG"
if [[ -z "$(bash "$SCRIPT_DIR/controller.sh" get "$SLUG" checkpoint)" ]]; then
  bash "$SCRIPT_DIR/controller.sh" set "$SLUG" checkpoint pending
fi
SAFE="$(bash "$SCRIPT_DIR/parallel_safe.sh" "$LANE_DIR/TASK.md")"
bash "$SCRIPT_DIR/controller.sh" set "$SLUG" parallel_safe "$SAFE"
echo "$LANE_DIR"
