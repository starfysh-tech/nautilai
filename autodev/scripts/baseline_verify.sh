#!/usr/bin/env bash
# Verify a lane's worktree passes checks BEFORE autonomous work starts,
# so pre-existing breakage is never billed to the worker.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKTREE="${1:?worktree path required}"
LANE="${2:?lane required}"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
LANE_DIR="$ROOT/.autodev/$LANE"
mkdir -p "$LANE_DIR"
if bash "$SCRIPT_DIR/verify.sh" "$WORKTREE" "$LANE_DIR" >"$LANE_DIR/baseline.log" 2>&1; then
  bash "$SCRIPT_DIR/controller.sh" set "$LANE" baseline_status green
  exit 0
else
  bash "$SCRIPT_DIR/controller.sh" set "$LANE" baseline_status red
  bash "$SCRIPT_DIR/controller.sh" set "$LANE" status needs_guidance
  echo "Baseline verification failed; see $LANE_DIR/baseline.log" >&2
  exit 1
fi
