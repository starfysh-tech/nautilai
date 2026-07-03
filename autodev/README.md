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

Neither reviews code quality beyond tests passing — that gap is on AutoDev's
backlog (a post-verify review gate), and it's one `/goal` structurally can't
close since its evaluator cannot execute a reviewer.

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

## Backlog

- Post-verify review gate: tests-green is necessary, not sufficient — a
  downstream bot review of run #2's output caught a P0 and a P1 that
  `verify.sh` blessed. A review pass should gate `DONE.md`.
- Repo-specific verifier presets for common stacks (incl. pnpm workspaces,
  where bare `npm test` misbehaves, and SwiftPM, which isn't detected).
- Safe merge helpers for completed independent lanes.
- JSON-line attempt logs for easier analysis.
