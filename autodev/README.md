# AutoDev

Bounded autonomous development loop for Claude Code: take a ticket or plan and
work it to done, blocked, or needs-guidance — without letting the model grind
indefinitely or grade its own homework.

## Install

```
/plugin install autodev@nautilai
```

## Usage

```
/autodev <ticket text | plan text | path or URL>
```

## How it works

- **One task lane per independent task** — state in `.autodev/<slug>/`
  (`TASK.md`, `RUNSTATE.md`, `DONE.md`, optional `VERIFY.sh`), all
  self-gitignored.
- **Scripted worktrees** — every lane gets `.autodev-worktrees/<slug>` on an
  `autodev/<slug>` branch via `create_worktree.sh`; the model never manages
  worktree mechanics by hand.
- **Baseline verification** — checks must pass *before* autonomous work starts,
  so pre-existing breakage is never billed to the worker.
- **Fast worker subagents** — each attempt is one bounded `haiku-worker` run
  that makes the smallest useful change and reports a structured result.
- **Objective verification** — `verify.sh` (lane `VERIFY.sh`, else auto-detected
  npm/pytest/go/cargo suite) decides completion, not model self-judgment.
- **Review gate** — tests-green is necessary, not sufficient: after `verify.sh`
  passes, an independent `review-gate` agent reviews the lane diff against
  TASK.md for what tests can't see (resource lifecycle, scope creep, weak new
  tests, security patterns). Blocking findings count as an implementation
  failure toward the same 3-cap; only a `pass` verdict yields `DONE.md`.
- **Failure accounting** — failures are classified
  (implementation / environment / specification / transient) and fingerprinted;
  only implementation failures count toward the cap.
- **Hard escalation** — after 3 counted failures or a repeated identical
  failure fingerprint, `controller.sh check` stops the lane and
  `escalate_summary.sh` produces a concise guidance handoff for the user.
- **Bounded parallelism** — up to 5 lanes at once, only when marked
  `parallel_safe` by a conservative heuristic.

## Scripts

All invoked by the skill via `${CLAUDE_PLUGIN_ROOT}/scripts/`:

| Script | Purpose |
| --- | --- |
| `init_task_lane.sh <slug> "<task>"` | Create lane files + controller state |
| `create_worktree.sh <slug> [base]` | Create/reuse the lane worktree |
| `remove_worktree.sh <slug>` | Remove worktree + `autodev/<slug>` branch |
| `baseline_verify.sh <worktree> <slug>` | Pre-flight green check |
| `verify.sh [dir] [lane-dir]` | Objective verifier (lane `VERIFY.sh` wins) |
| `classify_failure.sh <log>` | Bucket a failure log |
| `fingerprint_failure.sh <log>` | Digit/hex-stripped failure hash |
| `controller.sh <cmd> …` | State machine over `.autodev/state.json` |
| `parallel_safe.sh <task-file>` | Conservative parallelism heuristic |
| `escalate_summary.sh <lane-dir>` | Guidance handoff for a blocked lane |
| `list_lanes.sh` | List lane directories |

## AutoDev vs `/goal`

Claude Code's built-in `/goal` (v2.1.139+) also drives work to a completion
condition, and for a quick "keep going until the tests pass" in a session
you're watching, it's the right lighter tool. AutoDev exists for the
unattended case, where the differences are structural:

| | `/goal` | AutoDev |
| --- | --- | --- |
| Completion decided by | an evaluator model **reading the transcript** — it can't run commands, so it grades what the model *reports* | `verify.sh` exit code, run by scripts, with logs and a `DONE.md` proof |
| Failure handling | turn/time cap, then stops — no classification, no repeat detection, no handoff | classify → fingerprint → counted 3-cap → escalation summary |
| Blast radius | your live checkout | isolated worktree per lane |
| Concurrency | one goal per session | up to 5 gated lanes |
| Attempt cost | full-context main-loop turns | disposable haiku workers |

And where `/goal` provides no quality controls beyond your condition text,
AutoDev runs an independent review gate after tests pass — something `/goal`
structurally can't do, since its evaluator cannot execute a reviewer.

## Conventions

`review-gate` is a deliberate exception to the repo-wide
[finding-dispositions](../docs/conventions/finding-dispositions.md) convention:
it returns a `pass`/`block` verdict with blocking/advisory findings instead of
`auto-fix`/`report`/`ask-user`. It's a pipeline-internal gate consumed by the
orchestrator, not a user-facing review — `block` maps to `ask-user` (the
orchestrator decides whether to loop or escalate), `advisory` maps to
`report`, and there is no `auto-fix` because the reviewer is read-only
(`Read, Bash, Grep, Glob`, no `Edit`/`Write`).

## Design notes

- No hooks. An earlier iteration ran the verifier as a `Stop` hook in every
  repo the plugin was enabled in; that was invasive (full test suite on every
  stop, and a blocking error in repos with no test suite) and was removed.
  Verification runs only inside the `/autodev` loop.
- The worker never creates `DONE.md`; the orchestrator writes it only after
  `verify.sh` passes.
- `VERIFY.sh` receives `AUTODEV_PHASE` (`baseline` | `attempt`) so greenfield
  tasks — where the deliverable doesn't exist yet — can pass baseline honestly
  without falsely passing completion.
- Classification heuristics are deliberately narrow: a misclassified
  implementation failure would be an *uncounted* retry, so ambiguous logs
  default to `implementation`.

## Tests

Self-contained, offline bash suite (fixtures in `mktemp` dirs, no stubs):

```bash
bash autodev/tests/scripts.test.sh
```

Fittingly, the suite was authored by the plugin itself during its first live
validation run.

## Validated scope

Five live validation runs across five repos (see
[`tests/SCENARIOS.md`](tests/SCENARIOS.md)) — but scope is narrower than
"any repo", deliberately stated:

- **Stacks validated:** npm (`node --test`), bun-via-npm, pytest — all with
  fast suites (≤30s). go/cargo detection exists but is unexercised. pnpm/yarn
  workspaces and SwiftPM need a hand-written lane `VERIFY.sh`.
- **Environment:** one macOS machine, with user-level guardrail hooks (the
  secrets protection observed in run #5 came from the environment, not this
  plugin). Linux/CI untested.
- **Orchestration path validated:** teammate-fallback only; every run
  hand-substituted `${CLAUDE_PLUGIN_ROOT}`. The native installed-plugin path
  (skill triggering, agent-type resolution, main-session signals) has not run.
- **Review gate:** 3-for-3 correct blocks live; zero live `pass` verdicts —
  the DONE.md happy path through the gate and the false-positive rate are
  unmeasured.

## Backlog

Before this is trustworthy on *any* repo (ranked; the first three are the
confidence gate for general use):

- **Installed-plugin dogfood run** — first release, real `/plugin install`,
  main-session `/autodev` on a low-stakes task; must exercise skill
  triggering, native `${CLAUDE_PLUGIN_ROOT}`, agent-type resolution, and a
  lane that *passes* the review gate (DONE.md-with-verdict path).
- **Review-gate calibration** — measure the false-positive rate on ordinary
  decent diffs; every false block burns a third of the cap.
- **`harvest_lane.sh`** — completed work strands in the worktree today
  (commit on lane branch → push → PR → clean); done by hand four times, and
  deleting an unharvested worktree destroys the only copy.
- **`preflight.sh`** — fail fast before lane init: clean tree, verifier
  detectable (or lane VERIFY.sh required), `python3` present, remote/`gh`
  available; today these surface mid-run as confusing failures.
- **Environment portability** — Linux/CI, machines without guardrail hooks
  (promote the never-copy-secrets rule from prompt to script), cold-corepack
  recovery as automation rather than documentation.
- **Verifier presets / supported-stacks table** — exercise go/cargo; preset
  pnpm-workspace and long-suite (minutes) handling; publish what's supported.
- **Task-intake validation** — ticket URLs, plan files, and model-driven lane
  decomposition have never been exercised; all runs got curated task text and
  pre-split lanes.
- JSON-line attempt logs for easier analysis.
