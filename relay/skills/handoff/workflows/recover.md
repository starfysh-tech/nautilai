# Recover mode (`/handoff recover`)

Use this after an auto-compact — the `PreCompact` hook posts a systemMessage
suggesting it — or whenever the session feels like it lost earlier context,
even without that prompt.

1. Resolve the transcript: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-session.sh`
2. Extract the pre-compaction region:
   `bash ${CLAUDE_PLUGIN_ROOT}/scripts/extract-transcript.sh --before-last-compact <transcript>`
3. Extract the narrative pack: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/haiku-narrative.sh <transcript>`.
   It has no `--before-last-compact` equivalent — it always reads the full
   transcript — so use its Decisions/Dead ends output to fill those sections
   of the recovery delta below, judging by content which items predate the
   compaction boundary. Same degrade rule as the main flow: exit 3 means
   proceed without it, note "narrative: degraded", never block recovery.
4. Assemble a **recovery delta** directly in your reply — no file, no `/clear`,
   no marker. Include only the classes compaction actually drops: verbatim
   user intents, decisions and their reasoning, dead ends / abandoned
   approaches, and early constraints. Explicitly skip what compaction
   preserves well — current state, todos, recent files — there's no value in
   re-deriving those. Cap the delta to what's genuinely load-bearing; cite the
   fact pack and narrative pack rather than dumping them.
5. Where the fact pack or narrative pack contradicts your post-compaction
   memory, the transcript-grounded pack wins.
6. If a `compacted-<epoch>` marker exists in `~/.claude/handoffs/<slug>/`,
   rename it to `recovered-<epoch>` (`mv`, not delete) now that recovery is
   done.
