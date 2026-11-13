#!/usr/bin/env bash
# SessionStart(source=compact) hook: after an AUTO compaction, re-inject the
# messages the user wrote in the segment that compaction just summarized; the
# summary is the step that drops early requirements. The segment ends at the
# cut precompact-notify.sh recorded, since the new compact_boundary line is
# not yet in the transcript when this runs. Never touches `pending`, which
# belongs to the /clear handoff flow. Fails open: prints `{}` unless the
# injection is emitted.
set -euo pipefail

emitted=0
segment=""
trap '[ "$emitted" -eq 1 ] || echo "{}"; [ -z "$segment" ] || rm -f "$segment"; exit 0' EXIT

[ -z "${RELAY_NESTED:-}" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

input=$(cat)
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
session_id=$(printf '%s' "$input" | jq -r '.session_id // empty')
[ -f "$transcript" ] && [ -n "$cwd" ] && [ -n "$session_id" ] || exit 0

recovery_dir="$HOME/.claude/handoffs/.recovery"
cut_file="$recovery_dir/${session_id}.cut"
[ -f "$cut_file" ] || exit 0
read -r trigger cut < "$cut_file" || true
rm -f "$cut_file"
[ "$trigger" = auto ] || exit 0
case "${cut:-}" in ''|*[!0-9]*) exit 0 ;; esac
[ "$cut" -ge 1 ] || exit 0

here=$(dirname "$0")
marker_dir=$(bash "$here/handoff-dir.sh" "$cwd")
mkdir -p "$marker_dir"
printf '%s\n' "$transcript" > "${marker_dir}/compacted-$(date +%s)"

# The segment is (prev, cut]: prev is the boundary of the compaction before
# this one, 0 on a session's first compaction.
prev=$(head -n "$cut" "$transcript" | grep -n '"compact_boundary"' | tail -n 1 | cut -d: -f1 || true)
prev=${prev:-0}
# The previous compaction kept its newest messages verbatim
# (compactMetadata.preservedSegment), so this compaction is the first to
# summarize them; start the segment at that preserved head.
if [ "$prev" -gt 0 ]; then
  head_uuid=$(sed -n "${prev}p" "$transcript" | jq -r '.compactMetadata.preservedSegment.headUuid // empty' 2>/dev/null || true)
  if [ -n "$head_uuid" ]; then
    head_line=$(head -n "$prev" "$transcript" | grep -n "\"uuid\":\"${head_uuid}\"" | head -n 1 | cut -d: -f1 || true)
    [ -n "$head_line" ] && prev=$((head_line - 1))
  fi
fi
[ "$prev" -lt "$cut" ] || exit 0
segment=$(mktemp)
sed -n "$((prev + 1)),${cut}p" "$transcript" > "$segment"

mkdir -p "$recovery_dir"
find "$recovery_dir" -maxdepth 1 -type f -mtime +1 -exec rm -f {} + 2>/dev/null || true

# Auto-compaction fired because the context was full; a large injection
# would push it straight back toward the threshold.
msgs=$(bash "$here/extract-transcript.sh" --user-messages --cap 6000 "$segment" 2>/dev/null)

# The Haiku narrative (decisions, dead ends) takes 20s-1.5min, too slow for
# this hook. Build it detached (perl setsid, so it outlives the hook) from its
# own copy of the segment, which recovery-narrative.sh deletes;
# prompt-recovery.sh injects it at the next prompt once it is ready.
seg_copy="$recovery_dir/${session_id}.seg.jsonl"
case "${RELAY_NARRATIVE:-}" in [Oo][Ff][Ff]) narrative=off ;; *) narrative=on ;; esac
if [ "$narrative" = on ] && command -v perl >/dev/null 2>&1 && cp "$segment" "$seg_copy" 2>/dev/null; then
  perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV' \
    bash "$here/recovery-narrative.sh" "$seg_copy" "$recovery_dir/${session_id}.md" \
    </dev/null >/dev/null 2>&1 &
fi

[ -n "$(printf '%s' "$msgs" | tr -d '[:space:]')" ] || exit 0

prefix="Auto-compaction just summarized part of this conversation. Below are the user's messages from the part of the session that was just summarized, verbatim from the transcript. Treat the requirements in them as still in force unless a later message changed them."
[ "$narrative" = off ] || prefix="$prefix Constraints, decisions, and dead ends from the same part follow at a later prompt."
prefix="$prefix

"
jq -n --arg ctx "${prefix}${msgs}" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
emitted=1
