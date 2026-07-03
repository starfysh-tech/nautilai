#!/usr/bin/env bash
# Objective verifier. Usage: verify.sh [dir] [lane-dir]
# Precedence: <lane-dir>/VERIFY.sh > <dir>/VERIFY.sh > stack auto-detect.
set -euo pipefail
DIR="${1:-.}"
LANE_DIR="${2:-}"
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
