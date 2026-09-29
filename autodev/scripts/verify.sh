#!/usr/bin/env bash
# Objective verifier. Usage: verify.sh [dir] [lane-dir]
# Exposes AUTODEV_PHASE (baseline|attempt) so a lane VERIFY.sh can accept a
# not-yet-existing deliverable at baseline without falsely passing later.
#
# Lane without a frozen TDD profile (<lane-dir>/profile.md): one verifier,
#   <lane-dir>/VERIFY.sh > <dir>/VERIFY.sh > stack auto-detect.
# TDD lane: a pipeline that stops at the first failure —
#   1. frozen check: red tests and profile test_config unchanged since red_sha;
#      test files that existed at base_sha unchanged unless TASK.md lists them
#      under "## Test edits authorized"
#   2. red tests via the profile's test_file
#   3. lint and format_check on files changed since the lane's base_sha
#   4. <lane-dir>/VERIFY.sh, when present
#   5. full suite: profile full_suite > <dir>/VERIFY.sh > stack auto-detect
#   Steps 1–3 run in the attempt phase only. A missing profile key is a logged
#   skip, except test_file when red tests exist. After a pass, the profile's
#   coverage command writes <lane-dir>/coverage.log (report only).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIR="${1:-.}"
LANE_DIR="${2:-}"
export AUTODEV_PHASE="${AUTODEV_PHASE:-attempt}"
# Resolve the lane dir before cd-ing into DIR, or a relative lane path
# (e.g. .autodev/<slug>, as the skill passes) silently stops resolving.
if [[ -n "$LANE_DIR" ]]; then
  LANE_DIR="$(cd "$LANE_DIR" && pwd)"
fi
cd "$DIR"

# shellcheck source=lane_run.sh
source "$SCRIPT_DIR/lane_run.sh"

# auto_detect_suite: run the stack's default suite; 2 when none is found.
auto_detect_suite() {
  if [[ -f package.json ]]; then
    if command -v jq >/dev/null 2>&1; then
      if jq -e '.scripts.test' package.json >/dev/null 2>&1; then run_with_timeout npm test --silent; return $?; fi
    elif grep -q '"test"[[:space:]]*:' package.json; then
      # No jq: crude check, but failing toward running tests beats silently
      # reporting "no verifier found" when a test script exists.
      run_with_timeout npm test --silent; return $?
    fi
  fi
  if [[ -f pyproject.toml || -f pytest.ini || -d tests ]]; then
    if command -v pytest >/dev/null 2>&1; then run_with_timeout pytest -q; return $?; fi
  fi
  if [[ -f go.mod ]]; then run_with_timeout go test ./...; return $?; fi
  if [[ -f Cargo.toml ]]; then run_with_timeout cargo test --quiet; return $?; fi
  return 2
}

PROFILE="${LANE_DIR:+$LANE_DIR/profile.md}"
EXEMPT=0
if [[ -n "$LANE_DIR" ]] && grep -q '^red_tests: exempt' "$LANE_DIR/TASK.md" 2>/dev/null; then
  EXEMPT=1
fi
if [[ -z "$PROFILE" || ! -f "$PROFILE" || "$EXEMPT" -eq 1 ]]; then
  if [[ -n "$LANE_DIR" && -f "$LANE_DIR/VERIFY.sh" ]]; then
    run_with_timeout bash "$LANE_DIR/VERIFY.sh"
    exit $?
  fi
  if [[ -f ./VERIFY.sh ]]; then
    run_with_timeout bash ./VERIFY.sh
    exit $?
  fi
  if auto_detect_suite; then exit 0; else rc=$?; fi
  if [[ "$rc" -eq 2 ]]; then
    echo "No verifier found; create VERIFY.sh in the task lane for objective completion checks." >&2
  fi
  exit "$rc"
fi

# ---- TDD lane pipeline ----
SLUG="$(basename "$LANE_DIR")"
MAIN_ROOT="$(dirname "$(dirname "$LANE_DIR")")"
fail() { echo "verify: $*" >&2; exit 1; }
ENV_WORDS="$(lane_env "$PROFILE" "$LANE_DIR")" || fail "TDD profile db_isolation is invalid"
lane_get() { (cd "$MAIN_ROOT" && bash "$SCRIPT_DIR/controller.sh" get "$SLUG" "$1"); }
# profile_value <key> <var>: set <var> to the value; return 3 when absent or
# `unknown`. A profile error (exit 2) fails verification: a broken value must
# never read as a skipped step.
profile_value() {
  local out rc
  out="$(python3 "$SCRIPT_DIR/profile.py" get "$PROFILE" "$1")"
  rc=$?
  [[ "$rc" -eq 2 ]] && fail "TDD profile key $1 is invalid"
  [[ "$rc" -eq 0 ]] || return 3
  printf -v "$2" '%s' "$out"
}
# Set only through profile_value's printf -v.
cfg="" test_file="" cmd="" suite="" cov=""

RED_TESTS=()
if [[ -f "$LANE_DIR/red_tests.txt" ]]; then
  while IFS= read -r line; do [[ -n "$line" ]] && RED_TESTS+=("$line"); done < "$LANE_DIR/red_tests.txt"
fi

if [[ "$AUTODEV_PHASE" == "attempt" ]]; then
  [[ "${#RED_TESTS[@]}" -gt 0 ]] || fail "no red tests recorded; write and commit the slice's red test first, or mark the lane exempt in TASK.md"
  red_sha="$(lane_get red_sha)"
  [[ -n "$red_sha" ]] || fail "red tests recorded but no red_sha for lane $SLUG"
  frozen=("${RED_TESTS[@]}")
  if profile_value test_config cfg; then
    for c in ${cfg//,/ }; do frozen+=("$c"); done
  fi
  if ! git diff --quiet "$red_sha" -- "${frozen[@]}"; then
    git diff --stat "$red_sha" -- "${frozen[@]}" >&2
    fail "red tests or test config changed since $red_sha"
  fi
  # Existing tests are the spec too: a changed one must be authorized in
  # TASK.md "## Test edits authorized" (test-fix lanes), never silently edited.
  base_sha="$(lane_get base_sha)"
  if [[ -n "$base_sha" ]]; then
    authorized="$(awk '/^## Test edits authorized/{on=1;next} /^## /{on=0} on && /^- /{print substr($0,3)}' "$LANE_DIR/TASK.md")"
    edited=""
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      printf '%s\n' "$authorized" | grep -qxF -- "$f" && continue
      git cat-file -e "$base_sha:$f" 2>/dev/null && edited="$edited $f"
    done < <(git diff --name-only "$base_sha" | is_test_path)
    [[ -z "$edited" ]] || fail "existing tests changed without authorization in TASK.md:$edited"
  fi
  profile_value test_file test_file || fail "red tests exist but the TDD profile has no test_file"
  for f in "${RED_TESTS[@]}"; do
    echo "verify: red test $f"
    run_lane_cmd "$ENV_WORDS" "${test_file//\{file\}/$f}" || fail "red test $f fails"
  done

  changed=()
  if [[ -n "$base_sha" ]]; then
    while IFS= read -r f; do
      [[ -n "$f" && -f "$f" ]] && changed+=("$f")
    done < <(git diff --name-only "$base_sha"; git ls-files --others --exclude-standard)
  fi
  for k in lint format_check; do
    if ! profile_value "$k" cmd; then
      echo "verify: skipped: no $k in TDD profile"
      continue
    fi
    if [[ "${#changed[@]}" -eq 0 ]]; then
      echo "verify: skipped: $k (no changed files)"
      continue
    fi
    files="$(printf '%q ' "${changed[@]}")"
    if [[ "$cmd" == *"{files}"* ]]; then cmd="${cmd//\{files\}/$files}"; else cmd="$cmd $files"; fi
    run_lane_cmd "$ENV_WORDS" "$cmd" || fail "$k failed"
  done
fi

ran_lane_verify=0
if [[ -f "$LANE_DIR/VERIFY.sh" ]]; then
  run_with_timeout bash "$LANE_DIR/VERIFY.sh" || fail "lane VERIFY.sh failed"
  ran_lane_verify=1
fi

if profile_value full_suite suite; then
  run_lane_cmd "$ENV_WORDS" "$suite" || fail "full suite failed"
elif [[ -f ./VERIFY.sh ]]; then
  run_with_timeout bash ./VERIFY.sh || fail "repo VERIFY.sh failed"
else
  if auto_detect_suite; then rc=0; else rc=$?; fi
  if [[ "$rc" -eq 2 ]]; then
    [[ "$ran_lane_verify" -eq 1 ]] || { echo "No verifier found; set full_suite in the TDD profile." >&2; exit 2; }
    echo "verify: skipped: full suite (none configured or detected)"
  elif [[ "$rc" -ne 0 ]]; then
    fail "full suite failed"
  fi
fi

if [[ "$AUTODEV_PHASE" == "attempt" ]] && profile_value coverage cov; then
  run_lane_cmd "$ENV_WORDS" "$cov" > "$LANE_DIR/coverage.log" 2>&1 || echo "verify: coverage command failed; see coverage.log (not gated)"
fi
exit 0
