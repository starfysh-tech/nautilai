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

Immediately start step 3's `haiku-narrative.sh` in the background now, before
step 2 — it takes 20s–2.5min and should overlap the fact-pack read.

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
(chunked to at most 3 calls); it should already be running in the background
from step 1 by the time you reach this step. On exit 3 (degraded — `claude`
missing, the call failed/timed out,
output was empty, or the user set `RELAY_NARRATIVE=off`), proceed without it
and record the degrade reason from stderr in the doc's Provenance section;
never block the handoff on this step, and never re-prompt the user about a
deliberate `RELAY_NARRATIVE=off`.

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
- **Open questions / blockers** — anything unresolved or waiting on input. For each in-progress item, state its done-criterion — what "done" actually means for it — so the next session resumes against a target instead of re-deriving one.
- **Next steps** — the concrete actions the next session should take first.
- **Key artifacts** — paths/URLs to plans, PRDs, ADRs, issues, commits, diffs. Reference them; do **not** restate their contents.
- **Suggested skills** — skills the next session is likely to need, if any.
- **Files touched** — from the fact pack, curated to what matters.
- **Commands & outcomes** — notable commands and whether they succeeded, from the fact pack.
- **User intents (verbatim)** — the user's own words for what they asked for, quoted from the fact pack's user messages.
- **Dead ends** — approaches tried and abandoned; derive from the narrative pack and the conversation, cross-checked against the fact pack's Failures.
- **Provenance** — which extractors ran or degraded (including the narrative pack), and transcript size, so the next session can judge how much to trust this doc.

Populate the new sections from the fact pack — curated, not dumped: drop noise,
keep signal. Signal to keep verbatim when present: error messages and stack
traces, function signatures and type definitions, and test names with their
failure reasons. Noise to drop: raw file contents, exploratory chat, and
intermediate reasoning that didn't change a decision.

## 6. Write the consume-once marker

Write the doc's absolute path (and nothing else) to `$dir/pending`, overwriting
any existing marker. The `SessionStart` hook reads this file once to auto-inject
the handoff into the next session, then renames it `consumed-<epoch>` so it's
never injected twice. A 30-minute TTL applies only on `source=startup`; a
`/clear` handoff is honored regardless of age.

## 7. Report to the user

Print the absolute doc path, and tell them that running `/clear` will start a
fresh session that picks the handoff up automatically (consumed once, no TTL on
`/clear`) — no need to paste or re-open it manually.

## Recover mode (`/handoff recover`)

For `/handoff recover` (after auto-compact), read and follow
`${CLAUDE_PLUGIN_ROOT}/skills/handoff/workflows/recover.md`.

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
