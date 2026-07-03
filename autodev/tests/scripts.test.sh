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
# Summary
# =============================================================================

echo ""
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
