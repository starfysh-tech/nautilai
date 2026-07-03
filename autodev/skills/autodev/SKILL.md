---
name: autodev
description: Run a ticket, request, or implementation plan through a bounded autonomous development loop — scripted worktree lanes, a fast haiku-worker subagent per attempt, objective script-based verification, and a hard stop with a guidance handoff after 3 counted implementation failures. Use when the user runs /autodev, or asks to "run this ticket to completion", "work this plan autonomously", or "keep trying until it's done or blocked".
argument-hint: <ticket text | plan text | path or URL>
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, Agent]
---

# AutoDev

Take `$ARGUMENTS` (a ticket, plan, file path, or URL — read/fetch it if it's a
reference) and drive it to done, blocked, or needs-guidance. All state machinery
is scripted; never manage git worktrees or the state file by hand.

All scripts live in the plugin, invoked as
`bash ${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh`. They write lane state into the
user repo under `.autodev/` and worktrees under `.autodev-worktrees/` (both
self-gitignored).

## Core rules

- One task lane per independent task; reuse the same lane for repeated attempts.
- Up to 5 lanes in parallel, but only lanes marked `parallel_safe`.
- Every attempt is a `haiku-worker` subagent call, capped at one bounded attempt.
- Completion is decided by `verify.sh`, never by model self-judgment.
- After 3 counted implementation failures (or a repeated identical failure
  fingerprint), stop and hand off to the user.

## Loop

For each independent task in the request:

1. **Init the lane** (slug = short kebab-case task name):
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/init_task_lane.sh <slug> "<task text>"
   ```
   Then edit `.autodev/<slug>/TASK.md`: replace the placeholder acceptance
   criteria with objective, checkable ones. If the repo has no test suite
   covering the task, write `.autodev/<slug>/VERIFY.sh` with explicit checks.

   `VERIFY.sh` runs at two phases, distinguished by `$AUTODEV_PHASE`
   (`baseline` before any attempt, `attempt` after each one). When the task
   *creates* something that doesn't exist yet, branch on it — otherwise an
   honest verifier either fails baseline or falsely passes completion:
   ```bash
   if [[ "${AUTODEV_PHASE:-attempt}" == "baseline" ]]; then
     exit 0   # deliverable legitimately absent; repo otherwise healthy
   fi
   test -f autodev/tests/scripts.test.sh && bash autodev/tests/scripts.test.sh
   ```

2. **Create the worktree** (prints the worktree path):
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/create_worktree.sh <slug> [base-branch]
   ```

3. **Baseline verify** — confirms the lane starts green so pre-existing
   breakage is never billed to the worker. On failure the lane is flagged
   `needs_guidance`; report `.autodev/<slug>/baseline.log` to the user and stop
   this lane:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/baseline_verify.sh <worktree-path> <slug>
   ```

4. **Attempt loop** — repeat until done or the gate says stop:
   a. Gate check (exit 1 = stop this lane and escalate):
      ```bash
      bash ${CLAUDE_PLUGIN_ROOT}/scripts/controller.sh check <slug>
      ```
   b. Spawn a `haiku-worker` agent. Its prompt must include: the lane dir
      (`.autodev/<slug>`), the worktree path, and the task text. This loop
      assumes it runs in the main session, where the worker's completion
      returns to you directly; if you are yourself a subagent/teammate, the
      completion signal may not reach you — poll the worktree and
      `RUNSTATE.md` for the worker's handoff instead of waiting.
   c. Verify objectively, capturing the log:
      ```bash
      bash ${CLAUDE_PLUGIN_ROOT}/scripts/verify.sh <worktree-path> .autodev/<slug> \
        > .autodev/<slug>/attempt-N.log 2>&1
      ```
   d. On pass:
      ```bash
      bash ${CLAUDE_PLUGIN_ROOT}/scripts/controller.sh record-success <slug>
      ```
      Write `.autodev/<slug>/DONE.md` from the plugin template with the proof
      (checks run + results). Lane is complete.
   e. On fail, classify and record:
      ```bash
      CLASS=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/classify_failure.sh .autodev/<slug>/attempt-N.log)
      FP=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/fingerprint_failure.sh .autodev/<slug>/attempt-N.log)
      bash ${CLAUDE_PLUGIN_ROOT}/scripts/controller.sh record-failure <slug> "$CLASS" "$FP"
      ```
      - `transient` → retry once immediately (not counted).
      - `environment` / `specification` → do not retry; escalate now.
      - `implementation` → append a compact note to `RUNSTATE.md` and loop.

5. **Escalate** when a lane stops without success:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/escalate_summary.sh .autodev/<slug>
   ```
   Present its output to the user plus your suggested options. Do not grind on.

6. **Cleanup** — after the user accepts a completed lane (merged or discarded):
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/remove_worktree.sh <slug>
   ```
   Never remove a worktree with unmerged work without asking.

## Parallelism

`init_task_lane.sh` marks each lane `parallel_safe` via a conservative text
heuristic. Run lanes concurrently (spawn workers in one message) only when all
active lanes are `parallel_safe` and touch disjoint files/subsystems. Cap: 5.
When unsure, run sequentially.

## State inspection

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/controller.sh show   # full state.json
bash ${CLAUDE_PLUGIN_ROOT}/scripts/list_lanes.sh        # lane dirs
```

## Completion report

A lane is complete only when `verify.sh` passed and `DONE.md` exists with proof.
Report per lane: status, branch (`autodev/<slug>`), changed files, verification
evidence, and anything the user must decide (merge, follow-ups).
