# Run — open, resume, remove lanes

`$LANE` below is `bash "${CLAUDE_PLUGIN_ROOT}/scripts/lane"`.

## 1. Ensure a recipe

No `.lanerc` at the repo root → follow
`${CLAUDE_PLUGIN_ROOT}/skills/worktree-lanes/workflows/setup.md` first.

## 2. Open

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/lane" open <slug> [--proxy | --isolated] [--start] [--base <ref>]
```

- Mode: no flag = **host** (default; shared DB, no hostnames). `--proxy` = shared DB
  plus per-lane hostnames. `--isolated` = the recipe provisions a per-lane DB/stack.
  A mode works only if the recipe lists it in `LANE_MODES`; never promise isolation the
  recipe doesn't implement (read its `lane_env`/`lane_route`).
- `--start` runs the recipe's `lane_start`; without it no services start.
- `--base <ref>` cuts from that ref (default: recipe's `LANE_BASE_BRANCH`). The engine
  prints the resolved ref and SHA — relay them.
- PR review: `$LANE pr <number> [mode] [--start]` → lane `pr-<number>` on the PR branch.

## 3. Report

From the engine output: lane path, branch, mode, offset, ports, and whether services
started. The agent handoff line (`AGENT ACTION REQUIRED …`) is an instruction to you:
switch the session into the lane.

## 4. A failed open

A failing hook stops the open and keeps the lane at its last completed phase. Read the
error, fix the cause (recipe or environment), then:

```bash
$LANE resume <slug> [--start] [--env]
```

`resume` re-runs linking, `lane_setup`, and `lane_route` (plus `lane_start` with
`--start` — also how to restart a lane's services). It writes the env file only if the
open died before writing it, or with `--env`, which regenerates it from the current
recipe and discards edits made to it — use it after fixing `lane_env`, and tell the user.
If resume reports no registered worktree, the open died before creating it: `$LANE gc`,
then open the slug again.

## 5. Inspect and remove

```bash
$LANE ls              # slug, branch, mode, offset, phase, ports
$LANE rm <slug>       # refuses if the lane has uncommitted changes
$LANE gc              # drop state for vanished worktrees; run the recipe's lane_gc
```

`rm` runs `lane_retire` then `lane_stop`, removes the worktree, and **keeps the
branch**. If it refuses (uncommitted work, or a failing teardown hook), show the user why.
`--force` discards uncommitted work — only with the user's explicit approval.
