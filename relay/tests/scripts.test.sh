#!/usr/bin/env bash
# Tests for relay scripts: extract-transcript.sh, resolve-session.sh, and
# session-start-pickup.sh. Self-contained: builds throwaway fixtures/sandboxes
# in tmpdir, no network, no writes outside tmpdir (HOME is always overridden
# to a sandbox — the real ~/.claude is never touched). Prints per-case
# pass/fail, exits 0 only when all cases pass.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
RELAY_ROOT="$(cd "$(dirname "$HERE")" && pwd)"
SCRIPTS_DIR="$RELAY_ROOT/scripts"
FIXTURES_DIR="$HERE/fixtures"

PASS=0
FAIL=0

# assert <name> <expected> <actual>
assert() {
    if [ "$2" = "$3" ]; then
        PASS=$((PASS + 1)); printf '  ok   %-60s -> %s\n' "$1" "$3"
    else
        FAIL=$((FAIL + 1)); printf '  FAIL %-60s expected %s, got %s\n' "$1" "$2" "$3"
    fi
}

# assert_true <name> <condition-as-0/1>
assert_true() {
    if [ "$2" -eq 0 ]; then
        PASS=$((PASS + 1)); printf '  ok   %-60s\n' "$1"
    else
        FAIL=$((FAIL + 1)); printf '  FAIL %-60s\n' "$1"
    fi
}

# assert_contains <name> <haystack> <needle>
assert_contains() {
    case "$2" in
        *"$3"*) PASS=$((PASS + 1)); printf '  ok   %-60s\n' "$1" ;;
        *) FAIL=$((FAIL + 1)); printf '  FAIL %-60s missing: %s\n' "$1" "$3" ;;
    esac
}

# assert_not_contains <name> <haystack> <needle>
assert_not_contains() {
    case "$2" in
        *"$3"*) FAIL=$((FAIL + 1)); printf '  FAIL %-60s should not contain: %s\n' "$1" "$3" ;;
        *) PASS=$((PASS + 1)); printf '  ok   %-60s\n' "$1" ;;
    esac
}

START_TIME=$(date +%s)

# =============================================================================
# extract-transcript.sh tests
# =============================================================================

echo "=== extract-transcript.sh tests ==="

# The committed fixture holds @@FAKE_*@@ placeholders; the token-shaped fakes
# are assembled here from fragments so no secret-pattern string is ever
# committed (keeps gitleaks fully armed on this repo, no allowlist holes).
PRIV="PRIVATE"
FAKE_AWS="AKIA""ABCDEFGHIJKLMNOP"
FAKE_GHP="ghp_""1234567890abcdefghijklmnopqrstuvwxyz"
FAKE_PEM_B64="MIIBOgIBAAJBAKj34GkxFhD90vcNLYLInFEX6Ppy1tPf9Cnzj4p4WGeKLs1Pt8Qu"
PEM_HEADER="-----BEGIN RSA ${PRIV} KEY-----"
PEM_FOOTER="-----END RSA ${PRIV} KEY-----"
# JSON-escaped newlines (literal backslash-n) — this lands inside a JSONL string.
FAKE_PEM_JSON="${PEM_HEADER}"'\n'"${FAKE_PEM_B64}"'\n'"KUpRKfFLfRYC9AIKjbJTWit+CqvjWYzvQwECAwEAAQ=="'\n'"${PEM_FOOTER}"
FAKE_BEARER="abc123.def456.ghi789secrettoken"

MAIN_TMP=$(mktemp -d)
trap 'rm -rf "$MAIN_TMP"' EXIT
MAIN_FIXTURE="$MAIN_TMP/main.jsonl"
main_src=$(cat "$FIXTURES_DIR/main.jsonl")
main_src=${main_src//@@FAKE_AWS@@/$FAKE_AWS}
main_src=${main_src//@@FAKE_GHP@@/$FAKE_GHP}
main_src=${main_src//@@FAKE_PEM@@/$FAKE_PEM_JSON}
main_src=${main_src//@@FAKE_BEARER@@/$FAKE_BEARER}
printf '%s\n' "$main_src" > "$MAIN_FIXTURE"

MAIN_OUT="$(bash "$SCRIPTS_DIR/extract-transcript.sh" "$MAIN_FIXTURE")"

# --- Files touched: 100% structural recall ---
assert_contains "extract: fileA edits recorded"  "$MAIN_OUT" "/repo/fileA.txt (edits: 3)"
assert_contains "extract: fileB write recorded"  "$MAIN_OUT" "/repo/fileB.txt (writes: 1)"
assert_contains "extract: fileC reads recorded"  "$MAIN_OUT" "/repo/fileC.txt (reads: 2)"

# --- Commands run: all 6 planted commands recovered with desc + first-120 cap ---
assert_contains "extract: cmd 'List files' recovered"     "$MAIN_OUT" "List files: ls -la"
assert_contains "extract: cmd 'Check git status' recovered" "$MAIN_OUT" "Check git status: git status"
assert_contains "extract: cmd 'Run tests' recovered"      "$MAIN_OUT" "Run tests: npm test"
assert_contains "extract: cmd 'Install deps' recovered"   "$MAIN_OUT" "Install deps: npm install"
assert_contains "extract: cmd 'Show diff' recovered"      "$MAIN_OUT" "Show diff: git diff"

# --- Commands run: a literal "|" inside the command field survives the @tsv/
# IFS=tab column split intact (used to split the desc/cmd columns before the
# @tsv fix) ---
assert_contains "extract: cmd with literal pipe char stays intact" "$MAIN_OUT" "Count matching lines: grep -c foo file.txt | wc -l"

# --- Failures: all 3 planted failures recovered (string content, single-line
# array content, multi-line array content) ---
assert_contains "extract: string-content failure recovered" "$MAIN_OUT" "Error: file not found: missing.txt"
assert_contains "extract: array-content failure recovered"   "$MAIN_OUT" "Error: something bad happened in module xyz"

# --- Failures: a multi-line failure is truncated-then-flattened into exactly
# ONE bullet, with newlines replaced by spaces ---
assert_contains "extract: multi-line failure flattened to one bullet" "$MAIN_OUT" \
    "- Multi-line error occurred: Line 2 of the trace Line 3 with more detail and a second block appended"
multiline_failure_bullets=$(printf '%s' "$MAIN_OUT" | grep -c '^- Multi-line error occurred')
assert "extract: multi-line failure produces exactly one bullet" "1" "$multiline_failure_bullets"

# --- User messages: skip-prefix rules respected ---
assert_not_contains "extract: <command- prefixed message skipped"      "$MAIN_OUT" "caution: destructive op"
assert_not_contains "extract: <local-command- prefixed message skipped" "$MAIN_OUT" "some stdout here"
assert_not_contains "extract: <system-reminder prefixed message skipped" "$MAIN_OUT" "background context injected"
assert_not_contains "extract: 'Base directory for this skill' skipped"  "$MAIN_OUT" "/some/skill/path"
assert_not_contains "extract: 'Another Claude session sent a message:' skipped" "$MAIN_OUT" "hey, status update from teammate session"
assert_not_contains "extract: isMeta:true message skipped structurally" "$MAIN_OUT" "META-INJECTED"
assert_not_contains "extract: isCompactSummary:true message skipped structurally" "$MAIN_OUT" "COMPACT-SUMMARY"

# --- User messages: kept messages present verbatim ---
assert_contains "extract: normal user message 1 recovered" "$MAIN_OUT" "Please fix the login bug in the auth flow."
assert_contains "extract: normal user message 2 recovered" "$MAIN_OUT" "What's the current status of the test suite?"
assert_contains "extract: closing user message recovered"  "$MAIN_OUT" "Thanks, looks good. Ship it."

# --- User messages: a multi-line message stays ONE numbered entry with its
# internal newlines preserved verbatim (not split into several bullets) ---
MULTILINE_MSG_BLOCK=$(printf '%s\n%s\n%s' \
    "Line one of a multi-part update." \
    "Line two continues the thought." \
    "Line three wraps it up.")
assert_contains "extract: multi-line user message newlines preserved" "$MAIN_OUT" "$MULTILINE_MSG_BLOCK"
multiline_msg_numbered_once=$(printf '%s' "$MAIN_OUT" | grep -c '^3\. Line one of a multi-part update\.$')
assert "extract: multi-line user message numbered exactly once" "1" "$multiline_msg_numbered_once"

# --- Truncation: the >1500-char message is truncated with a marker ---
assert_contains "extract: long message truncation marker present" "$MAIN_OUT" "… [truncated]"
assert_not_contains "extract: long message content capped (no 1600-char run)" \
    "$MAIN_OUT" "$(printf 'This is a very long user message. %.0s' {1..50})"

# --- Secret scrubbing: every planted secret is redacted ---
assert_not_contains "extract: AKIA key redacted"      "$MAIN_OUT" "$FAKE_AWS"
assert_not_contains "extract: ghp_ token redacted"    "$MAIN_OUT" "$FAKE_GHP"
assert_not_contains "extract: PEM block redacted"     "$MAIN_OUT" "$FAKE_PEM_B64"
assert_not_contains "extract: PEM header line redacted" "$MAIN_OUT" "$PEM_HEADER"
assert_not_contains "extract: Bearer token value redacted" "$MAIN_OUT" "$FAKE_BEARER"
assert_contains "extract: [REDACTED] marker present"  "$MAIN_OUT" "[REDACTED]"
redacted_count=$(printf '%s' "$MAIN_OUT" | grep -o '\[REDACTED\]' | wc -l | tr -d ' ')
if [ "$redacted_count" -ge 3 ]; then
    PASS=$((PASS + 1)); printf '  ok   %-60s -> %s occurrences\n' "extract: at least 3 distinct redactions applied" "$redacted_count"
else
    FAIL=$((FAIL + 1)); printf '  FAIL %-60s only %s occurrences\n' "extract: at least 3 distinct redactions applied" "$redacted_count"
fi

# --- Provenance section always present ---
assert_contains "extract: provenance section present" "$MAIN_OUT" "## Provenance"
assert_contains "extract: provenance names extractor version" "$MAIN_OUT" "extractor: relay-extract v1"

# --- Cap note: >50 commands shows "(showing last N of M)" and keeps the most recent 50 ---
CAP_TMP="$(mktemp -d)"
python3 - "$CAP_TMP/many.jsonl" <<'PY'
import json, sys
lines = []
for i in range(1, 56):
    lines.append({"type": "assistant", "message": {"content": [
        {"type": "tool_use", "name": "Bash", "input": {"description": f"cmd{i:03d}", "command": f"echo {i}"}}
    ]}})
with open(sys.argv[1], "w") as f:
    for o in lines:
        f.write(json.dumps(o) + "\n")
PY
CAP_OUT="$(bash "$SCRIPTS_DIR/extract-transcript.sh" "$CAP_TMP/many.jsonl")"
assert_contains "extract: cap note shown for >50 commands" "$CAP_OUT" "(showing last 50 of 55)"
assert_not_contains "extract: oldest command (cmd001) dropped by cap" "$CAP_OUT" "cmd001:"
assert_contains "extract: newest command (cmd055) kept by cap" "$CAP_OUT" "cmd055: echo 55"
cap_shown=$(printf '%s' "$CAP_OUT" | grep -c '^- cmd')
assert "extract: cap keeps exactly 50 commands" "50" "$cap_shown"
rm -rf "$CAP_TMP"

# --- Empty-ish fixture: headers still print, with _none_ placeholders ---
EMPTY_OUT="$(bash "$SCRIPTS_DIR/extract-transcript.sh" "$FIXTURES_DIR/empty.jsonl")"
assert_contains "extract: empty fixture prints Files touched header"  "$EMPTY_OUT" "## Files touched"
assert_contains "extract: empty fixture prints Commands run header"   "$EMPTY_OUT" "## Commands run"
assert_contains "extract: empty fixture prints Failures header"       "$EMPTY_OUT" "## Failures"
assert_contains "extract: empty fixture prints User messages header"  "$EMPTY_OUT" "## User messages (verbatim)"
assert_contains "extract: empty fixture prints Provenance header"     "$EMPTY_OUT" "## Provenance"
empty_none_count=$(printf '%s' "$EMPTY_OUT" | grep -c '^_none_$')
assert "extract: empty fixture shows 4 _none_ placeholders" "4" "$empty_none_count"

# --- Malformed fixture: garbage lines are pre-filtered (fromjson?) so the
# extractor degrades gracefully — full output, exit 0, no parse errors.
bash "$SCRIPTS_DIR/extract-transcript.sh" "$FIXTURES_DIR/malformed.jsonl" >/tmp/relay-malformed-out.$$ 2>/tmp/relay-malformed-err.$$
malformed_exit=$?
malformed_out="$(cat /tmp/relay-malformed-out.$$)"
malformed_err="$(cat /tmp/relay-malformed-err.$$)"
rm -f /tmp/relay-malformed-out.$$ /tmp/relay-malformed-err.$$
assert "extract: malformed fixture exits 0" "0" "$malformed_exit"
assert_contains "extract: malformed fixture still prints Provenance" "$malformed_out" "## Provenance"
assert_not_contains "extract: malformed fixture emits no parse error on stderr" "$malformed_err" "parse error"

# =============================================================================
# extract-transcript.sh --before-last-compact tests
# =============================================================================

echo ""
echo "=== extract-transcript.sh --before-last-compact tests ==="

# compact-boundary.jsonl: one user message before an isCompactSummary:true
# line, one after. NOTE: main.jsonl already ends with its own
# isCompactSummary:true line (used elsewhere to test structural exclusion
# from "User messages"), so it is NOT a valid "no boundary" fixture for
# --before-last-compact — that flag would find main.jsonl's line 28 as the
# boundary and silently trim to it. malformed.jsonl carries no
# isCompactSummary line at all, so it's used as the genuine no-boundary case
# instead.
FLAGGED_OUT="$(bash "$SCRIPTS_DIR/extract-transcript.sh" --before-last-compact "$FIXTURES_DIR/compact-boundary.jsonl" 2>/dev/null)"
UNFLAGGED_OUT="$(bash "$SCRIPTS_DIR/extract-transcript.sh" "$FIXTURES_DIR/compact-boundary.jsonl" 2>/dev/null)"

assert_contains "before-last-compact: pre-boundary message present"  "$FLAGGED_OUT" "Pre-boundary message: implement retry logic"
assert_not_contains "before-last-compact: post-boundary message absent" "$FLAGGED_OUT" "Post-boundary message: fix the retry logic bug"
assert_contains "before-last-compact: provenance scope is pre-compaction" "$FLAGGED_OUT" "- scope: pre-compaction"
assert_not_contains "unflagged run on same fixture: no scope line in provenance" "$UNFLAGGED_OUT" "- scope:"

NOBOUNDARY_ERR="$(mktemp)"
NOBOUNDARY_OUT="$(bash "$SCRIPTS_DIR/extract-transcript.sh" --before-last-compact "$FIXTURES_DIR/malformed.jsonl" 2>"$NOBOUNDARY_ERR")"
NOBOUNDARY_UNFLAGGED_OUT="$(bash "$SCRIPTS_DIR/extract-transcript.sh" "$FIXTURES_DIR/malformed.jsonl" 2>/dev/null)"
assert_contains "before-last-compact: no-boundary fixture warns on stderr" "$(cat "$NOBOUNDARY_ERR")" "no compaction boundary"
assert_contains "before-last-compact: no-boundary fixture reports scope: full" "$NOBOUNDARY_OUT" "- scope: full"
noboundary_flagged_msgcount=$(printf '%s' "$NOBOUNDARY_OUT" | grep -c '^[0-9]*\. ')
noboundary_unflagged_msgcount=$(printf '%s' "$NOBOUNDARY_UNFLAGGED_OUT" | grep -c '^[0-9]*\. ')
assert "before-last-compact: no-boundary message count matches unflagged" "$noboundary_unflagged_msgcount" "$noboundary_flagged_msgcount"
rm -f "$NOBOUNDARY_ERR"

# Boundary on line 1: BSD head rejects -n 0, so this exercises the direct-
# truncate branch — everything is post-boundary, all sections empty, exit 0.
BOUNDARY1_TMP=$(mktemp -d)
cat > "$BOUNDARY1_TMP/boundary-first.jsonl" <<'B1EOF'
{"type": "user", "isCompactSummary": true, "message": {"content": "compact continuation as very first line"}}
{"type": "user", "message": {"content": "Post-boundary only message"}}
B1EOF
BOUNDARY1_OUT="$(bash "$SCRIPTS_DIR/extract-transcript.sh" --before-last-compact "$BOUNDARY1_TMP/boundary-first.jsonl" 2>/dev/null)"
boundary1_exit=$?
assert "before-last-compact: boundary on line 1 exits 0" "0" "$boundary1_exit"
assert_not_contains "before-last-compact: boundary on line 1 drops post-boundary message" "$BOUNDARY1_OUT" "Post-boundary only message"
assert_contains "before-last-compact: boundary on line 1 still prints Provenance" "$BOUNDARY1_OUT" "## Provenance"
assert_contains "before-last-compact: boundary on line 1 reports scope: pre-compaction" "$BOUNDARY1_OUT" "- scope: pre-compaction"
rm -rf "$BOUNDARY1_TMP"

# =============================================================================
# precompact-notify.sh tests
# =============================================================================

echo ""
echo "=== precompact-notify.sh tests ==="

PRECOMPACT="$SCRIPTS_DIR/precompact-notify.sh"

# 1. trigger=auto -> valid JSON with systemMessage, exit 0, marker file
# written under sandbox HOME containing the exact transcript_path.
PC_HOME1="$(mktemp -d)"
PC_TRANSCRIPT="/proj/precompact1/transcript.jsonl"
pc_out1=$(HOME="$PC_HOME1" bash "$PRECOMPACT" <<< '{"trigger":"auto","cwd":"/proj/precompact1","transcript_path":"'"$PC_TRANSCRIPT"'"}')
pc_exit1=$?
assert_true "precompact: auto trigger emits valid JSON" "$(printf '%s' "$pc_out1" | jq empty >/dev/null 2>&1; echo $?)"
assert_contains "precompact: auto trigger output has systemMessage key" "$pc_out1" "systemMessage"
assert "precompact: auto trigger never exits 2 (would block compaction)" "0" "$pc_exit1"
pc_slug1=$(printf '%s' "/proj/precompact1" | tr '/.' '-')
pc_marker1=$(find "$PC_HOME1/.claude/handoffs/$pc_slug1" -name 'compacted-*' 2>/dev/null)
assert_true "precompact: auto trigger writes a compacted-* marker" "$([ -n "$pc_marker1" ]; echo $?)"
pc_marker1_content=$(cat "$pc_marker1" 2>/dev/null)
assert "precompact: marker content is the exact transcript_path" "$PC_TRANSCRIPT" "$pc_marker1_content"
rm -rf "$PC_HOME1"

# 2. trigger=manual -> {} exit 0, no marker written
PC_HOME2="$(mktemp -d)"
pc_out2=$(HOME="$PC_HOME2" bash "$PRECOMPACT" <<< '{"trigger":"manual","cwd":"/proj/precompact1","transcript_path":"'"$PC_TRANSCRIPT"'"}')
pc_exit2=$?
assert "precompact: manual trigger yields {}" "{}" "$pc_out2"
assert "precompact: manual trigger exits 0" "0" "$pc_exit2"
pc_slug2=$(printf '%s' "/proj/precompact1" | tr '/.' '-')
pc_marker2=$(find "$PC_HOME2/.claude/handoffs/$pc_slug2" -name 'compacted-*' 2>/dev/null)
assert_true "precompact: manual trigger writes no marker" "$([ -z "$pc_marker2" ]; echo $?)"
rm -rf "$PC_HOME2"

# 3. malformed stdin -> {} exit 0 (fail-open via EXIT trap after jq errors
# under set -e)
PC_HOME3="$(mktemp -d)"
pc_out3=$(HOME="$PC_HOME3" bash "$PRECOMPACT" 2>/dev/null <<< 'not json at all {{{')
pc_exit3=$?
assert "precompact: malformed stdin yields {}" "{}" "$pc_out3"
assert "precompact: malformed stdin exits 0" "0" "$pc_exit3"
rm -rf "$PC_HOME3"

# 4. missing cwd (trigger=auto but no cwd key) -> {} exit 0
PC_HOME4="$(mktemp -d)"
pc_out4=$(HOME="$PC_HOME4" bash "$PRECOMPACT" <<< '{"trigger":"auto","transcript_path":"'"$PC_TRANSCRIPT"'"}')
pc_exit4=$?
assert "precompact: missing cwd yields {}" "{}" "$pc_out4"
assert "precompact: missing cwd exits 0" "0" "$pc_exit4"
rm -rf "$PC_HOME4"

# =============================================================================
# resolve-session.sh tests
# =============================================================================

echo ""
echo "=== resolve-session.sh tests ==="

# Test: env var resolves to the exact transcript path
RS_TMP="$(mktemp -d)"
RS_HOME="$RS_TMP/home"
mkdir -p "$RS_HOME"
RS_CWD="$RS_TMP/proj"
mkdir -p "$RS_CWD"
(
    cd "$RS_CWD" || exit 1
    slug=$(printf '%s' "$PWD" | tr '/.' '-')
    mkdir -p "$RS_HOME/.claude/projects/$slug"
    printf '{}\n' > "$RS_HOME/.claude/projects/$slug/envsession.jsonl"
    printf '{}\n' > "$RS_HOME/.claude/projects/$slug/other.jsonl"
    HOME="$RS_HOME" CLAUDE_CODE_SESSION_ID=envsession bash "$SCRIPTS_DIR/resolve-session.sh"
) > "$RS_TMP/out.txt" 2>/dev/null
rs_env_out="$(cat "$RS_TMP/out.txt")"
case "$rs_env_out" in
    */envsession.jsonl) rs_env_ok=0 ;;
    *) rs_env_ok=1 ;;
esac
assert_true "resolve: \$CLAUDE_CODE_SESSION_ID resolves exact transcript" "$rs_env_ok"

# Test: CLAUDE_SESSION_ID (secondary env var) also resolves exact transcript
(
    cd "$RS_CWD" || exit 1
    HOME="$RS_HOME" CLAUDE_SESSION_ID=envsession bash "$SCRIPTS_DIR/resolve-session.sh"
) > "$RS_TMP/out2.txt" 2>/dev/null
rs_env2_out="$(cat "$RS_TMP/out2.txt")"
case "$rs_env2_out" in
    */envsession.jsonl) rs_env2_ok=0 ;;
    *) rs_env2_ok=1 ;;
esac
assert_true "resolve: \$CLAUDE_SESSION_ID resolves exact transcript" "$rs_env2_ok"

# Test: unset env vars fall back to newest-mtime transcript, with a stderr warning
(
    cd "$RS_CWD" || exit 1
    slug=$(printf '%s' "$PWD" | tr '/.' '-')
    printf '{}\n' > "$RS_HOME/.claude/projects/$slug/newest.jsonl"
    # Explicit future mtime instead of sleeping past a 1s resolution boundary
    # (same touch -t pattern as the stale-marker case below).
    touch -t 203701020304 "$RS_HOME/.claude/projects/$slug/newest.jsonl"
    HOME="$RS_HOME" env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_SESSION_ID bash "$SCRIPTS_DIR/resolve-session.sh"
) > "$RS_TMP/out3.txt" 2>"$RS_TMP/err3.txt"
rs_mtime_out="$(cat "$RS_TMP/out3.txt")"
rs_mtime_err="$(cat "$RS_TMP/err3.txt")"
case "$rs_mtime_out" in
    */newest.jsonl) rs_mtime_ok=0 ;;
    *) rs_mtime_ok=1 ;;
esac
assert_true "resolve: no env id -> newest-mtime file resolved" "$rs_mtime_ok"
assert_contains "resolve: newest-mtime fallback warns on stderr" "$rs_mtime_err" "guessing newest-mtime transcript"

# Test: project dir exists but is empty -> exit 1
RS_EMPTY_CWD="$RS_TMP/emptyproj"
mkdir -p "$RS_EMPTY_CWD"
(
    cd "$RS_EMPTY_CWD" || exit 1
    slug=$(printf '%s' "$PWD" | tr '/.' '-')
    mkdir -p "$RS_HOME/.claude/projects/$slug"
    HOME="$RS_HOME" env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_SESSION_ID bash "$SCRIPTS_DIR/resolve-session.sh"
)
assert "resolve: empty project dir exits 1" "1" "$?"

# Test: no project dir at all -> exit 1
RS_NODIR_CWD="$RS_TMP/nodirproj"
mkdir -p "$RS_NODIR_CWD"
(
    cd "$RS_NODIR_CWD" || exit 1
    HOME="$RS_HOME" env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_SESSION_ID bash "$SCRIPTS_DIR/resolve-session.sh"
)
assert "resolve: missing project dir exits 1" "1" "$?"

# Test: env session id set but the file it points to doesn't exist -> falls
# back to mtime guess rather than failing
(
    cd "$RS_CWD" || exit 1
    HOME="$RS_HOME" CLAUDE_CODE_SESSION_ID=does-not-exist bash "$SCRIPTS_DIR/resolve-session.sh"
) > "$RS_TMP/out4.txt" 2>"$RS_TMP/err4.txt"
rs_stale_out="$(cat "$RS_TMP/out4.txt")"
rs_stale_err="$(cat "$RS_TMP/err4.txt")"
case "$rs_stale_out" in
    */newest.jsonl) rs_stale_ok=0 ;;
    *) rs_stale_ok=1 ;;
esac
assert_true "resolve: dangling session id falls back to mtime guess" "$rs_stale_ok"
assert_contains "resolve: dangling session id warns on stderr" "$rs_stale_err" "falling back to mtime guess"

rm -rf "$RS_TMP"

# =============================================================================
# session-start-pickup.sh tests
# =============================================================================

echo ""
echo "=== session-start-pickup.sh tests ==="

PICKUP="$SCRIPTS_DIR/session-start-pickup.sh"

run_pickup() {
    # run_pickup <HOME> <json-stdin>
    HOME="$1" bash "$PICKUP" <<< "$2"
}

# 1. source=resume is a no-op ({}), regardless of any pending marker
SP_TMP="$(mktemp -d)"
SP_HOME1="$SP_TMP/home1"
mkdir -p "$SP_HOME1"
CWD1="/proj/case1"
slug1=$(printf '%s' "$CWD1" | tr '/.' '-')
mkdir -p "$SP_HOME1/.claude/handoffs/$slug1"
echo "$SP_TMP/doc1.md" > "$SP_HOME1/.claude/handoffs/$slug1/pending"
echo "doc contents" > "$SP_TMP/doc1.md"
out1="$(run_pickup "$SP_HOME1" "{\"source\":\"resume\",\"cwd\":\"$CWD1\"}")"
assert "pickup: source=resume is a no-op" "{}" "$out1"
assert_true "pickup: source=resume valid JSON" "$(printf '%s' "$out1" | jq empty >/dev/null 2>&1; echo $?)"
# marker must be untouched by a resume no-op
assert_true "pickup: source=resume leaves pending marker in place" "$([ -f "$SP_HOME1/.claude/handoffs/$slug1/pending" ]; echo $?)"

# 2. source=startup + fresh marker -> additionalContext contains doc content,
#    marker renamed consumed-*
SP_HOME2="$SP_TMP/home2"
mkdir -p "$SP_HOME2"
CWD2="/proj/case2"
slug2=$(printf '%s' "$CWD2" | tr '/.' '-')
mkdir -p "$SP_HOME2/.claude/handoffs/$slug2"
doc2="$SP_TMP/doc2.md"
echo "# Fresh handoff doc for case 2" > "$doc2"
echo "$doc2" > "$SP_HOME2/.claude/handoffs/$slug2/pending"
out2="$(run_pickup "$SP_HOME2" "{\"source\":\"startup\",\"cwd\":\"$CWD2\"}")"
assert_true "pickup: fresh marker emits valid JSON" "$(printf '%s' "$out2" | jq empty >/dev/null 2>&1; echo $?)"
ctx2=$(printf '%s' "$out2" | jq -r '.hookSpecificOutput.additionalContext // empty')
assert_contains "pickup: additionalContext embeds doc text" "$ctx2" "Fresh handoff doc for case 2"
consumed2=$(find "$SP_HOME2/.claude/handoffs/$slug2" -name 'consumed-*' | wc -l | tr -d ' ')
assert "pickup: fresh marker renamed to consumed-*" "1" "$consumed2"
assert_true "pickup: original 'pending' marker no longer exists" "$([ ! -f "$SP_HOME2/.claude/handoffs/$slug2/pending" ]; echo $?)"

# 2b. same source=startup (clear also triggers pickup) with a doc containing
# embedded newlines/markdown — additionalContext must still be valid JSON
# with the doc text embedded (regression guard for JSON-escaping of the doc)
SP_HOME2B="$SP_TMP/home2b"
mkdir -p "$SP_HOME2B"
CWD2B="/proj/case2b"
slug2b=$(printf '%s' "$CWD2B" | tr '/.' '-')
mkdir -p "$SP_HOME2B/.claude/handoffs/$slug2b"
doc2b="$SP_TMP/doc2b.md"
printf '# Multi-line handoff\n\n- did X\n- did Y\n\nNext: do Z\n' > "$doc2b"
echo "$doc2b" > "$SP_HOME2B/.claude/handoffs/$slug2b/pending"
out2b="$(run_pickup "$SP_HOME2B" "{\"source\":\"clear\",\"cwd\":\"$CWD2B\"}")"
assert_true "pickup: source=clear + multi-line doc emits valid JSON" "$(printf '%s' "$out2b" | jq empty >/dev/null 2>&1; echo $?)"
ctx2b=$(printf '%s' "$out2b" | jq -r '.hookSpecificOutput.additionalContext // empty')
assert_contains "pickup: multi-line doc content embedded" "$ctx2b" "Next: do Z"

# 3. stale marker (>30 min old) -> expired-*, {}
SP_HOME3="$SP_TMP/home3"
mkdir -p "$SP_HOME3"
CWD3="/proj/case3"
slug3=$(printf '%s' "$CWD3" | tr '/.' '-')
mkdir -p "$SP_HOME3/.claude/handoffs/$slug3"
doc3="$SP_TMP/doc3.md"
echo "stale doc" > "$doc3"
marker3="$SP_HOME3/.claude/handoffs/$slug3/pending"
echo "$doc3" > "$marker3"
touch -t "$(date -v-40M +%Y%m%d%H%M 2>/dev/null || date -d '-40 minutes' +%Y%m%d%H%M)" "$marker3"
out3="$(run_pickup "$SP_HOME3" "{\"source\":\"startup\",\"cwd\":\"$CWD3\"}")"
assert "pickup: stale marker (>30min) yields {}" "{}" "$out3"
expired3=$(find "$SP_HOME3/.claude/handoffs/$slug3" -name 'expired-*' | wc -l | tr -d ' ')
assert "pickup: stale marker renamed to expired-*" "1" "$expired3"

# 4. dangling doc path (doc file missing) -> broken-*, {}
SP_HOME4="$SP_TMP/home4"
mkdir -p "$SP_HOME4"
CWD4="/proj/case4"
slug4=$(printf '%s' "$CWD4" | tr '/.' '-')
mkdir -p "$SP_HOME4/.claude/handoffs/$slug4"
echo "$SP_TMP/does-not-exist.md" > "$SP_HOME4/.claude/handoffs/$slug4/pending"
out4="$(run_pickup "$SP_HOME4" "{\"source\":\"startup\",\"cwd\":\"$CWD4\"}")"
assert "pickup: dangling doc path yields {}" "{}" "$out4"
broken4=$(find "$SP_HOME4/.claude/handoffs/$slug4" -name 'broken-*' | wc -l | tr -d ' ')
assert "pickup: dangling doc marker renamed to broken-*" "1" "$broken4"

# 5. no marker at all -> {}
SP_HOME5="$SP_TMP/home5"
mkdir -p "$SP_HOME5"
out5="$(run_pickup "$SP_HOME5" '{"source":"startup","cwd":"/proj/case5"}')"
assert "pickup: no pending marker yields {}" "{}" "$out5"

# 6. malformed stdin (not JSON at all) -> {} AND exit 0 (the EXIT trap forces
# status 0 so fail-open covers the exit code, not just the payload).
SP_HOME6="$SP_TMP/home6"
mkdir -p "$SP_HOME6"
out6=$(HOME="$SP_HOME6" bash "$PICKUP" 2>/dev/null <<< "not json at all {{{")
malformed_pickup_exit=$?
assert "pickup: malformed stdin still yields {} payload" "{}" "$out6"
assert "pickup: malformed stdin exits 0" "0" "$malformed_pickup_exit"

# 6b. empty stdin -> {} and exit 0 (this path IS a clean `exit 0`, unlike 6)
SP_HOME6B="$SP_TMP/home6b"
mkdir -p "$SP_HOME6B"
out6b=$(HOME="$SP_HOME6B" bash "$PICKUP" < /dev/null)
empty_stdin_exit=$?
assert "pickup: empty stdin yields {}" "{}" "$out6b"
assert "pickup: empty stdin exits 0" "0" "$empty_stdin_exit"

# 7. jq missing from PATH -> {} and exit 0 (explicit `command -v jq || exit 0`)
NOJQ_BIN="$(mktemp -d)"
SP_HOME7="$SP_TMP/home7"
mkdir -p "$SP_HOME7"
out7=$(HOME="$SP_HOME7" PATH="$NOJQ_BIN:/usr/bin:/bin" bash "$PICKUP" <<< '{"source":"startup","cwd":"/proj/case7"}')
nojq_exit=$?
assert "pickup: jq missing from PATH yields {}" "{}" "$out7"
assert "pickup: jq missing from PATH exits 0" "0" "$nojq_exit"
rm -rf "$NOJQ_BIN"

# 8. source values other than startup/clear/resume (e.g. "compact") -> {}
SP_HOME8="$SP_TMP/home8"
mkdir -p "$SP_HOME8"
CWD8="/proj/case8"
slug8=$(printf '%s' "$CWD8" | tr '/.' '-')
mkdir -p "$SP_HOME8/.claude/handoffs/$slug8"
echo "$SP_TMP/doc8.md" > "$SP_HOME8/.claude/handoffs/$slug8/pending"
echo "doc8" > "$SP_TMP/doc8.md"
out8="$(run_pickup "$SP_HOME8" "{\"source\":\"compact\",\"cwd\":\"$CWD8\"}")"
assert "pickup: unrecognized source (e.g. compact) yields {}" "{}" "$out8"
assert_true "pickup: unrecognized source leaves marker untouched" "$([ -f "$SP_HOME8/.claude/handoffs/$slug8/pending" ]; echo $?)"

# 9. missing cwd key in stdin -> {}
SP_HOME9="$SP_TMP/home9"
mkdir -p "$SP_HOME9"
out9="$(run_pickup "$SP_HOME9" '{"source":"startup"}')"
assert "pickup: missing cwd key yields {}" "{}" "$out9"

# =============================================================================
# session-start-pickup.sh: retention sweep tests
# =============================================================================
# Sweep only runs once marker_dir is derived (source=startup/clear + cwd
# present), same portable backdate pattern as the stale-marker case above
# (test 3), just in days instead of minutes.
backdate_days() {
    touch -t "$(date -v-"${1}"d +%Y%m%d%H%M 2>/dev/null || date -d "-${1} days" +%Y%m%d%H%M)" "$2"
}

# 10. old consumed-* marker (20 days, past the 14-day default) is swept
SP_HOME10="$SP_TMP/home10"
mkdir -p "$SP_HOME10"
CWD10="/proj/case10"
slug10=$(printf '%s' "$CWD10" | tr '/.' '-')
mkdir -p "$SP_HOME10/.claude/handoffs/$slug10"
old_consumed10="$SP_HOME10/.claude/handoffs/$slug10/consumed-1111"
: > "$old_consumed10"
backdate_days 20 "$old_consumed10"
run_pickup "$SP_HOME10" "{\"source\":\"startup\",\"cwd\":\"$CWD10\"}" >/dev/null
assert_true "sweep: old consumed-* marker (20d) removed" "$([ ! -f "$old_consumed10" ]; echo $?)"

# 11. old timestamped doc (*.md, 20 days) is swept
SP_HOME11="$SP_TMP/home11"
mkdir -p "$SP_HOME11"
CWD11="/proj/case11"
slug11=$(printf '%s' "$CWD11" | tr '/.' '-')
mkdir -p "$SP_HOME11/.claude/handoffs/$slug11"
old_doc11="$SP_HOME11/.claude/handoffs/$slug11/20250101-000000.md"
echo "old handoff doc" > "$old_doc11"
backdate_days 20 "$old_doc11"
run_pickup "$SP_HOME11" "{\"source\":\"startup\",\"cwd\":\"$CWD11\"}" >/dev/null
assert_true "sweep: old timestamped doc (20d) removed" "$([ ! -f "$old_doc11" ]; echo $?)"

# 12. fresh marker + fresh doc (untouched mtime, well under 14 days) are kept
SP_HOME12="$SP_TMP/home12"
mkdir -p "$SP_HOME12"
CWD12="/proj/case12"
slug12=$(printf '%s' "$CWD12" | tr '/.' '-')
mkdir -p "$SP_HOME12/.claude/handoffs/$slug12"
fresh_consumed12="$SP_HOME12/.claude/handoffs/$slug12/consumed-2222"
fresh_doc12="$SP_HOME12/.claude/handoffs/$slug12/20260101-000000.md"
: > "$fresh_consumed12"
echo "fresh handoff doc" > "$fresh_doc12"
run_pickup "$SP_HOME12" "{\"source\":\"startup\",\"cwd\":\"$CWD12\"}" >/dev/null
assert_true "sweep: fresh consumed-* marker kept" "$([ -f "$fresh_consumed12" ]; echo $?)"
assert_true "sweep: fresh doc kept" "$([ -f "$fresh_doc12" ]; echo $?)"

# 13. `pending` is never swept, even when old — and the sweep runs in the same
# pass that TTL logic already handles it. Note: a raw old `pending` file can't
# survive a run untouched to be independently checked post-hoc, since the
# same script invocation's own claim logic (marker_dir derives 1:1 from cwd)
# always claims whatever is at that exact path first; by the time the EXIT
# trap's sweep runs, an old `pending` has already been renamed to
# `expired-<epoch>` by the existing TTL check. This test instead verifies the
# composite contract: the old `pending` is converted (not raw-deleted) via
# TTL logic, the resulting expired-* marker is brand new so the *same* sweep
# pass correctly leaves it alone, and an unrelated old consumed-* marker
# sitting in the same directory is still correctly swept in that pass.
SP_HOME13="$SP_TMP/home13"
mkdir -p "$SP_HOME13"
CWD13="/proj/case13"
slug13=$(printf '%s' "$CWD13" | tr '/.' '-')
dir13="$SP_HOME13/.claude/handoffs/$slug13"
mkdir -p "$dir13"
doc13="$SP_TMP/doc13.md"
echo "doc for case 13" > "$doc13"
echo "$doc13" > "$dir13/pending"
backdate_days 20 "$dir13/pending"
old_consumed13="$dir13/consumed-3333"
: > "$old_consumed13"
backdate_days 20 "$old_consumed13"
out13="$(run_pickup "$SP_HOME13" "{\"source\":\"startup\",\"cwd\":\"$CWD13\"}")"
assert "sweep: old pending (20d) is stale -> {} (TTL path, not sweep)" "{}" "$out13"
assert_true "sweep: no file literally named 'pending' remains" "$([ ! -f "$dir13/pending" ]; echo $?)"
expired13=$(find "$dir13" -name 'expired-*' | wc -l | tr -d ' ')
assert "sweep: old pending renamed to expired-* (TTL logic, not deleted)" "1" "$expired13"
assert_true "sweep: brand-new expired-* marker not swept in same pass" "$([ -n "$(find "$dir13" -name 'expired-*')" ]; echo $?)"
assert_true "sweep: unrelated old consumed-* still swept in same pass" "$([ ! -f "$old_consumed13" ]; echo $?)"

# 14. RELAY_RETENTION_DAYS=0 disables the sweep entirely — old files of both
# kinds survive.
SP_HOME14="$SP_TMP/home14"
mkdir -p "$SP_HOME14"
CWD14="/proj/case14"
slug14=$(printf '%s' "$CWD14" | tr '/.' '-')
mkdir -p "$SP_HOME14/.claude/handoffs/$slug14"
old_consumed14="$SP_HOME14/.claude/handoffs/$slug14/consumed-4444"
old_doc14="$SP_HOME14/.claude/handoffs/$slug14/20250101-000000.md"
: > "$old_consumed14"
echo "old doc" > "$old_doc14"
backdate_days 20 "$old_consumed14"
backdate_days 20 "$old_doc14"
HOME="$SP_HOME14" RELAY_RETENTION_DAYS=0 bash "$PICKUP" <<< "{\"source\":\"startup\",\"cwd\":\"$CWD14\"}" >/dev/null
assert_true "sweep: RELAY_RETENTION_DAYS=0 keeps old consumed-* marker" "$([ -f "$old_consumed14" ]; echo $?)"
assert_true "sweep: RELAY_RETENTION_DAYS=0 keeps old doc" "$([ -f "$old_doc14" ]; echo $?)"

# 15. sweep failure (read-only handoff dir, so rm can't unlink) never changes
# pickup's own output or exit code — the fail-open contract covers the sweep
# too, not just jq/JSON errors.
SP_HOME15="$SP_TMP/home15"
mkdir -p "$SP_HOME15"
CWD15="/proj/case15"
slug15=$(printf '%s' "$CWD15" | tr '/.' '-')
dir15="$SP_HOME15/.claude/handoffs/$slug15"
mkdir -p "$dir15"
old_consumed15="$dir15/consumed-5555"
: > "$old_consumed15"
backdate_days 20 "$old_consumed15"
chmod 555 "$dir15"
out15=$(run_pickup "$SP_HOME15" "{\"source\":\"startup\",\"cwd\":\"$CWD15\"}")
pickup15_exit=$?
assert "sweep: read-only handoff dir still yields {} (no marker present)" "{}" "$out15"
assert "sweep: read-only handoff dir still exits 0" "0" "$pickup15_exit"
chmod 755 "$dir15"

rm -rf "$SP_TMP"

# =============================================================================
# haiku-narrative.sh tests
# =============================================================================

echo ""
echo "=== haiku-narrative.sh tests ==="

HN_SCRIPT="$SCRIPTS_DIR/haiku-narrative.sh"
HN_FIXTURE="$FIXTURES_DIR/haiku-narrative-dialogue.jsonl"

# 1. claude absent from PATH -> degrade (exit 3), stderr says "degraded",
# stdout empty. jq must still resolve, so build a sandbox bin with only jq
# symlinked rather than stripping a directory from the real PATH (jq and
# claude live in the same homebrew bin dir on this machine, so removing one
# directory would remove both).
HN_NOCLAUDE_BIN="$(mktemp -d)"
ln -s "$(command -v jq)" "$HN_NOCLAUDE_BIN/jq"
HN_BASH_BIN="$(command -v bash)"
hn_out1=$(PATH="$HN_NOCLAUDE_BIN" "$HN_BASH_BIN" "$HN_SCRIPT" "$FIXTURES_DIR/empty.jsonl" 2>"$HN_NOCLAUDE_BIN/err")
hn_exit1=$?
hn_err1="$(cat "$HN_NOCLAUDE_BIN/err")"
assert "haiku-narrative: claude absent exits 3 (degraded)" "3" "$hn_exit1"
assert_contains "haiku-narrative: claude absent stderr says degraded" "$hn_err1" "degraded"
assert "haiku-narrative: claude absent produces no stdout" "" "$hn_out1"
rm -rf "$HN_NOCLAUDE_BIN"

# 2. usage errors exit 1, not 3 (degrade is reserved for claude-specific
# failures, not for a missing/nonexistent transcript arg).
bash "$HN_SCRIPT" >/dev/null 2>/dev/null
assert "haiku-narrative: no transcript arg exits 1 (usage)" "1" "$?"
bash "$HN_SCRIPT" "$FIXTURES_DIR/does-not-exist.jsonl" >/dev/null 2>/dev/null
assert "haiku-narrative: nonexistent transcript path exits 1" "1" "$?"

# 2b. RELAY_NARRATIVE=off kill switch short-circuits before the claude PATH
# check (case-insensitive), degrading with a reason that names the env var so
# a handoff reader knows narrative was suppressed deliberately, not that
# claude failed. Checked with the real (still no-`claude`-required) PATH.
hn_off_out=$(RELAY_NARRATIVE=off bash "$HN_SCRIPT" "$FIXTURES_DIR/empty.jsonl" 2>/tmp/hn-off-err.$$)
hn_off_exit=$?
assert "haiku-narrative: RELAY_NARRATIVE=off exits 3 (degraded)" "3" "$hn_off_exit"
assert "haiku-narrative: RELAY_NARRATIVE=off emits no stdout" "" "$hn_off_out"
assert_contains "haiku-narrative: RELAY_NARRATIVE=off stderr names the reason" "$(cat /tmp/hn-off-err.$$)" "disabled by RELAY_NARRATIVE=off"
rm -f /tmp/hn-off-err.$$

# 2c. RELAY_NARRATIVE=OFF (mixed case) also trips the switch.
RELAY_NARRATIVE=OFF bash "$HN_SCRIPT" "$FIXTURES_DIR/empty.jsonl" >/dev/null 2>/dev/null
assert "haiku-narrative: RELAY_NARRATIVE=OFF (uppercase) exits 3" "3" "$?"

# Fake `claude` shim: captures the piped dialogue to $FAKE_CLAUDE_CAPTURE and
# emits canned output controlled by $FAKE_CLAUDE_MODE. Built inline into a
# tmpdir (never touches the real claude binary), mirroring how commitcraft's
# tests stub `gh` with a PATH-shadowing executable.
HN_BIN="$(mktemp -d)"
cat > "$HN_BIN/claude" <<'SHIM'
#!/usr/bin/env bash
if [ -n "${FAKE_CLAUDE_CAPTURE:-}" ]; then
    cat > "$FAKE_CLAUDE_CAPTURE"
else
    cat > /dev/null
fi
case "${FAKE_CLAUDE_MODE:-ok}" in
    slow)
        sleep 5
        echo "## Decisions" ;;
    ok)
        cat <<'EOF'
## Decisions
- Chose approach A because it is simpler

## Dead ends
- Tried approach B, abandoned due to complexity

## Constraints
- Must keep the API backward compatible
EOF
        ;;
    empty)
        : ;;
    fail)
        exit 1 ;;
    secret)
        printf '## Decisions\n- Rotated leaked key %s\n\n## Dead ends\n_none_\n\n## Constraints\n_none_\n' "${FAKE_SECRET_KEY:-}" ;;
esac
SHIM
chmod +x "$HN_BIN/claude"
HN_PATH="$HN_BIN:$PATH"

# 3. valid three-heading output from claude -> exit 0, all three headings
# present, and the dialogue actually piped to claude matches the prefilter:
# USER:/ASSISTANT: turns present, tool_result/isMeta/isCompactSummary content
# absent (see haiku-narrative-dialogue.jsonl fixture).
HN_CAPTURE="$(mktemp)"
hn_out3=$(PATH="$HN_PATH" FAKE_CLAUDE_MODE=ok FAKE_CLAUDE_CAPTURE="$HN_CAPTURE" bash "$HN_SCRIPT" "$HN_FIXTURE" 2>/dev/null)
hn_exit3=$?
assert "haiku-narrative: valid output exits 0" "0" "$hn_exit3"
assert_contains "haiku-narrative: valid output has Decisions heading" "$hn_out3" "## Decisions"
assert_contains "haiku-narrative: valid output has Dead ends heading" "$hn_out3" "## Dead ends"
assert_contains "haiku-narrative: valid output has Constraints heading" "$hn_out3" "## Constraints"
hn_dialogue="$(cat "$HN_CAPTURE")"
assert_contains "haiku-narrative: dialogue includes USER: turn" "$hn_dialogue" "USER: Please fix the login bug in the auth flow."
assert_contains "haiku-narrative: dialogue includes ASSISTANT: turn" "$hn_dialogue" "ASSISTANT: I decided to use approach A because it is simpler."
assert_not_contains "haiku-narrative: dialogue excludes tool_result content" "$hn_dialogue" "tool result payload should not appear"
assert_not_contains "haiku-narrative: dialogue excludes isMeta content" "$hn_dialogue" "META text should not appear"
assert_not_contains "haiku-narrative: dialogue excludes isCompactSummary content" "$hn_dialogue" "COMPACT text should not appear"
rm -f "$HN_CAPTURE"

# 4. claude emits empty output -> degrade (exit 3)
PATH="$HN_PATH" FAKE_CLAUDE_MODE=empty bash "$HN_SCRIPT" "$HN_FIXTURE" >/dev/null 2>/dev/null
assert "haiku-narrative: empty claude output degrades (exit 3)" "3" "$?"

# 5. claude exits nonzero -> degrade (exit 3)
PATH="$HN_PATH" FAKE_CLAUDE_MODE=fail bash "$HN_SCRIPT" "$HN_FIXTURE" >/dev/null 2>/dev/null
assert "haiku-narrative: claude nonzero exit degrades (exit 3)" "3" "$?"

# 6. secret scrub: a planted AKIA-style key in claude's own output must be
# redacted before reaching stdout (assembled from fragments, never a literal
# secret-shaped string in this file, per repo convention).
FAKE_SECRET_KEY="AKIA""QWERTYUIOPASDFGH"
hn_out6=$(PATH="$HN_PATH" FAKE_CLAUDE_MODE=secret FAKE_SECRET_KEY="$FAKE_SECRET_KEY" bash "$HN_SCRIPT" "$HN_FIXTURE" 2>/dev/null)
assert_contains "haiku-narrative: secret scrub marker present" "$hn_out6" "[REDACTED]"
assert_not_contains "haiku-narrative: planted secret absent from output" "$hn_out6" "$FAKE_SECRET_KEY"

# Timeout overrun: HAIKU_NARRATIVE_TIMEOUT=1 with a shim that sleeps 5s —
# the poll loop must kill the call and degrade (exit 3), not hang or emit
# partial output.
hn_timeout_out=$(PATH="$HN_PATH" FAKE_CLAUDE_MODE=slow HAIKU_NARRATIVE_TIMEOUT=1 \
    bash "$HN_SCRIPT" "$FIXTURES_DIR/haiku-narrative-dialogue.jsonl" 2>/tmp/hn-timeout-err.$$)
hn_timeout_exit=$?
assert "haiku-narrative: timed-out call exits 3 (degraded)" "3" "$hn_timeout_exit"
assert "haiku-narrative: timed-out call emits no stdout" "" "$hn_timeout_out"
assert_contains "haiku-narrative: timeout degrade noted on stderr" "$(cat /tmp/hn-timeout-err.$$)" "degraded"
rm -f /tmp/hn-timeout-err.$$

rm -rf "$HN_BIN"

# =============================================================================
# Summary
# =============================================================================

END_TIME=$(date +%s)
RUNTIME=$((END_TIME - START_TIME))

echo ""
echo "  $PASS passed, $FAIL failed (${RUNTIME}s)"
[ "$FAIL" -eq 0 ]
