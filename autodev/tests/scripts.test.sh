#!/usr/bin/env bash
# Tests for autodev scripts: classify_failure.sh, fingerprint_failure.sh,
# parallel_safe.sh, and controller.sh. Self-contained: builds throwaway fixtures
# in tmpdir, stubs nothing external, prints per-case pass/fail, exits 0 only
# when all cases pass.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
AUTODEV_ROOT="$(cd "$(dirname "$HERE")" && pwd)"
SCRIPTS_DIR="$AUTODEV_ROOT/scripts"

PASS=0
FAIL=0

# assert <name> <expected> <actual>
assert() {
    if [ "$2" = "$3" ]; then
        PASS=$((PASS + 1)); printf '  ok   %-50s -> %s\n' "$1" "$3"
    else
        FAIL=$((FAIL + 1)); printf '  FAIL %-50s expected %s, got %s\n' "$1" "$2" "$3"
    fi
}

# assert_exit <name> <expected_exit_code> <command...>
assert_exit() {
    local name="$1"
    local expected_exit="$2"
    shift 2
    if "$@" >/dev/null 2>&1; then
        actual_exit=0
    else
        actual_exit=$?
    fi
    if [ "$expected_exit" -eq "$actual_exit" ]; then
        PASS=$((PASS + 1)); printf '  ok   %-50s -> exit %s\n' "$name" "$actual_exit"
    else
        FAIL=$((FAIL + 1)); printf '  FAIL %-50s expected exit %s, got %s\n' "$name" "$expected_exit" "$actual_exit"
    fi
}

# =============================================================================
# Test: classify_failure.sh
# =============================================================================

echo "=== classify_failure.sh tests ==="

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Test transient classification
echo "ECONNRESET error occurred" > "$TMP/transient.log"
result=$(bash "$SCRIPTS_DIR/classify_failure.sh" "$TMP/transient.log")
assert "classify: ECONNRESET -> transient" "transient" "$result"

# Test environment classification
echo "No verifier found in PATH" > "$TMP/environment.log"
result=$(bash "$SCRIPTS_DIR/classify_failure.sh" "$TMP/environment.log")
assert "classify: No verifier found -> environment" "environment" "$result"

# Test specification classification
echo "The requirements are ambiguous and unclear" > "$TMP/specification.log"
result=$(bash "$SCRIPTS_DIR/classify_failure.sh" "$TMP/specification.log")
assert "classify: ambiguous -> specification" "specification" "$result"

# Test implementation classification
echo "Variable not defined on line 42" > "$TMP/implementation.log"
result=$(bash "$SCRIPTS_DIR/classify_failure.sh" "$TMP/implementation.log")
assert "classify: generic error -> implementation" "implementation" "$result"

# Test case insensitivity
echo "TIMEOUT occurred" > "$TMP/timeout.log"
result=$(bash "$SCRIPTS_DIR/classify_failure.sh" "$TMP/timeout.log")
assert "classify: TIMEOUT (uppercase) -> transient" "transient" "$result"

# Test rate limit
echo "You have exceeded your rate limit" > "$TMP/ratelimit.log"
result=$(bash "$SCRIPTS_DIR/classify_failure.sh" "$TMP/ratelimit.log")
assert "classify: rate limit -> transient" "transient" "$result"

# Test missing env
echo "missing env variable" > "$TMP/missing_env.log"
result=$(bash "$SCRIPTS_DIR/classify_failure.sh" "$TMP/missing_env.log")
assert "classify: missing env -> environment" "environment" "$result"

# Test permission denied
echo "permission denied when accessing file" > "$TMP/perm.log"
result=$(bash "$SCRIPTS_DIR/classify_failure.sh" "$TMP/perm.log")
assert "classify: permission denied -> environment" "environment" "$result"

# Test unknown requirement
echo "unknown requirement specified" > "$TMP/unknown.log"
result=$(bash "$SCRIPTS_DIR/classify_failure.sh" "$TMP/unknown.log")
assert "classify: unknown requirement -> specification" "specification" "$result"

# Test acceptance criteria unclear
echo "acceptance criteria unclear" > "$TMP/unclear.log"
result=$(bash "$SCRIPTS_DIR/classify_failure.sh" "$TMP/unclear.log")
assert "classify: acceptance criteria unclear -> specification" "specification" "$result"

# =============================================================================
# Test: fingerprint_failure.sh
# =============================================================================

echo ""
echo "=== fingerprint_failure.sh tests ==="

# Test: same failure with different line numbers hashes the same
log1=$(cat <<'EOF'
Error in file.js at line 42: Variable $x is undefined
Stack trace:
  at function.js:123
  at main.js:456
EOF
)
log2=$(cat <<'EOF'
Error in file.js at line 99: Variable $x is undefined
Stack trace:
  at function.js:789
  at main.js:321
EOF
)
echo "$log1" > "$TMP/fail1.log"
echo "$log2" > "$TMP/fail2.log"
hash1=$(bash "$SCRIPTS_DIR/fingerprint_failure.sh" "$TMP/fail1.log")
hash2=$(bash "$SCRIPTS_DIR/fingerprint_failure.sh" "$TMP/fail2.log")
if [ "$hash1" = "$hash2" ]; then
    PASS=$((PASS + 1)); printf '  ok   %-50s -> hashes match\n' "fingerprint: line numbers stripped"
else
    FAIL=$((FAIL + 1)); printf '  FAIL %-50s expected hashes to match, got %s vs %s\n' "fingerprint: line numbers stripped" "$hash1" "$hash2"
fi

# Test: different failures hash differently
log3=$(cat <<'EOF'
Error in file.js: Variable $x is undefined
EOF
)
log4=$(cat <<'EOF'
Error in file.js: Variable $y is undefined
EOF
)
echo "$log3" > "$TMP/fail3.log"
echo "$log4" > "$TMP/fail4.log"
hash3=$(bash "$SCRIPTS_DIR/fingerprint_failure.sh" "$TMP/fail3.log")
hash4=$(bash "$SCRIPTS_DIR/fingerprint_failure.sh" "$TMP/fail4.log")
if [ "$hash3" != "$hash4" ]; then
    PASS=$((PASS + 1)); printf '  ok   %-50s -> hashes differ\n' "fingerprint: different failures"
else
    FAIL=$((FAIL + 1)); printf '  FAIL %-50s expected hashes to differ, got %s\n' "fingerprint: different failures" "$hash3"
fi

# Test: hex addresses stripped
log5=$(cat <<'EOF'
Segmentation fault at 0xdeadbeef in module
at 0xdeadbeef+0x42
EOF
)
log6=$(cat <<'EOF'
Segmentation fault at 0xcafebabe in module
at 0xcafebabe+0x42
EOF
)
echo "$log5" > "$TMP/fail5.log"
echo "$log6" > "$TMP/fail6.log"
hash5=$(bash "$SCRIPTS_DIR/fingerprint_failure.sh" "$TMP/fail5.log")
hash6=$(bash "$SCRIPTS_DIR/fingerprint_failure.sh" "$TMP/fail6.log")
if [ "$hash5" = "$hash6" ]; then
    PASS=$((PASS + 1)); printf '  ok   %-50s -> hashes match\n' "fingerprint: hex addresses stripped"
else
    FAIL=$((FAIL + 1)); printf '  FAIL %-50s expected hashes to match, got %s vs %s\n' "fingerprint: hex addresses stripped" "$hash5" "$hash6"
fi

# =============================================================================
# Test: parallel_safe.sh
# =============================================================================

echo ""
echo "=== parallel_safe.sh tests ==="

# Test safe task
echo "Fix the button styling in CSS" > "$TMP/safe_task.txt"
result=$(bash "$SCRIPTS_DIR/parallel_safe.sh" "$TMP/safe_task.txt")
assert "parallel_safe: button styling -> true" "true" "$result"

# Test unsafe task - migration
echo "Run database migration to add user table" > "$TMP/unsafe_migration.txt"
result=$(bash "$SCRIPTS_DIR/parallel_safe.sh" "$TMP/unsafe_migration.txt")
assert "parallel_safe: migration -> false" "false" "$result"

# Test unsafe task - package-lock
echo "Update package-lock.json" > "$TMP/unsafe_lock.txt"
result=$(bash "$SCRIPTS_DIR/parallel_safe.sh" "$TMP/unsafe_lock.txt")
assert "parallel_safe: package-lock -> false" "false" "$result"

# Test unsafe task - schema
echo "Modify database schema" > "$TMP/unsafe_schema.txt"
result=$(bash "$SCRIPTS_DIR/parallel_safe.sh" "$TMP/unsafe_schema.txt")
assert "parallel_safe: schema -> false" "false" "$result"

# Test unsafe task - build config
echo "Update build config for production" > "$TMP/unsafe_build.txt"
result=$(bash "$SCRIPTS_DIR/parallel_safe.sh" "$TMP/unsafe_build.txt")
assert "parallel_safe: build config -> false" "false" "$result"

# Test unsafe task - dockerfile
echo "Modify Dockerfile" > "$TMP/unsafe_docker.txt"
result=$(bash "$SCRIPTS_DIR/parallel_safe.sh" "$TMP/unsafe_docker.txt")
assert "parallel_safe: dockerfile -> false" "false" "$result"

# Test case insensitivity
echo "Run MIGRATION on the database" > "$TMP/unsafe_migration_upper.txt"
result=$(bash "$SCRIPTS_DIR/parallel_safe.sh" "$TMP/unsafe_migration_upper.txt")
assert "parallel_safe: MIGRATION (uppercase) -> false" "false" "$result"

# Regression (run #2): package.json dependency edits invalidate the lockfile
# and collide with any other lane touching package.json — never parallel-safe
echo "Remove unused @sqlite.org/sqlite-wasm and sql.js dependencies from package.json" > "$TMP/unsafe_pkgjson.txt"
result=$(bash "$SCRIPTS_DIR/parallel_safe.sh" "$TMP/unsafe_pkgjson.txt")
assert "parallel_safe: package.json dep edit -> false" "false" "$result"

echo "Add a new dependency for date parsing" > "$TMP/unsafe_dep.txt"
result=$(bash "$SCRIPTS_DIR/parallel_safe.sh" "$TMP/unsafe_dep.txt")
assert "parallel_safe: add dependency -> false" "false" "$result"

# =============================================================================
# Test: controller.sh
# =============================================================================

echo ""
echo "=== controller.sh tests ==="

# Helper: run controller.sh in an isolated git repo
run_in_isolated_repo() {
    local script="$1"
    shift
    local repo_tmp="$(mktemp -d)"
    (
        cd "$repo_tmp"
        git init -q
        eval "$script" "$@"
    )
    local exit_code=$?
    rm -rf "$repo_tmp"
    return $exit_code
}

# Test: init-lane creates a lane with counted_failures: 0
if run_in_isolated_repo "
    bash '$SCRIPTS_DIR/controller.sh' init-lane test_lane
    bash '$SCRIPTS_DIR/controller.sh' show 2>/dev/null | grep -q '\"counted_failures\": 0'
"; then
    PASS=$((PASS + 1)); printf '  ok   %-50s -> counted_failures: 0\n' "controller: init-lane"
else
    FAIL=$((FAIL + 1)); printf '  FAIL %-50s\n' "controller: init-lane"
fi

# Test: record-failure with implementation class increments counted_failures
if run_in_isolated_repo "
    bash '$SCRIPTS_DIR/controller.sh' init-lane lane_impl
    bash '$SCRIPTS_DIR/controller.sh' record-failure lane_impl implementation fp1
    bash '$SCRIPTS_DIR/controller.sh' show 2>/dev/null | grep -q '\"counted_failures\": 1'
"; then
    PASS=$((PASS + 1)); printf '  ok   %-50s -> counted_failures incremented\n' "controller: record-failure implementation"
else
    FAIL=$((FAIL + 1)); printf '  FAIL %-50s\n' "controller: record-failure implementation"
fi

# Test: record-failure with non-implementation classes does NOT increment
if run_in_isolated_repo "
    bash '$SCRIPTS_DIR/controller.sh' init-lane lane_transient
    bash '$SCRIPTS_DIR/controller.sh' record-failure lane_transient transient fp1
    bash '$SCRIPTS_DIR/controller.sh' show 2>/dev/null | grep -q '\"counted_failures\": 0'
"; then
    PASS=$((PASS + 1)); printf '  ok   %-50s -> counted_failures NOT incremented\n' "controller: record-failure transient"
else
    FAIL=$((FAIL + 1)); printf '  FAIL %-50s\n' "controller: record-failure transient"
fi

# Test: check continues when failures < 3
if run_in_isolated_repo "
    bash '$SCRIPTS_DIR/controller.sh' init-lane lane_check1
    bash '$SCRIPTS_DIR/controller.sh' record-failure lane_check1 implementation fp1
    bash '$SCRIPTS_DIR/controller.sh' check lane_check1
"; then
    PASS=$((PASS + 1)); printf '  ok   %-50s -> exit 0\n' "controller: check continues at 1 failure"
else
    FAIL=$((FAIL + 1)); printf '  FAIL %-50s -> expected exit 0\n' "controller: check continues at 1 failure"
fi

# Test: check stops at 3 failures
if run_in_isolated_repo "
    bash '$SCRIPTS_DIR/controller.sh' init-lane lane_check3
    bash '$SCRIPTS_DIR/controller.sh' record-failure lane_check3 implementation fp1
    bash '$SCRIPTS_DIR/controller.sh' record-failure lane_check3 implementation fp2
    bash '$SCRIPTS_DIR/controller.sh' record-failure lane_check3 implementation fp3
    bash '$SCRIPTS_DIR/controller.sh' check lane_check3
"; then
    FAIL=$((FAIL + 1)); printf '  FAIL %-50s -> expected exit 1\n' "controller: check stops at 3 failures"
else
    PASS=$((PASS + 1)); printf '  ok   %-50s -> exit 1\n' "controller: check stops at 3 failures"
fi

# Test: check stops on repeated fingerprint
if run_in_isolated_repo "
    bash '$SCRIPTS_DIR/controller.sh' init-lane lane_repeated
    bash '$SCRIPTS_DIR/controller.sh' record-failure lane_repeated implementation fp1
    bash '$SCRIPTS_DIR/controller.sh' record-failure lane_repeated implementation fp1
    bash '$SCRIPTS_DIR/controller.sh' check lane_repeated
"; then
    FAIL=$((FAIL + 1)); printf '  FAIL %-50s -> expected exit 1\n' "controller: check stops on repeated fingerprint"
else
    PASS=$((PASS + 1)); printf '  ok   %-50s -> exit 1\n' "controller: check stops on repeated fingerprint"
fi

# Test: check continues below cap with different fingerprints
if run_in_isolated_repo "
    bash '$SCRIPTS_DIR/controller.sh' init-lane lane_below
    bash '$SCRIPTS_DIR/controller.sh' record-failure lane_below implementation fp1
    bash '$SCRIPTS_DIR/controller.sh' record-failure lane_below implementation fp2
    bash '$SCRIPTS_DIR/controller.sh' check lane_below
"; then
    PASS=$((PASS + 1)); printf '  ok   %-50s -> exit 0\n' "controller: check continues below cap"
else
    FAIL=$((FAIL + 1)); printf '  FAIL %-50s -> expected exit 0\n' "controller: check continues below cap"
fi

# =============================================================================
# Test: verify.sh / baseline_verify.sh phase contract (regressions from live
# validation run #1 — see tests/SCENARIOS.md)
# =============================================================================

echo ""
echo "=== verify.sh phase-contract tests ==="

# Fixture: a git repo with a lane whose VERIFY.sh branches on AUTODEV_PHASE
# and requires a deliverable that does not exist at baseline time.
PHASE_TMP="$(mktemp -d)"
(
    cd "$PHASE_TMP"
    git init -q -b main
    git commit -q --allow-empty -m init
    mkdir -p .autodev/lane1 wt
    cat > .autodev/lane1/VERIFY.sh <<'V'
#!/usr/bin/env bash
if [[ "${AUTODEV_PHASE:-attempt}" == "baseline" ]]; then exit 0; fi
test -f deliverable.txt
V
)

# baseline_verify passes AUTODEV_PHASE=baseline through, so an absent
# deliverable is a green baseline (greenfield-task deadlock regression).
# baseline_verify resolves lane state under the git toplevel of CWD, so run
# it from inside the fixture.
(
    cd "$PHASE_TMP"
    if bash "$SCRIPTS_DIR/baseline_verify.sh" "$PHASE_TMP/wt" lane1 >/dev/null 2>&1; then exit 0; else exit 1; fi
) && phase_baseline=0 || phase_baseline=1
assert "verify: baseline_verify greenfield baseline" "0" "$phase_baseline"

# attempt phase fails while the deliverable is absent (no false completion)
(
    cd "$PHASE_TMP"
    if bash "$SCRIPTS_DIR/verify.sh" wt .autodev/lane1 >/dev/null 2>&1; then exit 0; else exit 1; fi
) && phase_attempt_missing=0 || phase_attempt_missing=1
assert "verify: attempt fails on absent deliverable" "1" "$phase_attempt_missing"

# attempt phase passes once the deliverable exists — using RELATIVE paths,
# which regressed when verify.sh cd'd before resolving the lane dir
(
    cd "$PHASE_TMP"
    touch wt/deliverable.txt
    if bash "$SCRIPTS_DIR/verify.sh" wt .autodev/lane1 >/dev/null 2>&1; then exit 0; else exit 1; fi
) && phase_attempt_present=0 || phase_attempt_present=1
assert "verify: relative lane dir resolves after cd" "0" "$phase_attempt_present"
rm -rf "$PHASE_TMP"

# =============================================================================
# Test: state-accuracy regressions from live validation run #1
# =============================================================================

echo ""
echo "=== state-accuracy tests ==="

# record-success increments attempt_count (a one-attempt success used to be
# indistinguishable from zero attempts)
if run_in_isolated_repo "
    bash '$SCRIPTS_DIR/controller.sh' init-lane lane_success
    bash '$SCRIPTS_DIR/controller.sh' record-success lane_success
    bash '$SCRIPTS_DIR/controller.sh' show 2>/dev/null | grep -q '\"attempt_count\": 1'
"; then
    PASS=$((PASS + 1)); printf '  ok   %-50s -> attempt_count: 1\n' "controller: record-success counts the attempt"
else
    FAIL=$((FAIL + 1)); printf '  FAIL %-50s\n' "controller: record-success counts the attempt"
fi

# create_worktree.sh populates worktree_path in state.json (was always null)
WT_TMP="$(mktemp -d)"
(
    cd "$WT_TMP"
    git init -q -b main
    git commit -q --allow-empty -m init
    bash "$SCRIPTS_DIR/init_task_lane.sh" wt_lane "task text" >/dev/null
    bash "$SCRIPTS_DIR/create_worktree.sh" wt_lane >/dev/null
    # git toplevel resolves /var -> /private/var on macOS, so match on the
    # stable suffix rather than the mktemp prefix
    grep -q '"worktree_path": "/.*/\.autodev-worktrees/wt_lane"' .autodev/state.json
) && wt_recorded=0 || wt_recorded=1
assert "create_worktree: records worktree_path in state" "0" "$wt_recorded"
rm -rf "$WT_TMP"

# =============================================================================
# Test: baseline recovery (regression from run #3 — a failed baseline set
# needs_guidance permanently; a later green baseline never cleared it, so the
# check gate blocked the lane forever)
# =============================================================================

echo ""
echo "=== baseline recovery tests ==="

BR_TMP="$(mktemp -d)"
(
    cd "$BR_TMP"
    git init -q -b main
    git commit -q --allow-empty -m init
    mkdir -p .autodev/lane_recover wt
    bash "$SCRIPTS_DIR/controller.sh" init-lane lane_recover >/dev/null
    # Broken verifier: baseline fails, lane goes needs_guidance
    printf '#!/usr/bin/env bash\nexit 1\n' > .autodev/lane_recover/VERIFY.sh
    bash "$SCRIPTS_DIR/baseline_verify.sh" "$BR_TMP/wt" lane_recover >/dev/null 2>&1
    if bash "$SCRIPTS_DIR/controller.sh" check lane_recover >/dev/null 2>&1; then
        exit 1  # gate should be stopping here
    fi
    # Verifier fixed: baseline passes and must unstick the lane
    printf '#!/usr/bin/env bash\nexit 0\n' > .autodev/lane_recover/VERIFY.sh
    bash "$SCRIPTS_DIR/baseline_verify.sh" "$BR_TMP/wt" lane_recover >/dev/null 2>&1
    bash "$SCRIPTS_DIR/controller.sh" check lane_recover >/dev/null 2>&1
) && baseline_recover=0 || baseline_recover=1
assert "baseline: green baseline clears needs_guidance" "0" "$baseline_recover"
rm -rf "$BR_TMP"

# =============================================================================
# Test: concurrent controller.sh writes (regression from run #2 — torn reads
# under non-atomic write, and lost updates under unlocked read-modify-write)
# =============================================================================

echo ""
echo "=== controller.sh concurrency tests ==="

CONC_TMP="$(mktemp -d)"
(
    cd "$CONC_TMP"
    git init -q -b main
    for lane in laneA laneB laneC; do
        bash "$SCRIPTS_DIR/controller.sh" init-lane "$lane"
    done
    # 3 lanes x 4 sequential counted failures each, all lanes fired
    # concurrently — exactly the run #2 stress shape that lost an update
    for lane in laneA laneB laneC; do
        (
            for i in 1 2 3 4; do
                bash "$SCRIPTS_DIR/controller.sh" record-failure "$lane" implementation "fp$i"
            done
        ) &
    done
    wait
) 2>/dev/null

# State must still be parseable (no torn write survives atomic replace)...
(
    cd "$CONC_TMP"
    python3 -c "import json; json.load(open('.autodev/state.json'))"
) >/dev/null 2>&1 && conc_parse=0 || conc_parse=1
assert "controller: concurrent writes leave valid JSON" "0" "$conc_parse"

# ...and no update may be lost: every lane recorded all 4 failures
conc_counts=$(
    cd "$CONC_TMP"
    python3 -c "
import json
lanes = json.load(open('.autodev/state.json'))['lanes']
print(','.join(str(lanes[l]['attempt_count']) for l in ('laneA','laneB','laneC')))
" 2>/dev/null
)
assert "controller: no lost updates across 3 lanes" "4,4,4" "$conc_counts"
rm -rf "$CONC_TMP"

# =============================================================================
# Test: worktree lifecycle edge cases (PR #41 review findings)
# =============================================================================

echo ""
echo "=== worktree edge-case tests ==="

WTE_TMP="$(mktemp -d)"
(
    cd "$WTE_TMP"
    git init -q -b main
    git commit -q --allow-empty -m init
    # Stale non-worktree dir at the lane path: must refuse loudly, not
    # silently delete (it may hold unharvested work) and not fail confusingly
    mkdir -p .autodev-worktrees/stale_lane
    touch .autodev-worktrees/stale_lane/unharvested-work.txt
    if bash "$SCRIPTS_DIR/create_worktree.sh" stale_lane >/dev/null 2>&1; then
        exit 1  # should have refused
    fi
    test -f .autodev-worktrees/stale_lane/unharvested-work.txt  # data preserved
) && wte_stale=0 || wte_stale=1
assert "create_worktree: refuses stale dir, preserves data" "0" "$wte_stale"

(
    cd "$WTE_TMP"
    # Unregistered leftover dir: remove_worktree's contract is full cleanup
    mkdir -p .autodev-worktrees/orphan_lane
    bash "$SCRIPTS_DIR/remove_worktree.sh" orphan_lane >/dev/null 2>&1
    [[ ! -d .autodev-worktrees/orphan_lane ]]
) && wte_orphan=0 || wte_orphan=1
assert "remove_worktree: clears unregistered leftover dir" "0" "$wte_orphan"
rm -rf "$WTE_TMP"

# verify.sh without jq must still find a package.json test script (regression:
# silently fell through to "No verifier found")
NOJQ_TMP="$(mktemp -d)"
mkdir -p "$NOJQ_TMP/bin"
cat > "$NOJQ_TMP/bin/npm" <<'FAKE'
#!/usr/bin/env bash
[ "$1" = "test" ] && echo "fake-npm-test-ran" && exit 0
exit 1
FAKE
chmod +x "$NOJQ_TMP/bin/npm"
printf '{ "name": "x", "scripts": { "test": "true" } }\n' > "$NOJQ_TMP/package.json"
nojq_out=$(
    cd "$NOJQ_TMP"
    # PATH without jq but with git/bash basics and the fake npm
    PATH="$NOJQ_TMP/bin:/usr/bin:/bin" bash "$SCRIPTS_DIR/verify.sh" . 2>&1
)
case "$nojq_out" in
    *fake-npm-test-ran*) PASS=$((PASS + 1)); printf '  ok   %-50s -> npm test ran\n' "verify: finds npm test without jq" ;;
    *) FAIL=$((FAIL + 1)); printf '  FAIL %-50s got: %s\n' "verify: finds npm test without jq" "$nojq_out" ;;
esac
rm -rf "$NOJQ_TMP"

# =============================================================================
# Test: escalate_summary.sh output shape (gate/escalate machinery is
# fixture-validated — 4 live runs never triggered it, per SCENARIOS.md)
# =============================================================================

echo ""
echo "=== escalate_summary.sh tests ==="

ESC_TMP="$(mktemp -d)"
mkdir -p "$ESC_TMP/lane_x"
printf '# Task\n\nFix the widget.\n' > "$ESC_TMP/lane_x/TASK.md"
printf '# Attempt history\n- attempt 1: failed\n' > "$ESC_TMP/lane_x/RUNSTATE.md"
printf '# Last failure signature\n- mechanism cannot cross contexts\n\n# Next attempt\n- needs user decision: A or B\n' >> "$ESC_TMP/lane_x/RUNSTATE.md"
esc_out="$(bash "$SCRIPTS_DIR/escalate_summary.sh" "$ESC_TMP/lane_x")"
case "$esc_out" in
    *"needs guidance for lane: lane_x"*"Problem:"*"Fix the widget."*"Current blocker:"*"needs user decision: A or B"*"What has been done:"*"attempt 1: failed"*"Suggested guidance needed:"*)
        PASS=$((PASS + 1)); printf '  ok   %-50s -> all sections present\n' "escalate: handoff contains all sections" ;;
    *)
        FAIL=$((FAIL + 1)); printf '  FAIL %-50s missing sections\n' "escalate: handoff contains all sections" ;;
esac
# The current blocker must appear BEFORE the full history (run #5: three
# rounds of superseded attempts buried the actionable decision)
blocker_pos="${esc_out%%Current blocker:*}"
history_pos="${esc_out%%What has been done:*}"
if [ "${#blocker_pos}" -lt "${#history_pos}" ]; then
    PASS=$((PASS + 1)); printf '  ok   %-50s -> blocker first\n' "escalate: current blocker precedes history"
else
    FAIL=$((FAIL + 1)); printf '  FAIL %-50s\n' "escalate: current blocker precedes history"
fi
rm -rf "$ESC_TMP"

# Regression (run #5): distinct review-block findings must produce distinct
# fingerprints — the repeat-stop must not conflate different defects
REV_TMP="$(mktemp -d)"
printf 'BLOCK: queue.ts:45 empty-queue early return leaves flushing flag set forever\n' > "$REV_TMP/r1.log"
printf 'BLOCK: queue.ts:42 TOCTOU: flag set after await, concurrent calls both pass the guard\n' > "$REV_TMP/r2.log"
printf 'BLOCK: module-level flag cannot cross MV3 contexts; popup and sw never share memory\n' > "$REV_TMP/r3.log"
rf1=$(bash "$SCRIPTS_DIR/fingerprint_failure.sh" "$REV_TMP/r1.log")
rf2=$(bash "$SCRIPTS_DIR/fingerprint_failure.sh" "$REV_TMP/r2.log")
rf3=$(bash "$SCRIPTS_DIR/fingerprint_failure.sh" "$REV_TMP/r3.log")
if [ "$rf1" != "$rf2" ] && [ "$rf2" != "$rf3" ] && [ "$rf1" != "$rf3" ]; then
    PASS=$((PASS + 1)); printf '  ok   %-50s -> 3 distinct hashes\n' "fingerprint: distinct review blocks differ"
else
    FAIL=$((FAIL + 1)); printf '  FAIL %-50s hashes collide\n' "fingerprint: distinct review blocks differ"
fi
rm -rf "$REV_TMP"

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
