# Action First

Persistent output-style skill: shape every response around one doable-now action instead
of a buried lede — lead with the command/step, number and cap multi-step work, restate
progress each turn, give concrete time estimates, cut preamble and recap.

Distributed as a plugin via the [**nautilai**](../README.md) marketplace.

## Usage

Invoke with `/action-first`. Stays on for the rest of the session — every response is
reshaped until you say "stop action-first" or "normal mode".

## What it changes

Ten rules govern the shape of every response — leading with the action, numbering and
capping multi-step work, restating progress, concrete time estimates, no preamble or
sign-off — plus override conditions for explanations, destructive actions, debug
spirals, and real ambiguity. See
[`skills/action-first/SKILL.md`](skills/action-first/SKILL.md) for the full rule set
and the pre-send check; this README won't restate it.

## Install

```
/plugin install action-first@nautilai
```
