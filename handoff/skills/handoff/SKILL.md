---
name: handoff
description: Compact the current conversation into a handoff document so a fresh agent can pick up the work. Use when the user runs /handoff, says 'hand this off', 'pass to next session', 'compact for the next agent', or 'I'm switching context'. References existing artifacts by path rather than restating them.
argument-hint: 'What will the next session be used for?'
---

Write a handoff document summarising the current conversation so a fresh agent can continue the work.

## 1. Generate the destination path

```bash
echo "${TMPDIR:-/tmp}/handoff-$(date +%Y%m%d-%H%M%S)-$$.md"
```

This prints a unique path **without creating the file** — so you `Write` it fresh (no `Read` round-trip first). `${TMPDIR:-/tmp}` and `$$` are portable across macOS, Linux, and POSIX shells. If the command prints nothing (e.g. `$TMPDIR` points somewhere unwritable), stop and tell the user — do not write to a guessed path.

## 2. Write the doc

Use the printed path as the destination. Structure the document with these sections (omit one only if genuinely empty):

- **Goal** — what the work is trying to achieve.
- **Current state** — what's done, what's in progress.
- **Decisions** — choices made and the reasoning, so they aren't re-litigated.
- **Open questions / blockers** — anything unresolved or waiting on input.
- **Next steps** — the concrete actions the next session should take first.
- **Key artifacts** — paths/URLs to plans, PRDs, ADRs, issues, commits, diffs. Reference them; do **not** restate their contents.
- **Suggested skills** — skills the next session is likely to need, if any.

## 3. Report the path

After writing, print the absolute path of the handoff doc so the user knows where it landed.

## Notes

- If the user passed arguments, treat them as a description of what the next session will focus on and tailor the doc accordingly.
- Keep it dense and skimmable — the next agent reads this cold.

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
