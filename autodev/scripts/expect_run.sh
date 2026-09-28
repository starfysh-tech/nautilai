#!/usr/bin/env bash
# Run lane tests through the frozen TDD profile and require an outcome.
#   expect_run.sh red   <worktree> <lane-dir> <test-file>...
#       Each test must fail for a real reason. Records the paths in
#       <lane-dir>/red_tests.txt and the output in <lane-dir>/red.log.
#   expect_run.sh green <worktree> <lane-dir> [--no-test-changes <sha>] <test-file>...
#       Each test must pass. With --no-test-changes, no test, red test, or
#       test-config file may differ from <sha> (the refactor check).
#   expect_run.sh guard <worktree> <lane-dir> <patch> <test-file>
#       In a detached copy of the lane HEAD: the test passes, the
#       guard-removal patch applies, then the test fails.
# Exit 0: expectation met. Exit 1: not met. Exit 2: cannot run (no profile,
# no test_file, bad arguments).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lane_run.sh
source "$SCRIPT_DIR/lane_run.sh"

MODE="${1:?mode required: red|green|guard}"
WORKTREE="$(cd "${2:?worktree required}" && pwd)"
LANE_DIR="$(cd "${3:?lane dir required}" && pwd)"
shift 3

PROFILE="$LANE_DIR/profile.md"
if [[ ! -f "$PROFILE" ]]; then
  echo "expect_run: no TDD profile frozen in $LANE_DIR" >&2
  exit 2
fi
TEST_FILE_CMD="$(python3 "$SCRIPT_DIR/profile.py" get "$PROFILE" test_file)" || {
  echo "expect_run: profile has no usable test_file" >&2
  exit 2
}

DB_ENV="$(lane_env "$PROFILE" "$LANE_DIR")" || { echo "expect_run: TDD profile db_isolation is invalid" >&2; exit 2; }

# run_one <file> <log>: run one test file, output appended to <log>.
run_one() {
  local cmd="${TEST_FILE_CMD//\{file\}/$1}"
  echo "\$ $cmd" >> "$2"
  (cd "$WORKTREE" && run_lane_cmd "$DB_ENV" "$cmd") >> "$2" 2>&1
}

# is_test_path: filter stdin to paths that are tests, red tests, or test config.
# The name patterns cover pytest, jest/vitest, go and rspec layouts.
is_test_path() {
  local cfg frozen
  cfg="$(python3 "$SCRIPT_DIR/profile.py" get "$PROFILE" test_config 2>/dev/null | tr ', ' '\n\n')"
  frozen="$(cat "$LANE_DIR/red_tests.txt" 2>/dev/null; printf '%s\n' "$cfg")"
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    if printf '%s\n' "$frozen" | grep -qxF -- "$p"; then echo "$p"; continue; fi
    case "$p" in
      */tests/*|tests/*|*/test/*|test/*|*/__tests__/*|__tests__/*|*/spec/*|spec/*) echo "$p" ;;
      test_*|*/test_*|*_test.*|*.test.*|*.spec.*|conftest.py|*/conftest.py) echo "$p" ;;
    esac
  done
}

case "$MODE" in
  red)
    : > "$LANE_DIR/red.log"
    for f in "$@"; do
      if [[ ! -f "$WORKTREE/$f" ]]; then
        echo "expect_run: $f does not exist in the worktree" >&2
        exit 1
      fi
      start=$(wc -l < "$LANE_DIR/red.log")
      run_one "$f" "$LANE_DIR/red.log"
      rc=$?
      if [[ "$rc" -eq 0 ]]; then
        echo "expect_run: $f passes; a red test must fail" >&2
        exit 1
      fi
      # These fail without running the test, so they prove nothing about it.
      case "$rc" in
        124) echo "expect_run: $f timed out; not a red" >&2; exit 1 ;;
        126|127) echo "expect_run: $f did not run (exit $rc); not a red" >&2; exit 1 ;;
      esac
      if tail -n "+$((start + 1))" "$LANE_DIR/red.log" | grep -qiE 'collected 0 items|no tests (ran|found|collected)'; then
        echo "expect_run: $f collected no tests; not a red" >&2
        exit 1
      fi
      grep -qxF "$f" "$LANE_DIR/red_tests.txt" 2>/dev/null || echo "$f" >> "$LANE_DIR/red_tests.txt"
    done
    ;;
  green)
    if [[ "${1:-}" == "--no-test-changes" ]]; then
      since="${2:?--no-test-changes needs a commit}"
      shift 2
      changed="$(cd "$WORKTREE" && { git diff --name-only "$since"; git ls-files --others --exclude-standard; })"
      tests_changed="$(printf '%s\n' "$changed" | is_test_path)"
      if [[ -n "$tests_changed" ]]; then
        echo "expect_run: test files changed since $since:" >&2
        echo "$tests_changed" >&2
        exit 1
      fi
    fi
    : > "$LANE_DIR/green.log"
    for f in "$@"; do
      if ! run_one "$f" "$LANE_DIR/green.log"; then
        echo "expect_run: $f fails; see $LANE_DIR/green.log" >&2
        exit 1
      fi
    done
    ;;
  guard)
    patch="$(cd "$(dirname "${1:?patch required}")" && pwd)/$(basename "$1")"
    test_path="${2:?guard test required}"
    log="$LANE_DIR/guard.log"
    : > "$log"
    # Mutate a detached copy at the lane's HEAD, never the lane worktree.
    GUARD_WT="$LANE_DIR/guard-wt"
    git -C "$WORKTREE" worktree remove --force "$GUARD_WT" >/dev/null 2>&1 || true
    if ! git -C "$WORKTREE" worktree add --detach "$GUARD_WT" HEAD >> "$log" 2>&1; then
      echo "expect_run: cannot create guard worktree; see $log" >&2
      exit 2
    fi
    trap 'git -C "$WORKTREE" worktree remove --force "$GUARD_WT" >/dev/null 2>&1' EXIT
    WORKTREE="$GUARD_WT"
    if ! run_one "$test_path" "$log"; then
      echo "expect_run: $test_path is not green before the guard is removed" >&2
      exit 2
    fi
    if ! git -C "$GUARD_WT" apply "$patch" >> "$log" 2>&1; then
      echo "expect_run: guard-removal patch does not apply; see $log" >&2
      exit 2
    fi
    run_one "$test_path" "$log"
    rc=$?
    case "$rc" in
      0) echo "expect_run: $test_path still passes with the guard removed" >&2; exit 1 ;;
      124|126|127) echo "expect_run: $test_path did not run after removal (exit $rc)" >&2; exit 2 ;;
    esac
    ;;
  *)
    echo "expect_run: unknown mode $MODE" >&2
    exit 2
    ;;
esac
