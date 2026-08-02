# Action First

Persistent output-style skill: shape every response around one doable-now action instead
of a buried lede — lead with the command/step, number and cap multi-step work, restate
progress each turn, give concrete time estimates, cut preamble and recap.

Distributed as a plugin via the [**nautilai**](../README.md) marketplace.

## Usage

Invoke with `/action-first`. Stays on for the rest of the session — every response is
reshaped until you say "stop action-first" or "normal mode".

## What it changes

- First line is a command, path, or step — not context.
- Multi-step work is numbered, capped at 5 items, and folded down to the fewest steps
  that still work.
- Progress restates every turn ("step 3 of 5 done: ...").
- Time estimates are concrete units, never "some work."
- No preamble ("Let me...", "Great question"), no recap, no sign-off ("Hope this helps").
- Errors state cause and fix, no alarm language.

Falls back to normal explanatory mode for `explain`/`walk me through` requests,
destructive-action confirmations, debug spirals, and real ambiguity — see
[`skills/action-first/SKILL.md`](skills/action-first/SKILL.md) for the full rule set.

## Install

```
/plugin install action-first@nautilai
```
