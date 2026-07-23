# Backlog

Tracked, non-urgent work for the nautilai marketplace and its plugins.

## CommitCraft

- **Restructure dispatch from one arg-driven skill to plugin commands.**
  Today CommitCraft is a single skill named `commitcraft`, so it surfaces as the doubled
  id `commitcraft:commitcraft` and subcommands ride in as an argument
  (`/commitcraft commit`). Splitting the workflows into plugin commands
  (`commands/commit.md`, `commands/pr.md`, …) would invoke as `/commitcraft:commit`,
  `/commitcraft:pr`, etc. — one namespace level, no name repeat, subcommands mapped to real
  files.
  - **Why:** cleaner invocation and discoverability; removes the cosmetic `:commitcraft`
    repeat.
  - **Cost / risk:** a real refactor of how CommitCraft routes subcommands; the shared
    `AskUserQuestion`-first preamble and execution policy would need to live in each command
    or a shared include. Not worth doing on its own — fold into the next substantive
    CommitCraft change.

## AutoDev

- **Installed-plugin dogfood run.** Run `/autodev` on a low-stakes task from a
  fresh session with autodev installed (v2.9.0+, user scope) — the first
  exercise of the native path every validation run bypassed: skill triggering
  from its description, harness-expanded `${CLAUDE_PLUGIN_ROOT}`,
  `haiku-worker`/`review-gate` agent-type resolution, direct worker completion
  signals in the main session, and the first live review-gate `pass` producing
  `DONE.md`. Findings go into [autodev/tests/SCENARIOS.md](autodev/tests/SCENARIOS.md) as the dogfood-run
  entry, same improve→confirm loop as runs 1–5.
  - **Why:** top-ranked readiness gap (see the [autodev/README.md](autodev/README.md#backlog) backlog) — the
    documented primary path is the one path never validated.
  - **Cost / risk:** one session, one small task; failures are visible, not
    silent (worst case is first-run friction, which is itself the data).

## sentry-ops

- **Deferred workflows.** Five candidates were scoped and left out of the initial
  plugin, which ships four workflows (`audit`, `triage`, `investigate`,
  `instrument`):
  - alert-rule and monitor review
  - release-health and adoption analysis
  - quota and sampling cost tuning
  - performance-trace investigation
  - cron monitor setup
  - **Why:** four workflows that hold up under real use beat eight thin ones. Each
    deferred item needs its own grounding — alerting and quota behavior are
    org-level Sentry settings, and performance traces are a different data shape
    than issues — so bolting them on would have diluted the four that work.
  - **Cost / risk:** each is largely additive (a new workflow file plus its
    disposition rules), so none blocks the others; the real cost is the same
    docs-grounding pass `audit` already pays, repeated per surface.
