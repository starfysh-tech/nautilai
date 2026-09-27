#!/usr/bin/env bash
# UserPromptSubmit hook: inject, once, the narrative recovery-narrative.sh
# built after an auto-compaction of this session. Runs on every prompt; the
# no-op path is one jq call and one file test. Always exits 0.
trap 'exit 0' EXIT

[ -z "${RELAY_NESTED:-}" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

session_id=$(jq -r '.session_id // empty' 2>/dev/null)
file="$HOME/.claude/handoffs/.recovery/${session_id}.md"
[ -n "$session_id" ] && [ -f "$file" ] || exit 0

narrative=$(cat "$file")
rm -f "$file"
jq -n --arg ctx "Relay rebuilt these decisions, dead ends, and constraints from the transcript as it was before the last auto-compaction. Haiku wrote them and no agent has verified them: check a claim against the repo before relying on it.

${narrative}" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $ctx}}'
