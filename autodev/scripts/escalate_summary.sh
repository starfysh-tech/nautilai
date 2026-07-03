#!/usr/bin/env bash
# Print a concise guidance handoff for a blocked lane.
set -euo pipefail
LANE_DIR="${1:?lane dir required}"
TASK_FILE="$LANE_DIR/TASK.md"
STATE_FILE="$LANE_DIR/RUNSTATE.md"
printf "Autodev needs guidance for lane: %s\n\n" "$(basename "$LANE_DIR")"
printf "Problem:\n"
sed -n '1,80p' "$TASK_FILE" 2>/dev/null || echo "(no TASK.md)"
printf "\nWhat has been done:\n"
sed -n '1,160p' "$STATE_FILE" 2>/dev/null || echo "(no RUNSTATE.md)"
printf "\nSuggested guidance needed:\n- clarify acceptance criteria\n- approve broader refactor\n- provide domain decision\n- allow alternate implementation path\n"
