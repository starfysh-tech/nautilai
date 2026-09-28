---
name: autodev
description: Run a plan or ticket(s) through a bounded, test-driven development loop — a launch checkpoint to confirm seams and acceptance scenarios, red tests written and committed one slice at a time, scripted worktree lanes, a fast haiku-worker subagent per attempt, objective script-based verification, a review gate, guard mutation checks, and a hard stop with a guidance handoff after 3 counted failures per slice. Use when the user runs /autodev, or asks to "run this ticket to completion", "work this plan test-first", or "keep trying until it's done or blocked". Flags: --setup | --plan-only | --review-tests | --unattended.
argument-hint: "[--setup | --plan-only | --review-tests <path> | --unattended] <plan or ticket(s) | path or URL>"
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, Agent, Skill, AskUserQuestion]
---

# AutoDev

Take `$ARGUMENTS` — a plan or ticket(s), as text, a file path, or a URL (read or
fetch it) — and drive it to done, blocked, or needs-guidance, test-first. All
state machinery is scripted; never manage git worktrees, lane state, test runs,
or commits by hand.

Scripts live in the plugin: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh`.
They write lane state into the user repo under `.autodev/` and worktrees under
`.autodev-worktrees/` (both self-gitignored). The TDD rules are in
`${CLAUDE_PLUGIN_ROOT}/skills/autodev/references/tdd.md`; read it before
planning. Terms: lane, slice, red test, launch checkpoint, guard, advisor, TDD
profile.

## Routing

Read the leading `--` flags of `$ARGUMENTS`; everything after them is the plan
or ticket input.

| Flags | Read and follow |
|---|---|
| `--setup` | `workflows/setup.md` |
| `--plan-only <input>` | `workflows/plan-only.md` |
| `--review-tests <path>` | `workflows/review-tests.md` |
| none, or `--unattended` | `workflows/run.md` |

All paths are under `${CLAUDE_PLUGIN_ROOT}/skills/autodev/`. An unknown `--`
flag: list the valid ones and stop.

Record the mode before anything else — `true` with `--unattended`, `false`
without it:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/controller.sh run-set unattended <true|false>
```

## Core rules

- One lane per independent task; retries reuse the lane.
- Up to 5 lanes in parallel, only lanes marked `parallel_safe`.
- Every attempt is one `haiku-worker` subagent call.
- Completion is decided by `verify.sh`, the review gate, and the guard check —
  never by the implementing model's self-judgment.
- Red tests are written one slice at a time, by you, never by the worker.
- After 3 counted failures in a slice (or a repeated identical failure
  fingerprint), stop the lane and hand off to the user.
- Commits go through the path `commit_path.sh` prints (see `workflows/run.md`),
  never raw `git commit`, never `--no-verify`.

## Stops and the advisor

The run has two stops: setup confirmation (only when the repo has no
`.claude/autodev.md`) and the launch checkpoint.

- `controller.sh run-get unattended` prints `true`: do not stop. Spawn the
  `advisor` agent with the stop's package and the path
  `${CLAUDE_PLUGIN_ROOT}/skills/autodev/references/tdd.md`; it decides; append its decision to
  `.autodev/<slug>/decisions.md`; continue.
- Otherwise, when the user can answer: ask with `AskUserQuestion`.
- Otherwise (a subagent without `--unattended`): write the stop's package to
  the lane dirs, set `controller.sh set <slug> checkpoint awaiting`, report
  `awaiting_checkpoint` with the lane dirs, and stop. A later run finds the
  lanes and shows the stop.

Never-advisor list — always escalate the lane, even when unattended:

- a change outside the lane branch (hook config, CI, shared config);
- a secret-scanner hit;
- anything irreversible.

If the `advisor` agent type does not resolve, use `general-purpose` with
`model: "opus"` and paste `${CLAUDE_PLUGIN_ROOT}/agents/advisor.md` into the prompt.

## State inspection

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/controller.sh show   # full state.json
bash ${CLAUDE_PLUGIN_ROOT}/scripts/list_lanes.sh        # lane dirs
```

## Completion report

A lane is complete only when every slice passed `verify.sh` and the review gate,
the guard check passed, and `DONE.md` exists with proof. Report per lane:
status, branch (`autodev/<slug>`), commits, changed files, verification
evidence, coverage, advisory findings, the decision log, and anything the user
must decide. Unattended runs: ask the user to keep or adjust each decision-log
entry; for an adjusted entry, reset the lanes its `affects` field names
(`controller.sh set <slug> checkpoint pending`) and run them again from the
step the decision belongs to.
