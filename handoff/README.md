# Handoff

Compact the current conversation into a handoff document so a fresh agent can pick up the work — referencing existing artifacts by path rather than restating them.

Distributed as a plugin via the [**nautilai**](../README.md) marketplace.

## Install

```text
/plugin marketplace add starfysh-tech/nautilai
/plugin install handoff@nautilai
```

## Use

```text
/handoff                         # write a handoff doc for the current work
/handoff debugging the auth flow # tailor it to what the next session will focus on
```

Handoff also triggers from natural language — "hand this off", "pass to next session",
"compact for the next agent", "I'm switching context" — without the explicit slash form.

## What it does

1. Generates a unique temp path (`$TMPDIR`/`/tmp`, portable across macOS, Linux, and POSIX shells) without pre-creating the file, so the doc is written in one pass.
2. Writes a structured handoff doc with these sections:

   | Section | Purpose |
   |---|---|
   | Goal | What the work is trying to achieve |
   | Current state | What's done, what's in progress |
   | Decisions | Choices made and the reasoning, so they aren't re-litigated |
   | Open questions / blockers | Anything unresolved or waiting on input |
   | Next steps | The concrete actions to take first |
   | Key artifacts | Paths/URLs to plans, PRDs, ADRs, issues, commits, diffs — referenced, not restated |
   | Suggested skills | Skills the next session is likely to need |

3. Prints the absolute path of the doc so you know where it landed.

If the optional argument is supplied, it's treated as a description of the next session's
focus and the document is tailored accordingly.

## License

MIT
