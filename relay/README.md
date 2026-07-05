# Relay

Session continuity for Claude Code: a transcript-grounded handoff document that
a fresh session picks up automatically. Relay resolves the current session's
transcript, extracts a fact pack of what actually happened (files touched,
commands run, failures, verbatim user messages), and writes a handoff doc that
blends that ground truth with the running conversation's own understanding of
goals and decisions. A `SessionStart` hook then injects the pending doc into
the next session with no manual step.

Distributed as a plugin via the [**nautilai**](../README.md) marketplace.
Relay ships the `handoff` skill — the plugin was renamed to Relay, but the
skill kept its original name so existing trigger phrases ("hand this off",
`/handoff`) keep working.

## Why transcript-grounded

`/compact` and model self-summaries are recency-biased: they favor what's
fresh in context and quietly drop early constraints, dead ends already tried,
and decisions made and reasoned about many turns back. The session transcript
JSONL doesn't have that bias — everything that happened is still in it — so
Relay's bundled scripts extract facts from the transcript itself rather than
asking the model to remember.

## Install

```text
/plugin marketplace add starfysh-tech/nautilai
/plugin install relay@nautilai
```

## Use

```text
/handoff                         # write a handoff doc for the current work
/handoff debugging the auth flow # tailor it to what the next session will focus on
```

Also triggers from natural language — "hand this off", "pass to next session",
"relay this", "compact for the next agent", "I'm switching context" — without
the explicit slash form.

## Requirements

The fact pack extractor needs `jq`. The narrative step additionally needs the
`claude` CLI on `PATH` and makes 1-3 live Haiku calls per handoff (one per
transcript chunk, up to 3 for very large transcripts) — skipped gracefully,
with no impact on the rest of the handoff, when `claude` is unavailable.

## How it works

1. `scripts/resolve-session.sh` locates the current session's transcript JSONL.
2. `scripts/extract-transcript.sh` reads it and prints a fact pack: files
   touched, commands run, failures, user messages (verbatim, secret-scrubbed,
   with harness-injected content like skill prompts and compaction summaries
   filtered out), and provenance.
3. `scripts/haiku-narrative.sh` reads the same transcript's dialogue turns and
   prints a narrative pack — Decisions, Dead ends, Constraints — recovered
   from ASSISTANT prose via headless Haiku. The fact pack is structural (tool
   calls, verbatim user text) and can't see this; the reasoning behind a
   decision or why an approach was abandoned only lives in assistant turns,
   which need a model to summarize. Degrades gracefully (exit 3) if the
   `claude` CLI is missing or the call fails/times out — the handoff proceeds
   without it, noted in Provenance.
4. The skill writes a handoff doc combining the fact pack and narrative pack
   with its own understanding of the conversation — goal, decisions, next
   steps — plus fact-grounded sections (files touched, commands & outcomes,
   verbatim user intents, dead ends).
5. It writes a one-line pending marker pointing at the doc.
6. A `SessionStart` hook atomically claims that marker on the next session,
   injects the doc if it's still within its TTL, and renames the marker
   (`consumed-*`) so it only fires once — even with concurrent session starts.

### Recovery

Auto-compact loses the same kinds of things `/compact` does — early
constraints, dead ends, and the reasoning behind decisions made many turns
back — without you asking for a handoff. When Claude Code auto-compacts, a
`PreCompact` hook drops a `compacted-<epoch>` marker in the project's handoff
directory and emits a systemMessage nudging you to run `/handoff recover`.
That subcommand re-extracts the fact pack scoped to the transcript region
*before* the compaction boundary and rebuilds the compaction-lossy classes
in-session — no new handoff doc, no `/clear` required.

## Storage layout

```text
~/.claude/handoffs/<project-slug>/
├── pending              # absolute path to the doc awaiting pickup
├── compacted-<epoch>    # marker: an auto-compact happened, recovery not yet run
├── recovered-<epoch>    # marker: /handoff recover has already run for that compaction
└── <YYYYMMDD-HHMMSS>.md # the handoff doc(s)
```

`<project-slug>` is the working directory path with every `/` and `.` replaced
by `-`, so handoffs are scoped per project and don't collide across repos or
worktrees. The `pending` marker has a 30-minute TTL and is consumed (deleted)
the first time a session picks it up — a doc that isn't claimed within the
window is left on disk but no longer auto-injected.

## Disabling auto-pickup

The `SessionStart` hook is what makes pickup automatic. To go back to writing
handoff docs without the auto-inject behavior, either uninstall the plugin or
remove its hook registration — the skill itself still writes the doc and the
`pending` marker either way, it just won't be read back automatically.

## Roadmap

`/handoff recover` is shipped (see Recovery, above). The Haiku narrative layer
is also shipped: it recovers 11-12 of 12 planted assistant-turn facts across 3
eval runs vs 0/12 for the jq fact pack alone (see
`relay/tests/eval/LEDGER.md`).

## Security note

Transcript text is untrusted input — a session can contain arbitrary content,
including prose that reads as instructions (found the hard way: a transcript
about editing CLAUDE.md persona rules hijacked the narrative extractor in
testing). `haiku-narrative.sh` runs Haiku with a bare `--system-prompt` (no
CLAUDE.md inheritance) and explicit instructions to treat transcript content
as data to analyze, never as commands to obey or questions to answer.

## License

MIT
