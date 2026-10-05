#!/usr/bin/env bash
# Lifecycle tests for worktree-lanes/scripts/lane. Self-contained: each case
# builds a throwaway repo (no remote) in a tmpdir, writes a .lanerc, and drives
# the engine. Socket discovery is stubbed (a PATH shim for lsof), so results do
# not depend on what is listening on the host. Exits 0 only when all pass.
#
# LANE_TEST_BASH=/bin/bash runs the engine under another bash (e.g. macOS 3.2).
set -uo pipefail

export GIT_AUTHOR_NAME="lane-test" GIT_AUTHOR_EMAIL="lane-test@example.com"
export GIT_COMMITTER_NAME="lane-test" GIT_COMMITTER_EMAIL="lane-test@example.com"

HERE="$(cd "$(dirname "$0")" && pwd)"
LANE="$(cd "$HERE/.." && pwd)/scripts/lane"
BASH_BIN="${LANE_TEST_BASH:-bash}"

PASS=0
FAIL=0
ok()   { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else fail "$1" "expected: $2"$'\n'"got:      $3"; fi; }
yn() { if "$@"; then echo yes; else echo no; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# lsof shim: a port "listens" iff it is in $LANE_TEST_LISTENING.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/lsof" <<'EOF'
#!/bin/sh
p=""
for a in "$@"; do case "$a" in -iTCP:*) p="${a#-iTCP:}" ;; esac; done
case " ${LANE_TEST_LISTENING:-} " in *" $p "*) exit 0 ;; esac
exit 1
EOF
chmod +x "$TMP/bin/lsof"
export PATH="$TMP/bin:$PATH"
export LANE_TEST_LISTENING=""

# A PID guaranteed dead: a finished child's.
DEAD_PID="$(sh -c 'echo $$')"

# new_repo <name> — fresh repo with one commit on main; cd into it.
new_repo() {
  REPO_DIR="$TMP/$1"
  mkdir -p "$REPO_DIR" && cd "$REPO_DIR" || exit 1
  git init -q -b main
  echo app > app.txt
  git add app.txt && git commit -qm init
}
lane() { "$BASH_BIN" "$LANE" "$@"; }
WT() { echo "$REPO_DIR/.claude/worktrees/$1"; }
STATE() { echo "$REPO_DIR/.claude/worktrees/.state/$1"; }

echo "=== arguments ==="
new_repo args
cat > .lanerc <<'EOF'
touch "$LANE_MAIN_MARKER"
LANE_MODES="host proxy"
EOF
export LANE_MAIN_MARKER="$REPO_DIR/sourced"
git checkout -q -b release && git commit -q --allow-empty -m rel && git checkout -q main
lane --help >/dev/null 2>&1; check "--help: exit 0" 0 $?
lane open x --help >/dev/null 2>&1
check "--help: recipe not sourced" no "$(yn test -e sourced)"
lane open feat-x --base release >/dev/null 2>&1
check "open <slug> --base <ref>: exit 0" 0 $?
check "open: lane named by slug, not base" "feat-x" "$(git -C "$(WT feat-x)" rev-parse --abbrev-ref HEAD 2>&1)"
check "open: cut from the --base commit" "$(git rev-parse release)" "$(git -C "$(WT feat-x)" rev-parse HEAD)"
lane open a b >/dev/null 2>&1; check "open: extra positional rejected" 1 $?
lane open c --bogus >/dev/null 2>&1; check "open: unknown flag rejected" 1 $?
lane rm feat-x --start >/dev/null 2>&1; check "rm: flag of another verb rejected" 1 $?
lane open d --isolated >/dev/null 2>&1; check "open: mode the recipe does not declare rejected" 1 $?
mkdir -p "$TMP/args-outside" && touch "$TMP/args-outside/keep"
lane rm ../../../args-outside >/dev/null 2>&1; check "rm: path-traversal slug rejected" 1 $?
check "rm: traversal target untouched" yes "$(yn test -f "$TMP/args-outside/keep")"
lane open e --base no-such-ref >/dev/null 2>&1; check "open: unresolvable base fails" 1 $?
check "open: failed base leaves no worktree or state" no "$(yn test -e "$(WT e)" -o -e "$(STATE e)")"
unset LANE_MAIN_MARKER

echo "=== rm safety ==="
new_repo rmsafe
: > .lanerc
lane open w >/dev/null 2>&1
echo work > "$(WT w)/new-file.txt"
lane rm w >/dev/null 2>&1; check "rm: refuses a lane with uncommitted work" 1 $?
check "rm: refused lane still has its work" work "$(cat "$(WT w)/new-file.txt" 2>&1)"
lane rm w --force >/dev/null 2>&1; check "rm --force: removes the dirty lane" 0 $?
check "rm: branch kept" yes "$(yn git show-ref --verify --quiet refs/heads/w)"
lane open clean >/dev/null 2>&1
lane rm clean >/dev/null 2>&1; check "rm: clean lane (engine-made .env only) removed" 0 $?
echo 'LANE_LINK_DIRS="app.txt"' > .lanerc
lane open linked >/dev/null 2>&1
echo edited >> "$(WT linked)/app.txt"
lane rm linked >/dev/null 2>&1; check "rm: edit to a real file named in LANE_LINK_DIRS blocks rm" 1 $?
check "rm: that edit survives" yes "$(yn grep -q edited "$(WT linked)/app.txt")"
cat > .lanerc <<'EOF'
lane_stop() { false; echo reached > "$LANE_MAIN/stop-after-failure"; }
EOF
lane open stuck >/dev/null 2>&1
lane rm stuck >/dev/null 2>&1; check "rm: failing teardown hook keeps the lane" 1 $?
check "rm: lane still present after failed teardown" yes "$(yn test -d "$(WT stuck)")"
check "rm: teardown hook stops at its failing command" no "$(yn test -e stop-after-failure)"

echo "=== strict hooks + resume ==="
new_repo strict
cat > .lanerc <<'EOF'
lane_setup() { [ -f "$LANE_MAIN/allow-setup" ]; echo reached > "$LANE_DIR/after-failure"; }
EOF
out="$(lane open s 2>&1)"; rc=$?
check "open: failing lane_setup exits non-zero" 1 "$rc"
check "open: no 'lane ready' after a failed hook" no "$(yn grep -q 'lane ready' <<<"$out")"
check "open: hook stops at the failing command" no "$(yn test -e "$(WT s)/after-failure")"
touch allow-setup
lane resume s >/dev/null 2>&1; check "resume: completes the interrupted open" 0 $?
check "resume: phase is ready" "PHASE=ready" "$(grep '^PHASE=' "$(STATE s)")"
cat > .lanerc <<'EOF'
lane_env() { false; echo IGNORED_FAILURE=yes; }
EOF
lane open envfail >/dev/null 2>&1
check "open: lane_env failing mid-hook exits non-zero" 1 $?
check "open: lane_env failure writes no env file" no "$(yn test -e "$(WT envfail)/.env")"
check "open: no temp files left in the lane" "" "$(find "$(WT envfail)" -maxdepth 1 -name '.lane.*')"
lane rm envfail >/dev/null 2>&1; check "rm: lane from a failed open is clean (no temp leftovers)" 0 $?

echo "=== env file ==="
new_repo envf
printf 'DB_NAME=shared\nSECRET=main-secret\nexport DB_NAME=shared-too\r\n' > .env
cat > .lanerc <<'EOF'
LANE_PORT_VARS="WEB_PORT:41000"
lane_env() {
  echo "DB_NAME=${LANE_PROJECT}_db"
  echo "WEB_URL=http://localhost:${WEB_PORT}"
}
EOF
lane open env1 >/dev/null 2>&1
ENVF="$(WT env1)/.env"
check "env: every definition of a set key collapses to one" "DB_NAME=envf-env1_db" "$(grep -E '^(export )?DB_NAME=' "$ENVF")"
check "env: hook sees per-lane port" "WEB_URL=http://localhost:41100" "$(grep '^WEB_URL=' "$ENVF")"
check "env: main env copied by default" "SECRET=main-secret" "$(grep '^SECRET=' "$ENVF")"
cat > .lanerc <<'EOF'
LANE_ENV_COPY=0
EOF
lane open nocopy >/dev/null 2>&1; check "env: LANE_ENV_COPY=0 open succeeds" 0 $?
check "env: LANE_ENV_COPY=0 still writes the env file" yes "$(yn test -f "$(WT nocopy)/.env")"
check "env: LANE_ENV_COPY=0 leaves main's secrets out" no "$(yn grep -q '^SECRET=' "$(WT nocopy)/.env")"
echo 'LANE_ENV_COPY=true' > .lanerc
lane open badflag >/dev/null 2>&1; check "settings: on/off value other than 1/0 rejected" 1 $?
check "settings: rejected value creates nothing" no "$(yn test -e "$(WT badflag)")"
echo 'LANE_CHECKOUT_HOOKS=' > .lanerc
lane open emptyflag >/dev/null 2>&1; check "settings: empty on/off value rejected" 1 $?
cat > .lanerc <<'EOF'
lane_setup() { echo "$LANE_ENV_FILE $LANE_ENV_COPY" > "$LANE_MAIN/seen-settings"; }
EOF
lane open seen >/dev/null 2>&1
check "hooks see resolved settings, defaults included" ".env 1" "$(cat seen-settings 2>&1)"
: > .lanerc
lane open keep >/dev/null 2>&1
chmod 000 .env
lane resume keep --env >/dev/null 2>&1; rc=$?
chmod 644 .env
check "env: unreadable main env fails the regeneration" 1 "$rc"
check "env: failed regeneration leaves the lane's env file intact" "SECRET=main-secret" "$(grep '^SECRET=' "$(WT keep)/.env")"
cat > .lanerc <<'EOF'
LANE_PORT_VARS="WEB_PORT:41000"
lane_env() { echo "WEB_PORT=49999"; }
EOF
lane open env3 >/dev/null 2>&1; check "env: lane_env may not override an allocated port" 1 $?
cat > .lanerc <<'EOF'
lane_env() { echo "not a key value line"; }
EOF
lane open env2 >/dev/null 2>&1; check "env: malformed lane_env output fails the open" 1 $?
cat > .lanerc <<'EOF'
lane_env() { echo "GREETING=$(cat "$LANE_MAIN/greeting")"; }
EOF
echo one > greeting; lane open regen >/dev/null 2>&1
echo two > greeting; lane resume regen >/dev/null 2>&1
check "resume: env file kept without --env" "GREETING=one" "$(grep '^GREETING=' "$(WT regen)/.env")"
lane resume regen --env >/dev/null 2>&1
check "resume --env: env file regenerated" "GREETING=two" "$(grep '^GREETING=' "$(WT regen)/.env")"

new_repo tracked
echo "TRACKED=1" > .env && git add .env && git commit -qm env
: > .lanerc
lane open t >/dev/null 2>&1; check "env: tracked env file refused" 1 $?
check "env: refused open leaves no worktree" no "$(yn test -e "$(WT t)")"
check "env: refused open leaves no branch" no "$(yn git show-ref --verify --quiet refs/heads/t)"
check "env: tracked file in main untouched" "TRACKED=1" "$(cat .env)"
git rm -q .env && git commit -qm untrack
cat > .lanerc <<'EOF'
lane_project() { [ -f "$LANE_MAIN/ok" ]; echo p; }
EOF
lane open later >/dev/null 2>&1
( cd "$(WT later)" && echo "USER WORK" > .env && git add -f .env && git commit -qm "user env" )
touch ok
lane resume later >/dev/null 2>&1; check "resume: env file tracked since the open is refused" 1 $?
check "resume: user's tracked env content survives" "USER WORK" "$(cat "$(WT later)/.env")"

echo "=== checkout hooks ==="
new_repo hooks
# Husky-style repo hooks: committed dir + core.hooksPath. Each hook logs its name.
mkdir .hk
printf '#!/bin/sh\nbasename "$0" >> "%s/fired"\n' "$REPO_DIR" > .hk/post-checkout
cp .hk/post-checkout .hk/pre-commit && chmod +x .hk/*
git add .hk && git commit -qm hooks && git config core.hooksPath .hk && rm -f fired
: > .lanerc
lane open h1 >/dev/null 2>&1; check "hooks: open in a repo with checkout hooks succeeds" 0 $?
check "hooks: repo's post-checkout does not run when a lane is created" no "$(yn grep -qs post-checkout fired)"
git -C "$(WT h1)" commit -q --allow-empty -m x
check "hooks: repo's commit hooks still run in the lane" yes "$(yn grep -qs pre-commit fired)"
echo 'LANE_CHECKOUT_HOOKS=1' > .lanerc && rm -f fired
lane open h2 >/dev/null 2>&1
check "hooks: LANE_CHECKOUT_HOOKS=1 runs the repo's post-checkout" yes "$(yn grep -qs post-checkout fired)"
echo 'LANE_CHECKOUT_HOOKS=0' > .lanerc && rm -f fired
GIT_CONFIG_PARAMETERS="'core.hooksPath=.hk'" lane open h3 >/dev/null 2>&1
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=.hk lane open h4 >/dev/null 2>&1
check "hooks: an inherited -c / GIT_CONFIG_* hooksPath can't turn them back on" no "$(yn grep -qs post-checkout fired)"
check "hooks: those opens succeeded" yes "$(yn test -d "$(WT h3)" -a -d "$(WT h4)")"
LANE_RECIPE=.lanerc lane open rel1 >/dev/null 2>&1; check "recipe: relative LANE_RECIPE from main" 0 $?
( cd "$(WT h1)" && LANE_RECIPE=../../../.lanerc "$BASH_BIN" "$LANE" open rel2 >/dev/null 2>&1 )
check "recipe: relative LANE_RECIPE from another worktree" 0 $?

echo "=== ports ==="
new_repo ports
cat > .lanerc <<'EOF'
LANE_PORT_VARS="WEB_PORT:41000 API_PORT:41100"
EOF
lane open p1 >/dev/null 2>&1
lane open p2 >/dev/null 2>&1
check "ports: first lane skips main's ports and cross-key collisions" "PORTS=WEB_PORT:41200 API_PORT:41300" "$(grep '^PORTS=' "$(STATE p1)")"
check "ports: second lane is disjoint from the first" "PORTS=WEB_PORT:41400 API_PORT:41500" "$(grep '^PORTS=' "$(STATE p2)")"
LANE_TEST_LISTENING="41700" lane open p3 >/dev/null 2>&1
check "ports: offset with a listening port is skipped" "PORTS=WEB_PORT:41800 API_PORT:41900" "$(grep '^PORTS=' "$(STATE p3)")"
echo 'LANE_PORT_VARS="PATH:41000"' > .lanerc
lane open bad1 >/dev/null 2>&1; check "ports: reserved key rejected" 1 $?
echo 'LANE_PORT_VARS="BASHOPTS:41000"' > .lanerc
lane open bad2 >/dev/null 2>&1; check "ports: shell-special key rejected" 1 $?
check "ports: rejected key creates nothing" no "$(yn test -e "$(WT bad2)")"
echo 'LANE_PORT_VARS="WEB_PORT:41000 WEB_PORT:42000"' > .lanerc
lane open bad3 >/dev/null 2>&1; check "ports: duplicate key rejected" 1 $?

new_repo legacy
echo 'LANE_PORT_VARS="WEB_PORT:41000"' > .lanerc
# Lanes made by other tooling: ports recorded (quoted / export+CRLF), no LANE_OFFSET.
git worktree add -q -b old1 "$(WT old1)"
echo "WEB_PORT='41100'" > "$(WT old1)/.env"
git worktree add -q -b old2 "$(WT old2)"
printf 'export WEB_PORT=41200\r\n' > "$(WT old2)/.env"
lane open fresh >/dev/null 2>&1
check "ports: unmanaged lanes' recorded ports are not reused" "PORTS=WEB_PORT:41300" "$(grep '^PORTS=' "$(STATE fresh)")"
cat > .lanerc <<'EOF'
LANE_PORT_VARS="WEB_PORT:41000"
lane_stop() { echo "$WEB_PORT" > "$LANE_MAIN/stopped-port"; }
EOF
lane rm old2 >/dev/null 2>&1; check "rm: unmanaged lane removed" 0 $?
check "rm: unmanaged lane's hooks get its recorded port" 41200 "$(cat stopped-port 2>&1)"

echo "=== reservations, locks, gc ==="
new_repo gc
: > .lanerc
lane open g >/dev/null 2>&1
check "lanes root self-ignored in main" "" "$(git status --porcelain -- .claude)"
git worktree remove --force "$(WT g)"
printf 'PHASE=allocated\nOWNER=%s\nOFFSET=7\n' "$$" > "$(STATE live)"
printf 'PHASE=allocated\nOWNER=%s\nOFFSET=8\n' "$DEAD_PID" > "$(STATE dead)"
lane gc >/dev/null 2>&1
check "gc: state of a vanished worktree dropped" no "$(yn test -e "$(STATE g)")"
check "gc: in-progress reservation (live owner) kept" yes "$(yn test -e "$(STATE live)")"
check "gc: abandoned reservation (dead owner) dropped" no "$(yn test -e "$(STATE dead)")"
printf 'PHASE=allocated\nOWNER=%s\nOFFSET=9\n' "$DEAD_PID" > "$(STATE retry)"
lane open retry >/dev/null 2>&1; check "open: slug with abandoned reservation reopens" 0 $?
lane open live >/dev/null 2>&1; check "open: slug with live reservation refused" 1 $?
mkdir "$REPO_DIR/.claude/worktrees/.state/.lock" && echo "$DEAD_PID" > "$REPO_DIR/.claude/worktrees/.state/.lock/pid"
lane open afterlock >/dev/null 2>&1; check "lock: stale lock from a dead process reclaimed" 0 $?
lane open dup >/dev/null 2>&1 & a=$!
lane open dup >/dev/null 2>&1 & b=$!
wait "$a"; ra=$?; wait "$b"; rb=$?
check "open: concurrent opens of one slug — exactly one wins" 1 $((ra + rb))
check "open: winner's state intact" "PHASE=ready" "$(grep '^PHASE=' "$(STATE dup)")"

echo ""
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
