# shellcheck shell=bash
# Sourced, not executed. Shared by verify.sh and expect_run.sh; the caller must
# set SCRIPT_DIR (lane_env runs profile.py from it).
#
# run_with_timeout: portable timeout (macOS ships no timeout(1)). Run the
# command in its own process group, poll with kill -0 (a signal-0 send is a
# liveness check, not a real signal), and kill the whole group on overrun so no
# orphaned test runner survives the caller's timeout window.
# AUTODEV_VERIFY_TIMEOUT (seconds) is configurable per-repo; long integration
# suites can raise it.
verify_timeout="${AUTODEV_VERIFY_TIMEOUT:-1200}"
run_with_timeout() {
  set +e
  ( set -m; "$@" ) &
  pid=$!
  waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if [[ "$waited" -ge "$verify_timeout" ]]; then
      echo "timed out after ${verify_timeout}s; killing process group for pid ${pid}" >&2
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

# lane_env <profile> <lane-dir>: print the lane-scoped env assignments from the
# profile's db_isolation (e.g. DB_NAME=test_{slug}), so parallel lanes never
# share a test database. Empty when unset.
lane_env() {
  local db rc
  db="$(python3 "$SCRIPT_DIR/profile.py" get "$1" db_isolation)"
  rc=$?
  [[ "$rc" -eq 3 ]] && return 0
  [[ "$rc" -eq 0 ]] || return 1
  printf '%s' "${db//\{slug\}/$(basename "$2")}"
}

# run_lane_cmd <env> <cmd>: run a profile command with the lane env, under the
# timeout, in the current directory.
run_lane_cmd() {
  # shellcheck disable=SC2086 # $1 is a list of VAR=value words
  run_with_timeout env $1 bash -c "$2"
}
