---
name: handoff
description: Write a transcript-grounded handoff document so a fresh session can pick up the work automatically. Use when the user runs /handoff, says 'hand this off', 'pass to next session', 'relay this', 'compact for the next agent', or 'I'm switching context'. Also use for /handoff recover after auto-compact, 'recover what compaction dropped', or 'rebuild lost context'. References existing artifacts by path rather than restating them.
argument-hint: 'What will the next session be used for?'
---

Write a handoff document from the ground truth of this session's transcript — not
just your in-context memory — so a fresh agent can continue the work and pick it
up automatically on `/clear`.

## 1. Resolve the transcript

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-session.sh
```

Prints the current session's transcript JSONL path. A warning on stderr means it
had to guess by mtime — proceed, but treat the fact pack below as slightly less
certain. If it exits nonzero, say so and fall back to writing the handoff purely
from in-context knowledge — never abort the handoff over a missing transcript.

## 2. Extract the fact pack

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/extract-transcript.sh <transcript>
```

This prints a markdown fact pack: Files touched, Commands run, Failures, User
messages (verbatim, secret-scrubbed), and Provenance. Treat it as **ground
truth** — it's pulled from the transcript, not reconstructed from memory. Where
it disagrees with your in-window recollection, trust the fact pack and note the
discrepancy in the doc rather than silently picking one.

## 3. Extract the narrative pack

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/haiku-narrative.sh <transcript>
```

Prints a narrative pack — `## Decisions` / `## Dead ends` / `## Constraints` —
recovered from ASSISTANT turns via headless Haiku, which the fact pack
structurally can't see (it only reads tool_use/tool_result/user-text). This
call can take ~20s for one chunk and up to ~2.5min for a huge transcript
(chunked to at most 3 calls) — start it right after resolving the transcript
in step 1 and let it run in the background while you read the fact pack in
step 2. On exit 3 (degraded — `claude` missing, the call failed/timed out, or
output was empty), proceed without it and record "narrative: degraded" in the
doc's Provenance section; never block the handoff on this step.

## 4. Compute the destination

```bash
# Slug rule must match resolve-session.sh / session-start-pickup.sh.
slug=$(pwd | tr '/.' '-')
dir="$HOME/.claude/handoffs/$slug"
mkdir -p "$dir"
doc="$dir/$(date +%Y%m%d-%H%M%S).md"
```

## 5. Write the doc

Structure it with these sections (omit any of the twelve only if genuinely empty):

- **Goal** — what the work is trying to achieve.
- **Current state** — what's done, what's in progress.
- **Decisions** — choices made and the reasoning, so they aren't re-litigated. Build from the narrative pack, the fact pack, and in-window knowledge together; the narrative pack is transcript-grounded, so where it disagrees with post-compaction memory it wins, same rule as the fact pack.
- **Open questions / blockers** — anything unresolved or waiting on input.
- **Next steps** — the concrete actions the next session should take first.
- **Key artifacts** — paths/URLs to plans, PRDs, ADRs, issues, commits, diffs. Reference them; do **not** restate their contents.
- **Suggested skills** — skills the next session is likely to need, if any.
- **Files touched** — from the fact pack, curated to what matters.
- **Commands & outcomes** — notable commands and whether they succeeded, from the fact pack.
- **User intents (verbatim)** — the user's own words for what they asked for, quoted from the fact pack's user messages.
- **Dead ends** — approaches tried and abandoned; derive from the narrative pack and the conversation, cross-checked against the fact pack's Failures.
- **Provenance** — which extractors ran or degraded (including the narrative pack), and transcript size, so the next session can judge how much to trust this doc.

Populate the new sections from the fact pack — curated, not dumped: drop noise,
keep signal. The first seven sections carry the same semantics as before.

## 6. Write the consume-once marker

Write the doc's absolute path (and nothing else) to `$dir/pending`, overwriting
any existing marker. The `SessionStart` hook reads this file once, within a
30-minute TTL, to auto-inject the handoff into the next session, then renames it
`consumed-<epoch>` so it's never injected twice.

## 7. Report to the user

Print the absolute doc path, and tell them that running `/clear` will start a
fresh session that picks the handoff up automatically (30-minute TTL, consumed
once) — no need to paste or re-open it manually.

## Recover mode (`/handoff recover`)

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

## Notes

- If the user passed arguments, treat them as a description of what the next session will focus on and tailor the doc — especially Next steps and Suggested skills — accordingly.
- Keep it dense and skimmable — the next agent reads this cold.
- Never invent a `${CLAUDE_PLUGIN_ROOT}/scripts/...` path other than the three above.

## Shoals (project corrections)

At the start of a run, read `.claude/shoals/handoff.handoff.md` from the project
root if it exists, and honor every entry as a constraint.

When the user corrects your behavior — what a handoff doc for this project must
always include or omit — append a shoal to that file (creating `.claude/shoals/`
if needed):

```markdown
## <short title>
- **Trigger:** when this comes up
- **Wrong:** what you did that the user rejected
- **Correct:** what to do instead
- **Why:** the reason
```

Append-only — never edit or delete an entry; retire one with `- **Obsolete:**
<date> — <reason>`. Dedup on **Trigger**. Capture only explicit behavioral
corrections, not passing preferences. Mention the capture in one line; don't
narrate it.
