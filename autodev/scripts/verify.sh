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

# Portable timeout: macOS ships no timeout(1). Run the verifier command in its
# own process group, poll with kill -0 (a signal-0 send is a liveness check,
# not a real signal), and kill the whole group on overrun so no orphaned test
# runner survives the caller's timeout window. AUTODEV_VERIFY_TIMEOUT (seconds)
# is configurable per-repo; long integration suites can raise it.
verify_timeout="${AUTODEV_VERIFY_TIMEOUT:-1200}"
run_with_timeout() {
  set +e
  ( set -m; "$@" ) &
  pid=$!
  waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if [[ "$waited" -ge "$verify_timeout" ]]; then
      echo "verify.sh: timed out after ${verify_timeout}s; killing process group for pid ${pid}" >&2
      kill -TERM -- "-${pid}" 2>/dev/null || kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null
      set -e
      return 124
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "$pid"
  status=$?
  set -e
  return "$status"
}

if [[ -n "$LANE_DIR" && -f "$LANE_DIR/VERIFY.sh" ]]; then
  run_with_timeout bash "$LANE_DIR/VERIFY.sh"
  exit $?
fi
if [[ -f ./VERIFY.sh ]]; then
  run_with_timeout bash ./VERIFY.sh
  exit $?
fi
if [[ -f package.json ]]; then
  if command -v jq >/dev/null 2>&1; then
    if jq -e '.scripts.test' package.json >/dev/null 2>&1; then run_with_timeout npm test --silent; exit $?; fi
  elif grep -q '"test"[[:space:]]*:' package.json; then
    # No jq: crude check, but failing toward running tests beats silently
    # reporting "no verifier found" when a test script exists.
    run_with_timeout npm test --silent; exit $?
  fi
fi
if [[ -f pyproject.toml || -f pytest.ini || -d tests ]]; then
  if command -v pytest >/dev/null 2>&1; then run_with_timeout pytest -q; exit $?; fi
fi
if [[ -f go.mod ]]; then run_with_timeout go test ./...; exit $?; fi
if [[ -f Cargo.toml ]]; then run_with_timeout cargo test --quiet; exit $?; fi
echo "No verifier found; create VERIFY.sh in the task lane for objective completion checks." >&2
exit 2
