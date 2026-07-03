#!/usr/bin/env bash
# Objective verifier. Usage: verify.sh [dir] [lane-dir]
# Precedence: <lane-dir>/VERIFY.sh > <dir>/VERIFY.sh > stack auto-detect.
# Exposes AUTODEV_PHASE (baseline|attempt) so a lane VERIFY.sh can accept a
# not-yet-existing deliverable at baseline without falsely passing later.
set -euo pipefail
DIR="${1:-.}"
LANE_DIR="${2:-}"
export AUTODEV_PHASE="${AUTODEV_PHASE:-attempt}"
# Resolve the lane dir before cd-ing into DIR, or a relative lane path
# (e.g. .autodev/<slug>, as the skill passes) silently stops resolving.
if [[ -n "$LANE_DIR" ]]; then
  LANE_DIR="$(cd "$LANE_DIR" && pwd)"
fi
cd "$DIR"
if [[ -n "$LANE_DIR" && -f "$LANE_DIR/VERIFY.sh" ]]; then
  bash "$LANE_DIR/VERIFY.sh"
  exit $?
fi
if [[ -f ./VERIFY.sh ]]; then
  bash ./VERIFY.sh
  exit $?
fi
if [[ -f package.json ]]; then
  if command -v jq >/dev/null 2>&1 && jq -e '.scripts.test' package.json >/dev/null 2>&1; then npm test --silent; exit $?; fi
fi
if [[ -f pyproject.toml || -f pytest.ini || -d tests ]]; then
  if command -v pytest >/dev/null 2>&1; then pytest -q; exit $?; fi
fi
if [[ -f go.mod ]]; then go test ./...; exit $?; fi
if [[ -f Cargo.toml ]]; then cargo test --quiet; exit $?; fi
echo "No verifier found; create VERIFY.sh in the task lane for objective completion checks." >&2
exit 2
