---
name: worktree-lanes
description: Run several branches of a repo at once, each in its own git worktree with its own env file, ports, optional per-lane DB, linked or installed deps, and routes, so parallel work never collides. A bundled stack-agnostic engine driven by a per-repo .lanerc recipe the agent discovers, drafts, and the user approves. Use when the user asks to "run parallel branches", "work on several features at once", "open a dev lane", "spin up a worktree for this PR", or "set up worktree lanes". Flags --setup, --proxy, --isolated, --start, --base.
argument-hint: "[--setup | <slug> [--proxy | --isolated] [--start] [--base <ref>]]"
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob]
---

# Worktree Lanes

> **omp / pi:** these runtimes leave `${CLAUDE_PLUGIN_ROOT}` literal in skill text. If it appears unexpanded below, substitute the plugin root: the directory two levels above the folder containing this `SKILL.md` (`<plugin-root>/skills/<skill>/SKILL.md`).

A lane is a git worktree that behaves like the main checkout but with its own ports,
env file, and (when the recipe supports it) database and hostnames. The **engine**
(`bash "${CLAUDE_PLUGIN_ROOT}/scripts/lane"`) is generic; the **recipe** (`.lanerc` at
the repo root) is per-repo bash that the engine sources.

Read `${CLAUDE_PLUGIN_ROOT}/skills/worktree-lanes/references/contract.md` before
writing or editing a recipe. When a lane misbehaves, read
`${CLAUDE_PLUGIN_ROOT}/skills/worktree-lanes/references/gotchas.md`.

## Routing

| `$ARGUMENTS` | Read and follow |
|---|---|
| `--setup` | `workflows/setup.md` |
| `<slug>` with optional `--proxy`/`--isolated`/`--start`/`--base <ref>` | `workflows/run.md` |

Paths are under `${CLAUDE_PLUGIN_ROOT}/skills/worktree-lanes/`. Any other `--` flag:
list the valid ones and stop.

## Core rules

- Drive lanes only through the engine; never hand-run `git worktree add/remove` on its
  lanes or edit `<LANE_ROOT>/.state/`.
- The recipe is executable code. Writing it, and **any later edit** to it, is a user
  stop: show the diff and get confirmation (no user → write `.lanerc.draft`, stop).
- Never claim isolation the recipe doesn't implement: a mode works only if listed in
  `LANE_MODES`, and `isolated` must provision its own DB/stack.
- `lane rm` refuses a lane with uncommitted work. Use `--force` only when the user has
  said to discard that work.
- Engine errors are real failures: report them; don't retry by hand or work around the
  engine. A failed open is continued with `lane resume <slug>`.
- Don't print lane env files (they carry main's secrets); grep specific keys.

## State inspection

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/lane" ls
```

## Completion

A lane is ready when the engine prints `lane ready`. Report path, branch, base ref,
mode, ports, and whether services started; act on the `AGENT ACTION REQUIRED` handoff
line (switch the session into the lane).
