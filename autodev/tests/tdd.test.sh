#!/usr/bin/env bash
# Tests for autodev's TDD scripts: profile.py, init_task_lane.sh role files,
# expect_run.sh, the verify.sh pipeline, controller.sh TDD states,
# and commit_lane.sh. Self-contained: throwaway repos in a
# tmpdir, fake HOME for plugin detection, exits 0 only when all cases pass.
set -uo pipefail

# CI runners have no git identity; fixture commits need one.
export GIT_AUTHOR_NAME="autodev-test" GIT_AUTHOR_EMAIL="autodev-test@example.com"
export GIT_COMMITTER_NAME="autodev-test" GIT_COMMITTER_EMAIL="autodev-test@example.com"

HERE="$(cd "$(dirname "$0")" && pwd)"
AUTODEV_ROOT="$(cd "$(dirname "$HERE")" && pwd)"
SCRIPTS_DIR="$AUTODEV_ROOT/scripts"

PASS=0
FAIL=0

# assert <name> <expected> <actual>
assert() {
    if [ "$2" = "$3" ]; then
        PASS=$((PASS + 1)); printf '  ok   %-55s -> %s\n' "$1" "$3"
    else
        FAIL=$((FAIL + 1)); printf '  FAIL %-55s expected [%s], got [%s]\n' "$1" "$2" "$3"
    fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# make_repo <dir>: git repo with one commit on main.
make_repo() {
    mkdir -p "$1"
    git -C "$1" init -q -b main
    printf 'seed\n' > "$1/README.md"
    git -C "$1" add README.md
    git -C "$1" commit -q -m "chore: seed"
}

# =============================================================================
echo "=== profile.py ==="
# =============================================================================

# body() raises ProfileError (not StopIteration) on unclosed frontmatter.
printf -- '---\ntest_file: x\n' > "$TMP/unclosed.md"
python3 - "$SCRIPTS_DIR/profile.py" "$TMP/unclosed.md" <<'PY' >/dev/null 2>&1
import importlib.util, sys
spec = importlib.util.spec_from_file_location("autodev_profile", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
try:
    m.body(sys.argv[2])
except m.ProfileError:
    sys.exit(0)
sys.exit(1)
PY
assert "profile: body() on unclosed frontmatter raises ProfileError" "0" "$?"

# is_test_path splits a test_config list on commas and spaces.
mkdir -p "$TMP/itp"
printf -- '---\ntest_config: a.cfg, b.cfg\n---\n' > "$TMP/itp/profile.md"
itp="$(SCRIPT_DIR="$SCRIPTS_DIR" PROFILE="$TMP/itp/profile.md" LANE_DIR="$TMP/itp" bash -c \
  'source "$SCRIPT_DIR/lane_run.sh"; printf "a.cfg\nb.cfg\nsrc/x.py\n" | is_test_path' | tr '\n' ' ')"
assert "lane_run: test_config list splits on comma and space" "a.cfg b.cfg " "$itp"

P="$TMP/profile.md"
cat > "$P" <<'EOF'
---
test_file: uv run pytest -q {file}
---
Prose.
EOF
out=$(python3 "$SCRIPTS_DIR/profile.py" get "$P" test_file); rc=$?
assert "profile: plain value" "uv run pytest -q {file}" "$out"
assert "profile: plain value exit" "0" "$rc"

# Skip contract: absent key and literal `unknown` both mean "no value" (exit 3).
cat > "$P" <<'EOF'
---
lint: unknown
---
EOF
python3 "$SCRIPTS_DIR/profile.py" get "$P" format >/dev/null; rc=$?
assert "profile: absent key -> skip" "3" "$rc"
python3 "$SCRIPTS_DIR/profile.py" get "$P" lint >/dev/null; rc=$?
assert "profile: unknown value -> skip" "3" "$rc"

# Quoting: values may contain ': ' and '#'; quotes are stripped, not kept.
cat > "$P" <<'EOF'
---
full_suite: "npm test -- --reporter=dot # all"
format_check: 'ruff format --check: strict'
---
EOF
out=$(python3 "$SCRIPTS_DIR/profile.py" get "$P" full_suite)
assert "profile: double-quoted value with #" "npm test -- --reporter=dot # all" "$out"
out=$(python3 "$SCRIPTS_DIR/profile.py" get "$P" format_check)
assert "profile: single-quoted value with ': '" "ruff format --check: strict" "$out"

# Errors (exit 2): a present-but-empty value would otherwise read as "skip".
cat > "$P" <<'EOF'
---
lint:
---
EOF
python3 "$SCRIPTS_DIR/profile.py" get "$P" lint >/dev/null 2>&1; rc=$?
assert "profile: present-but-empty -> error" "2" "$rc"
printf 'no frontmatter here\n' > "$P"
python3 "$SCRIPTS_DIR/profile.py" get "$P" lint >/dev/null 2>&1; rc=$?
assert "profile: no frontmatter -> error" "2" "$rc"
printf -- '---\nlint: ruff\n' > "$P"
python3 "$SCRIPTS_DIR/profile.py" get "$P" lint >/dev/null 2>&1; rc=$?
assert "profile: unclosed frontmatter -> error" "2" "$rc"
python3 "$SCRIPTS_DIR/profile.py" get "$TMP/missing.md" lint >/dev/null 2>&1; rc=$?
assert "profile: missing file -> error" "2" "$rc"
printf -- '---\nlint ruff check\ntest_file: sh {file}\n---\n' > "$P"
python3 "$SCRIPTS_DIR/profile.py" get "$P" test_file >/dev/null 2>&1; rc=$?
assert "profile: frontmatter line without ':' -> error" "2" "$rc"

# CRLF files (edited on Windows) and a body '---' must not leak into values.
printf -- '---\r\nlint: ruff check\r\n---\r\nbody\r\n---\r\nformat: nope\r\n' > "$P"
out=$(python3 "$SCRIPTS_DIR/profile.py" get "$P" lint)
assert "profile: CRLF value has no \\r" "ruff check" "$out"
python3 "$SCRIPTS_DIR/profile.py" get "$P" format >/dev/null; rc=$?
assert "profile: key after body --- is not frontmatter" "3" "$rc"

# =============================================================================
echo "=== init_task_lane.sh ==="
# =============================================================================

R="$TMP/init_repo"
make_repo "$R"
(cd "$R" && bash "$SCRIPTS_DIR/init_task_lane.sh" lane_a "Fix the widget count." >/dev/null)
L="$R/.autodev/lane_a"
grep -q '^Fix the widget count\.$' "$L/TASK.md"; assert "init: task text rendered into TASK.md" "0" "$?"
grep -q '^## Seams$' "$L/TASK.md"; assert "init: TASK.md comes from the template" "0" "$?"
grep -q '{{TASK}}' "$L/TASK.md"; assert "init: no unrendered placeholder" "1" "$?"
safe=$(cd "$R" && bash "$SCRIPTS_DIR/controller.sh" show | python3 -c 'import json,sys; print(json.load(sys.stdin)["lanes"]["lane_a"]["parallel_safe"])')
assert "init: new template stays parallel_safe" "true" "$safe"

# Role files: no profile -> generic sections only, plus the no-profile marker.
grep -q '^### Worker rules$' "$L/TDD-worker.md"; assert "init: worker file has worker rules" "0" "$?"
grep -q 'Tautological assertion' "$L/TDD-worker.md"; assert "init: worker file has no review tables" "1" "$?"
grep -q 'Tautological assertion' "$L/TDD-review.md"; assert "init: review file has anti-patterns" "0" "$?"
grep -q '^### Worker rules$' "$L/TDD-review.md"; assert "init: review file has no worker rules" "1" "$?"
grep -q '^## Complexity quadrant' "$L/TDD-worker.md"; assert "init: orchestrator-only text stays out" "1" "$?"
grep -q '^no project TDD profile$' "$L/TDD-worker.md"; assert "init: no-profile marker" "0" "$?"
grep -q 'pytest' "$L/TDD-worker.md"; assert "init: no stack -> no stack patterns" "1" "$?"

# With a profile: matching stack sections only, profile prose appended, frozen copy.
mkdir -p "$R/.claude"
cat > "$R/.claude/autodev.md" <<'EOF'
---
test_file: pytest -q {file}
stack: pytest, rtl
---
Factories live in tests/factories.py.
EOF
(cd "$R" && bash "$SCRIPTS_DIR/init_task_lane.sh" lane_b "Add lockout." >/dev/null)
L="$R/.autodev/lane_b"
grep -q '^### pytest$' "$L/TDD-worker.md"; assert "init: listed stack section kept" "0" "$?"
grep -q '^### Vitest$' "$L/TDD-worker.md"; assert "init: unlisted stack section dropped" "1" "$?"
grep -q 'getByTestId' "$L/TDD-review.md"; assert "init: rtl review rule kept for rtl stack" "0" "$?"
grep -q '^Factories live in tests/factories.py.$' "$L/TDD-review.md"; assert "init: profile prose in review file" "0" "$?"
cmp -s "$R/.claude/autodev.md" "$L/profile.md"; assert "init: profile frozen into lane" "0" "$?"
printf 'changed\n' >> "$R/.claude/autodev.md"
(cd "$R" && bash "$SCRIPTS_DIR/init_task_lane.sh" lane_b "Add lockout." >/dev/null)
grep -q '^changed$' "$L/profile.md"; assert "init: re-run does not refreeze" "1" "$?"

# A malformed rules file fails loudly instead of producing a partial file.
printf '<!-- tdd: roles=worker,boss -->\nx\n<!-- /tdd -->\n' > "$TMP/bad.md"
python3 "$SCRIPTS_DIR/profile.py" cut "$TMP/bad.md" worker >/dev/null 2>&1; rc=$?
assert "cut: unknown role -> error" "2" "$rc"
printf '<!-- tdd: roles=worker -->\nx\n' > "$TMP/bad.md"
python3 "$SCRIPTS_DIR/profile.py" cut "$TMP/bad.md" worker >/dev/null 2>&1; rc=$?
assert "cut: unclosed section -> error" "2" "$rc"
printf '<!-- tdd: roles=worker -->\nx\n<!-- /tdd -->\n' > "$TMP/bad.md"
python3 "$SCRIPTS_DIR/profile.py" cut "$TMP/bad.md" review >/dev/null 2>&1; rc=$?
assert "cut: no section for the role -> error" "2" "$rc"
grep -q 'patch that removes only that guard' "$L/TDD-review.md"; assert "init: review file has the guard check rule" "0" "$?"

# =============================================================================
echo "=== controller.sh TDD states ==="
# =============================================================================

C="$TMP/ctl_repo"
make_repo "$C"
ctl() { (cd "$C" && bash "$SCRIPTS_DIR/controller.sh" "$@"); }
ctl init-lane s >/dev/null
ctl record-failure s implementation fp1 >/dev/null
ctl record-failure s implementation fp2 >/dev/null
ctl record-slice-green s >/dev/null
assert "controller: slice green resets counted failures" "0" "$(ctl get s counted_failures)"
ctl record-failure s implementation fp2 >/dev/null
ctl record-failure s implementation fp3 >/dev/null
assert "controller: next slice gets its own cap" "continue" "$(ctl check s)"

# Specification and environment failures escalate by script: the gate stops
# at once, without waiting for the counted-failure cap.
ctl init-lane sp >/dev/null
ctl record-failure sp specification "spec_gap: x" >/dev/null
ctl check sp >/dev/null; assert "controller: specification failure stops the lane" "1" "$?"
assert "controller: specification failure -> needs_guidance" "needs_guidance" "$(ctl get sp status)"
ctl init-lane en >/dev/null
ctl record-failure en environment "command not found" >/dev/null
ctl check en >/dev/null; assert "controller: environment failure stops the lane" "1" "$?"
ctl init-lane im >/dev/null
ctl record-failure im implementation fp1 >/dev/null
assert "controller: one implementation failure continues" "continue" "$(ctl check im)"

# Checkpoint gate: a lane from init_task_lane.sh cannot attempt until confirmed.
(cd "$C" && bash "$SCRIPTS_DIR/init_task_lane.sh" gated "Task." >/dev/null)
ctl check gated >/dev/null; assert "controller: new lane blocked before checkpoint" "1" "$?"
ctl set gated checkpoint awaiting >/dev/null
ctl check gated >/dev/null; assert "controller: awaiting checkpoint blocks" "1" "$?"
ctl set gated checkpoint confirmed >/dev/null
assert "controller: confirmed lane continues" "continue" "$(ctl check gated)"

# A TDD lane (frozen profile.md) cannot be confirmed before its test review exists.
(cd "$C" && bash "$SCRIPTS_DIR/init_task_lane.sh" reviewed "Task." >/dev/null)
printf -- '---\ntest_file: sh {file}\n---\n' > "$C/.autodev/reviewed/profile.md"
ctl set reviewed checkpoint confirmed >/dev/null 2>&1
assert "controller: confirm refused without test-review.md" "1" "$?"
assert "controller: refused confirm leaves checkpoint" "pending" "$(ctl get reviewed checkpoint)"
printf '# Test review\n' > "$C/.autodev/reviewed/test-review.md"
ctl set reviewed checkpoint confirmed >/dev/null 2>&1
assert "controller: confirm allowed with test-review.md" "0" "$?"
assert "controller: TDD lane confirmed" "confirmed" "$(ctl get reviewed checkpoint)"

# A green baseline clears needs_guidance only; it never resets other statuses
# or the checkpoint (a settled plan must stay settled across re-runs).
printf 'exit 0\n' > "$C/.autodev/gated/VERIFY.sh"
ctl set gated status "done" >/dev/null
(cd "$C" && bash "$SCRIPTS_DIR/baseline_verify.sh" "$C" gated >/dev/null 2>&1)
assert "baseline: green keeps status done" "done" "$(ctl get gated status)"
assert "baseline: green keeps checkpoint" "confirmed" "$(ctl get gated checkpoint)"
ctl set gated status needs_guidance >/dev/null
(cd "$C" && bash "$SCRIPTS_DIR/baseline_verify.sh" "$C" gated >/dev/null 2>&1)
assert "baseline: green clears needs_guidance" "pending" "$(ctl get gated status)"

# base_sha: the lane's fixed comparison point for changed-file checks.
main_sha=$(git -C "$C" rev-parse main)
(cd "$C" && bash "$SCRIPTS_DIR/create_worktree.sh" gated main >/dev/null)
assert "worktree: base_sha is the base branch commit" "$main_sha" "$(ctl get gated base_sha)"
git -C "$C/.autodev-worktrees/gated" commit -q --allow-empty -m "test: lane work"
(cd "$C" && bash "$SCRIPTS_DIR/create_worktree.sh" gated main >/dev/null)
assert "worktree: reattach keeps original base_sha" "$main_sha" "$(ctl get gated base_sha)"

# Run-level flag: --unattended is recorded by script, not remembered by the model.
assert "controller: unattended unset by default" "" "$(ctl run-get unattended)"
ctl run-set unattended true >/dev/null
assert "controller: unattended recorded" "true" "$(ctl run-get unattended)"

# =============================================================================
echo "=== expect_run.sh ==="
# =============================================================================

# Fixture: tests are shell scripts; the profile's test_file runs one with sh.
E="$TMP/exp_repo"
make_repo "$E"
mkdir -p "$E/.claude" "$E/tests"
cat > "$E/.claude/autodev.md" <<'EOF'
---
test_file: sh {file}
---
EOF
printf 'exit 1\n' > "$E/tests/red_test.sh"
printf 'exit 0\n' > "$E/tests/green_test.sh"
(cd "$E" && bash "$SCRIPTS_DIR/init_task_lane.sh" x "Task." >/dev/null)
EL="$E/.autodev/x"
xr() { (cd "$E" && bash "$SCRIPTS_DIR/expect_run.sh" "$@" >/dev/null 2>&1); }

xr red "$E" "$EL" tests/red_test.sh; assert "red: failing test accepted" "0" "$?"
grep -qx 'tests/red_test.sh' "$EL/red_tests.txt"; assert "red: path recorded for the frozen set" "0" "$?"
[ -s "$EL/red.log" ] && saved=0 || saved=1; assert "red: failure output saved for the checkpoint" "0" "$saved"
xr red "$E" "$EL" tests/green_test.sh; assert "red: passing test rejected" "1" "$?"

# A failure that is not the test failing is not a red: missing command (127),
# not executable (126), timeout (124), or a runner that collected nothing.
xr red "$E" "$EL" tests/missing_test.sh; assert "red: missing test file rejected" "1" "$?"
printf 'exit 127\n' > "$E/tests/cmd127.sh"
xr red "$E" "$EL" tests/cmd127.sh; assert "red: exit 127 rejected" "1" "$?"
printf 'exit 124\n' > "$E/tests/cmd124.sh"
xr red "$E" "$EL" tests/cmd124.sh; assert "red: exit 124 rejected" "1" "$?"
printf 'echo "collected 0 items"; exit 5\n' > "$E/tests/empty.sh"
xr red "$E" "$EL" tests/empty.sh; assert "red: no tests collected rejected" "1" "$?"
grep -qx 'tests/cmd127.sh' "$EL/red_tests.txt"; assert "red: rejected path not recorded" "1" "$?"

# No profile frozen into the lane: cannot run at all (exit 2), never a pass.
make_repo "$TMP/noprof"
(cd "$TMP/noprof" && bash "$SCRIPTS_DIR/init_task_lane.sh" y "Task." >/dev/null)
(cd "$TMP/noprof" && bash "$SCRIPTS_DIR/expect_run.sh" red "$TMP/noprof" "$TMP/noprof/.autodev/y" t.sh >/dev/null 2>&1)
assert "red: no profile -> cannot run" "2" "$?"

# db_isolation: every test command in a lane runs with the lane-scoped env.
python3 - "$E/.claude/autodev.md" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
open(p,'w').write(s.replace("---\n", "---\ndb_isolation: DB_NAME=test_{slug}\n", 1))
PY
(cd "$E" && bash "$SCRIPTS_DIR/init_task_lane.sh" dbl "Task." >/dev/null)
printf 'echo "db=$DB_NAME"; exit 1\n' > "$E/tests/db_test.sh"
xr red "$E" "$E/.autodev/dbl" tests/db_test.sh
grep -q '^db=test_dbl$' "$E/.autodev/dbl/red.log"; assert "run: db_isolation env applied per lane" "0" "$?"

# green: every named test must pass; --no-test-changes guards the refactor.
xr green "$E" "$EL" tests/green_test.sh; assert "green: passing test accepted" "0" "$?"
xr green "$E" "$EL" tests/red_test.sh; assert "green: failing test rejected" "1" "$?"
git -C "$E" add tests; git -C "$E" commit -q -m "test: fixtures"
green_sha=$(git -C "$E" rev-parse HEAD)
mkdir -p "$E/src"; printf 'x=1\n' > "$E/src/app.py"
xr green "$E" "$EL" --no-test-changes "$green_sha" tests/green_test.sh; assert "green: source-only change accepted" "0" "$?"
printf '# tweak\nexit 0\n' > "$E/tests/green_test.sh"
xr green "$E" "$EL" --no-test-changes "$green_sha" tests/green_test.sh; assert "green: changed test file rejected" "1" "$?"
git -C "$E" checkout -q -- tests/green_test.sh
printf 'exit 0\n' > "$E/tests/new_test.sh"
xr green "$E" "$EL" --no-test-changes "$green_sha" tests/green_test.sh; assert "green: added test file rejected" "1" "$?"
/bin/rm -f "$E/tests/new_test.sh" "$E/src/app.py"

# guard: in a throwaway worktree, the named test passes, the guard-removal
# patch applies, and the same test then fails.
mkdir -p "$E/src"
printf 'if [ "$1" = bad ]; then exit 1; fi\nexit 0\n' > "$E/src/guard.sh"
printf 'if sh src/guard.sh bad; then exit 1; fi\nexit 0\n' > "$E/tests/guard_test.sh"
printf 'exit 0\n' > "$E/tests/weak_test.sh"
git -C "$E" add src tests; git -C "$E" commit -q -m "feat: guard"
cp "$E/src/guard.sh" "$TMP/guard.orig"
printf 'exit 0\n' > "$E/src/guard.sh"
git -C "$E" diff > "$TMP/remove_guard.patch"
git -C "$E" checkout -q -- src/guard.sh
printf 'not a patch\n' > "$TMP/bad.patch"

xr guard "$E" "$EL" "$TMP/remove_guard.patch" tests/guard_test.sh; assert "guard: removal turns its test red" "0" "$?"
xr guard "$E" "$EL" "$TMP/remove_guard.patch" tests/weak_test.sh; assert "guard: test that misses removal -> not met" "1" "$?"
xr guard "$E" "$EL" "$TMP/bad.patch" tests/guard_test.sh; assert "guard: patch that does not apply -> error" "2" "$?"
xr guard "$E" "$EL" "$TMP/remove_guard.patch" tests/red_test.sh; assert "guard: test red before removal -> error" "2" "$?"
cmp -s "$E/src/guard.sh" "$TMP/guard.orig"; assert "guard: lane worktree untouched" "0" "$?"
git -C "$E" worktree list | grep -q guard; assert "guard: throwaway worktree removed" "1" "$?"

# =============================================================================
echo "=== verify.sh pipeline ==="
# =============================================================================

# Each stage command appends its name to stages.log, so order and early stop
# are observable from outside.
V="$TMP/ver_repo"
make_repo "$V"
mkdir -p "$V/.claude" "$V/tests" "$V/src"
cat > "$V/.claude/autodev.md" <<EOF
---
test_file: sh {file}
lint: echo lint >> $TMP/stages.log; sh $V/lint.sh {files}
format_check: sh -c 'echo format_check >> $TMP/stages.log' -- {files}
full_suite: echo full_suite >> $TMP/stages.log
---
EOF
printf 'exit 0\n' > "$V/lint.sh"
printf 'exit 0\n' > "$V/tests/slice1_test.sh"
git -C "$V" add tests; git -C "$V" commit -q -m "test: add red test"
(cd "$V" && bash "$SCRIPTS_DIR/init_task_lane.sh" v "Task." >/dev/null)
VL="$V/.autodev/v"
printf 'tests/slice1_test.sh\n' > "$VL/red_tests.txt"
printf 'echo lane_verify >> %s/stages.log\n' "$TMP" > "$VL/VERIFY.sh"
vctl() { (cd "$V" && bash "$SCRIPTS_DIR/controller.sh" "$@" >/dev/null); }
vctl set v base_sha "$(git -C "$V" rev-parse HEAD~1)"
vctl set v red_sha "$(git -C "$V" rev-parse HEAD)"
printf 'x=1\n' > "$V/src/app.py"
vrun() { : > "$TMP/stages.log"; (cd "$V" && AUTODEV_PHASE="$1" bash "$SCRIPTS_DIR/verify.sh" "$V" "$VL" >/dev/null 2>&1); }
stages() { tr '\n' ' ' < "$TMP/stages.log" | sed 's/ $//'; }

vrun attempt; assert "verify: all stages pass" "0" "$?"
assert "verify: stage order" "lint format_check lane_verify full_suite" "$(stages)"

vrun baseline; assert "verify: baseline passes" "0" "$?"
assert "verify: baseline skips red and lint stages" "lane_verify full_suite" "$(stages)"

printf 'exit 1\n' > "$V/lint.sh"
vrun attempt; assert "verify: lint failure fails" "1" "$?"
assert "verify: stops at lint" "lint" "$(stages)"
printf 'exit 0\n' > "$V/lint.sh"

printf 'exit 1\n' > "$V/tests/slice1_test.sh"
git -C "$V" commit -q -am "test: red"
vctl set v red_sha "$(git -C "$V" rev-parse HEAD)"
vrun attempt; assert "verify: failing red test fails" "1" "$?"
assert "verify: stops before lint" "" "$(stages)"

printf 'exit 0\n' > "$V/tests/slice1_test.sh"
vrun attempt; assert "verify: edited red test fails" "1" "$?"
assert "verify: frozen check stops first" "" "$(stages)"
git -C "$V" checkout -q -- tests/slice1_test.sh
git -C "$V" rm -q tests/slice1_test.sh
vrun attempt; assert "verify: deleted red test fails" "1" "$?"
git -C "$V" checkout -q HEAD -- tests/slice1_test.sh

# test_config is frozen with the red tests: a skip marker there is a tamper.
printf 'exit 0\n' > "$V/tests/slice1_test.sh"; git -C "$V" commit -q -am "test: green fixture"
printf '# config\n' > "$V/conftest.py"; git -C "$V" add conftest.py; git -C "$V" commit -q -m "test: config"
vctl set v red_sha "$(git -C "$V" rev-parse HEAD)"
python3 - "$VL/profile.md" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
open(p,'w').write(s.replace("---\n", "---\ntest_config: conftest.py\ncoverage: echo covered\n", 1))
PY
vrun attempt; assert "verify: green with test_config frozen" "0" "$?"
grep -q '^covered$' "$VL/coverage.log"; assert "verify: coverage report written" "0" "$?"
printf 'collect_ignore = ["tests"]\n' >> "$V/conftest.py"
vrun attempt; assert "verify: changed test_config fails" "1" "$?"
git -C "$V" checkout -q -- conftest.py

# Missing keys: lint is a logged skip; test_file with red tests is a failure.
python3 - "$VL/profile.md" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
s="\n".join(l for l in s.split("\n") if not l.startswith(("lint:", "test_file:")))
open(p,'w').write(s)
PY
out=$(cd "$V" && bash "$SCRIPTS_DIR/verify.sh" "$V" "$VL" 2>&1); rc=$?
assert "verify: no test_file with red tests fails" "1" "$rc"
python3 - "$VL/profile.md" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
open(p,'w').write(s.replace("---\n", "---\ntest_file: sh {file}\n", 1))
PY
out=$(cd "$V" && bash "$SCRIPTS_DIR/verify.sh" "$V" "$VL" 2>&1); rc=$?
assert "verify: missing lint key still passes" "0" "$rc"
printf '%s\n' "$out" | grep -q 'skipped: no lint in TDD profile'; assert "verify: missing lint key is logged" "0" "$?"

# A present-but-empty key is a profile error, never a silent skip.
cat > "$VL/profile.md" <<EOF
---
test_file: sh {file}
format_check: sh -c 'echo format_check >> $TMP/stages.log' -- {files}
full_suite: echo full_suite >> $TMP/stages.log
test_config: conftest.py
---
EOF
cp "$VL/profile.md" "$TMP/profile.keep"
printf 'tests/slice1_test.sh\n' > "$VL/red_tests.txt"
vrun attempt; assert "verify: good profile passes (control)" "0" "$?"
python3 - "$VL/profile.md" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
open(p,'w').write(s.replace("test_config: conftest.py", "test_config:"))
PY
printf 'tests/slice1_test.sh\n' > "$VL/red_tests.txt"
(cd "$V" && bash "$SCRIPTS_DIR/verify.sh" "$V" "$VL" >/dev/null 2>&1); rc=$?
assert "verify: empty profile value fails, not skips" "1" "$rc"
cp "$TMP/profile.keep" "$VL/profile.md"

# A non-exempt lane must have red tests by its first attempt.
: > "$VL/red_tests.txt"
(cd "$V" && bash "$SCRIPTS_DIR/verify.sh" "$V" "$VL" >/dev/null 2>&1); rc=$?
assert "verify: non-exempt lane with no red tests fails" "1" "$rc"

# An exempt lane verifies through its lane VERIFY.sh only, as before TDD.
sed -i.bak 's/^red_tests: pending$/red_tests: exempt — docs only/' "$VL/TASK.md"
vrun attempt; assert "verify: exempt lane passes on lane VERIFY.sh" "0" "$?"
assert "verify: exempt lane runs only lane VERIFY.sh" "lane_verify" "$(stages)"
mv "$VL/TASK.md.bak" "$VL/TASK.md"

# Full-suite precedence: profile full_suite wins over a repo VERIFY.sh.
printf 'tests/slice1_test.sh\n' > "$VL/red_tests.txt"
printf 'echo repo_verify >> %s/stages.log\n' "$TMP" > "$V/VERIFY.sh"
git -C "$V" add VERIFY.sh; git -C "$V" commit -q -m "chore: repo verify"
vctl set v red_sha "$(git -C "$V" rev-parse HEAD)"
vrun baseline
assert "verify: profile full_suite beats repo VERIFY.sh" "lane_verify full_suite" "$(stages)"

# Existing tests (present at base_sha) are frozen unless TASK.md authorizes them.
X="$TMP/old_tests_repo"
make_repo "$X"
mkdir -p "$X/.claude" "$X/tests"
printf -- '---\ntest_file: sh {file}\nfull_suite: true\n---\n' > "$X/.claude/autodev.md"
printf 'exit 0\n' > "$X/tests/old_test.sh"
git -C "$X" add tests; git -C "$X" commit -q -m "test: existing"
(cd "$X" && bash "$SCRIPTS_DIR/init_task_lane.sh" o "Task." >/dev/null && bash "$SCRIPTS_DIR/create_worktree.sh" o main >/dev/null)
XW="$X/.autodev-worktrees/o"; XL="$X/.autodev/o"
printf 'exit 0\n' > "$XW/tests/red_test.sh"
git -C "$XW" add tests/red_test.sh; git -C "$XW" commit -q -m "test: red"
(cd "$X" && bash "$SCRIPTS_DIR/controller.sh" set o red_sha "$(git -C "$XW" rev-parse HEAD)" >/dev/null)
printf 'tests/red_test.sh\n' > "$XL/red_tests.txt"
xv() { (cd "$X" && bash "$SCRIPTS_DIR/verify.sh" "$XW" "$XL" >/dev/null 2>&1); }
printf 'exit 0\n' > "$XW/tests/new_test.sh"
xv; assert "verify: a new test file is allowed" "0" "$?"
printf '# rewritten\nexit 0\n' > "$XW/tests/old_test.sh"
xv; assert "verify: edited existing test fails" "1" "$?"
printf '\n## Test edits authorized\n- tests/old_test.sh\n' >> "$XL/TASK.md"
xv; assert "verify: authorized existing test edit passes" "0" "$?"

# Renaming a red test is caught like a delete.
git -C "$V" mv tests/slice1_test.sh tests/renamed_test.sh
vrun attempt; assert "verify: renamed red test fails" "1" "$?"
git -C "$V" mv tests/renamed_test.sh tests/slice1_test.sh

# =============================================================================
echo "=== commit_lane.sh ==="
# =============================================================================

K="$TMP/commit_repo"
make_repo "$K"
(cd "$K" && bash "$SCRIPTS_DIR/init_task_lane.sh" k "Task." >/dev/null)
KL="$K/.autodev/k"
kctl() { (cd "$K" && bash "$SCRIPTS_DIR/controller.sh" "$@"); }
cl() { (cd "$K" && bash "$SCRIPTS_DIR/commit_lane.sh" "$K" "$KL" "$@" >/dev/null 2>&1); }
mkdir -p "$K/tests"
printf 'exit 1\n' > "$K/tests/a_test.sh"
printf 'junk\n' > "$K/coverage.xml"

cl red "test(widget): add red test for count" tests/a_test.sh; assert "commit: red commit succeeds" "0" "$?"
assert "commit: subject is the given subject" "test(widget): add red test for count" "$(git -C "$K" log -1 --format=%s)"
git -C "$K" ls-files --error-unmatch coverage.xml >/dev/null 2>&1; assert "commit: unlisted stray file not staged" "1" "$?"
assert "commit: red records red_sha" "$(git -C "$K" rev-parse HEAD)" "$(kctl get k red_sha)"
git -C "$K" log -1 --format=%B | grep -qi 'co-authored-by'; assert "commit: no attribution footer" "1" "$?"

printf 'x\n' > "$K/a.txt"
cl green "Fix: Bad Subject." a.txt; assert "commit: non-conventional subject rejected" "2" "$?"
git -C "$K" diff --cached --quiet; assert "commit: rejected subject stages nothing" "0" "$?"
cl green "feat(widget): $(printf 'x%.0s' $(seq 1 70))" a.txt; assert "commit: subject over 72 chars rejected" "2" "$?"

kctl record-failure k implementation fp1 >/dev/null
cl green "feat(widget): count items" a.txt; assert "commit: green commit succeeds" "0" "$?"
assert "commit: green records green_sha" "$(git -C "$K" rev-parse HEAD)" "$(kctl get k green_sha)"
assert "commit: green resets the slice cap" "0" "$(kctl get k counted_failures)"

# A failing hook is a hard failure: no commit, no bypass.
mkdir -p "$K/.git/hooks"
printf '#!/bin/sh\necho "hook says no" >&2\nexit 1\n' > "$K/.git/hooks/pre-commit"
chmod +x "$K/.git/hooks/pre-commit"
before=$(git -C "$K" rev-parse HEAD)
printf 'y\n' > "$K/b.txt"
cl green "feat(widget): more" b.txt; assert "commit: hook failure fails" "1" "$?"
assert "commit: hook failure leaves HEAD" "$before" "$(git -C "$K" rev-parse HEAD)"
/bin/rm -f "$K/.git/hooks/pre-commit"

# =============================================================================
echo "=== drop_slice.sh ==="
# =============================================================================

# Lane with a green slice 1 and a committed slice 2 red test (appended to the
# same file), plus the worker's uncommitted attempt at slice 2.
D="$TMP/drop_repo"
make_repo "$D"
mkdir -p "$D/.claude"
printf -- '---\ntest_file: sh {file}\nfull_suite: true\n---\n' > "$D/.claude/autodev.md"
(cd "$D" && bash "$SCRIPTS_DIR/init_task_lane.sh" dl "Task." >/dev/null && bash "$SCRIPTS_DIR/create_worktree.sh" dl main >/dev/null)
DW="$D/.autodev-worktrees/dl"; DL="$D/.autodev/dl"
dctl() { (cd "$D" && bash "$SCRIPTS_DIR/controller.sh" "$@"); }
dcl() { (cd "$D" && bash "$SCRIPTS_DIR/commit_lane.sh" "$DW" "$DL" "$@" >/dev/null 2>&1); }
mkdir -p "$DW/tests" "$DW/src"
printf 'true\n' > "$DW/tests/s_test.sh"
dcl red "test(x): slice 1 red" tests/s_test.sh
printf '# Test review\n' > "$DL/test-review.md"
dctl set dl checkpoint confirmed >/dev/null
printf 'tests/s_test.sh\n' > "$DL/red_tests.txt"
printf 'ok\n' > "$DW/src/a.txt"; dcl green "feat(x): slice 1" src/a.txt
slice1="$(cat "$DW/tests/s_test.sh")"
printf 'exit 1\n' >> "$DW/tests/s_test.sh"; dcl red "test(x): slice 2 red" tests/s_test.sh
printf 'exit 0\n' > "$DW/tests/n_test.sh"; dcl red "test(x): slice 2 second red" tests/n_test.sh
printf 'tests/n_test.sh\n' >> "$DL/red_tests.txt"
printf 'attempt\n' > "$DW/src/a.txt"
dctl record-failure dl specification "spec_gap: y" >/dev/null
(cd "$D" && bash "$SCRIPTS_DIR/verify.sh" "$DW" "$DL" >/dev/null 2>&1)
assert "drop: slice 2 red fails verify before the drop (control)" "1" "$?"

(cd "$D" && bash "$SCRIPTS_DIR/drop_slice.sh" "$DW" "$DL" "advisor kept the current rule" >/dev/null 2>&1)
assert "drop: exits 0" "0" "$?"
assert "drop: worktree clean" "" "$(git -C "$DW" status --porcelain)"
assert "drop: shared red file back to slice 1" "$slice1" "$(cat "$DW/tests/s_test.sh")"
[ -e "$DW/tests/n_test.sh" ] && gone=0 || gone=1; assert "drop: slice-only red file removed" "1" "$gone"
grep -qx 'tests/n_test.sh' "$DL/red_tests.txt"; assert "drop: removed file leaves red_tests.txt" "1" "$?"
git -C "$DW" log -1 --format=%s | grep -q '^revert(autodev): drop slice'; assert "drop: revert commit subject" "0" "$?"
assert "drop: red_sha moves to the revert" "$(git -C "$DW" rev-parse HEAD)" "$(dctl get dl red_sha)"
assert "drop: lane continues" "continue" "$(dctl check dl)"
grep -q 'advisor kept the current rule' "$DL/dropped.md"; assert "drop: reason logged" "0" "$?"
(cd "$D" && bash "$SCRIPTS_DIR/verify.sh" "$DW" "$DL" >/dev/null 2>&1)
assert "drop: earlier slices still verify" "0" "$?"

# A drop at the launch checkpoint logs to dropped.md and touches nothing else.
head_before="$(git -C "$DW" rev-parse HEAD)"; red_before="$(dctl get dl red_sha)"
(cd "$D" && bash "$SCRIPTS_DIR/drop_slice.sh" --checkpoint "$DL" "advisor dropped scenario 3" >/dev/null 2>&1)
assert "drop --checkpoint: exits 0" "0" "$?"
grep -q 'advisor dropped scenario 3' "$DL/dropped.md"; assert "drop --checkpoint: reason logged" "0" "$?"
grep -q 'launch checkpoint' "$DL/dropped.md"; assert "drop --checkpoint: stage logged" "0" "$?"
assert "drop --checkpoint: no commit" "$head_before" "$(git -C "$DW" rev-parse HEAD)"
assert "drop --checkpoint: red_sha unchanged" "$red_before" "$(dctl get dl red_sha)"

# =============================================================================
echo "=== eval grader (offline) ==="
# =============================================================================

EV="$AUTODEV_ROOT/tests/eval"
bash "$EV/live-validate.sh" --grade "$EV/fixtures/auth-system.gold.md" >/dev/null 2>&1
assert "eval: gold plan passes every check" "0" "$?"
grep -v 'Q2: OAuth' "$EV/fixtures/auth-system.gold.md" > "$TMP/degraded.md"
bash "$EV/live-validate.sh" --grade "$TMP/degraded.md" >/dev/null 2>&1
assert "eval: plan missing OAuth in Q2 fails" "1" "$?"
sed 's/depends on data from the previous test (shared database state)/fine/' "$EV/fixtures/auth-system.gold.md" > "$TMP/degraded.md"
bash "$EV/live-validate.sh" --grade "$TMP/degraded.md" >/dev/null 2>&1
assert "eval: review missing shared state fails" "1" "$?"

echo ""
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
