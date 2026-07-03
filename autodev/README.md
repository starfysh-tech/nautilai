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

## Design notes

- No hooks. An earlier iteration ran the verifier as a `Stop` hook in every
  repo the plugin was enabled in; that was invasive (full test suite on every
  stop, and a blocking error in repos with no test suite) and was removed.
  Verification runs only inside the `/autodev` loop.
- The worker never creates `DONE.md`; the orchestrator writes it only after
  `verify.sh` passes.
- Classification heuristics are deliberately narrow: a misclassified
  implementation failure would be an *uncounted* retry, so ambiguous logs
  default to `implementation`.

## Backlog

- Repo-specific verifier presets for common stacks.
- Safe merge helpers for completed independent lanes.
- JSON-line attempt logs for easier analysis.
- Self-contained bash test suite for the scripts (per repo convention).
