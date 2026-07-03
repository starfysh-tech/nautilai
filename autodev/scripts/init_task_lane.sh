#!/usr/bin/env bash
# Initialize a task lane: TASK.md, RUNSTATE.md, controller state, parallel-safety flag.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SLUG="${1:?slug required}"
INPUT="${2:-}"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
LANE_DIR="$ROOT/.autodev/$SLUG"
mkdir -p "$LANE_DIR"
if [[ ! -f "$LANE_DIR/TASK.md" ]]; then
cat > "$LANE_DIR/TASK.md" <<TASK
# Task

$INPUT

## Acceptance criteria
- Define objective completion checks here.

## Constraints
- Keep changes minimal.
- Respect existing architecture unless explicitly authorized.
TASK
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
SAFE="$(bash "$SCRIPT_DIR/parallel_safe.sh" "$LANE_DIR/TASK.md")"
bash "$SCRIPT_DIR/controller.sh" set "$SLUG" parallel_safe "$SAFE"
echo "$LANE_DIR"
