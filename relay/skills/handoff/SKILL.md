---
name: handoff
description: Write a transcript-grounded handoff document so a fresh session can pick up the work automatically. Use when the user runs /handoff, says 'hand this off', 'pass to next session', 'relay this', 'compact for the next agent', or 'I'm switching context'. References existing artifacts by path rather than restating them.
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

## 3. Compute the destination

```bash
# Slug rule must match resolve-session.sh / session-start-pickup.sh.
slug=$(pwd | tr '/.' '-')
dir="$HOME/.claude/handoffs/$slug"
mkdir -p "$dir"
doc="$dir/$(date +%Y%m%d-%H%M%S).md"
```

## 4. Write the doc

Structure it with these sections (omit any of the twelve only if genuinely empty):

- **Goal** — what the work is trying to achieve.
- **Current state** — what's done, what's in progress.
- **Decisions** — choices made and the reasoning, so they aren't re-litigated.
- **Open questions / blockers** — anything unresolved or waiting on input.
- **Next steps** — the concrete actions the next session should take first.
- **Key artifacts** — paths/URLs to plans, PRDs, ADRs, issues, commits, diffs. Reference them; do **not** restate their contents.
- **Suggested skills** — skills the next session is likely to need, if any.
- **Files touched** — from the fact pack, curated to what matters.
- **Commands & outcomes** — notable commands and whether they succeeded, from the fact pack.
- **User intents (verbatim)** — the user's own words for what they asked for, quoted from the fact pack's user messages.
- **Dead ends** — approaches tried and abandoned; derive from the conversation and cross-check against the fact pack's Failures.
- **Provenance** — which extractors ran or degraded, and transcript size, so the next session can judge how much to trust this doc.

Populate the new sections from the fact pack — curated, not dumped: drop noise,
keep signal. The first seven sections carry the same semantics as before.

## 5. Write the consume-once marker

Write the doc's absolute path (and nothing else) to `$dir/pending`, overwriting
any existing marker. The `SessionStart` hook reads this file once, within a
30-minute TTL, to auto-inject the handoff into the next session, then renames it
`consumed-<epoch>` so it's never injected twice.

## 6. Report to the user

Print the absolute doc path, and tell them that running `/clear` will start a
fresh session that picks the handoff up automatically (30-minute TTL, consumed
once) — no need to paste or re-open it manually.

## Notes

- If the user passed arguments, treat them as a description of what the next session will focus on and tailor the doc — especially Next steps and Suggested skills — accordingly.
- Keep it dense and skimmable — the next agent reads this cold.
- Never invent a `${CLAUDE_PLUGIN_ROOT}/scripts/...` path other than the two above.

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
