# The `.lanerc` contract

A `.lanerc` is a **sourced bash file** at the repo root. The engine sources it from the
main checkout on every verb (except `--help`), then calls its hooks with `CWD` set to
the lane. It is executable code with the user's privileges: review it like any script
you run, and treat every later edit to it as a new review.

## Variables

| Name | Default | Meaning |
|---|---|---|
| `LANE_ROOT` | `.claude/worktrees` | Where lanes live (relative to main). Self-gitignored on first open. |
| `LANE_BASE_BRANCH` | `main` | Base when `open` gets no `--base`. Resolved as `origin/<base>` (fetched), else local `<base>`; unresolvable fails. |
| `LANE_MODES` | `host` | Modes this recipe supports (`host proxy isolated`). `open --proxy/--isolated` fails unless listed. |
| `LANE_ENV_FILE` | `.env` | The app's env file, generated per lane. Must stay gitignored and inside the lane: a tracked file, symlink, or path resolving outside the lane is refused (checked before every write). |
| `LANE_ENV_COPY` | `true` | Seed the lane env file with main's copy (including its secrets). `false` = start empty. |
| `LANE_LINK_DIRS` | *(empty)* | Dirs **symlinked** from main. Only for deps proven branch-agnostic — installs through a link mutate main. |
| `LANE_PORT_VARS` | *(empty)* | `KEY:base` pairs: unique uppercase keys (not `LANE_*`, `BASH*`, or shell/engine names), unique bases 1024–65535. Lane port = `base + stride*offset`. |
| `LANE_PORT_STRIDE` | `100` | Port spacing between lanes. |
| `LANE_WORKTREE_GUARD` | `SKIP_WORKTREE_SETUP=1` | Space-separated `NAME=value` words set around `git worktree add`, so a repo's post-checkout bootstrap hook can skip. |
| `LANE_AGENT_MSG` | EnterWorktree form | Non-TTY handoff message (`%s` = lane path). |

Ports: offsets start at 1 (main is offset 0). Allocation runs under a lock and skips any
offset whose ports collide with main, another lane, or a listening socket — so
`WEB_PORT:3000 API_PORT:3100` with stride 100 is safe; the colliding offsets are skipped.

## Hooks (all optional)

Every hook runs in a subshell with `CWD=lane` (`lane_gc`: main) and **errexit on**: the
first failing command fails the hook, and a failed hook fails the verb. A failed `open`
keeps the lane and records its phase; `lane resume <slug>` continues from there. (An
open that dies before the worktree exists leaves only a reservation; `lane gc` or
reopening the slug reclaims it once that process has exited.)

Exported to every lane hook: `LANE_DIR`, `LANE_MAIN`, `LANE_SLUG`, `LANE_OFFSET`,
`LANE_PROJECT` (empty inside `lane_project`), `LANE_MODE`, `LANE_BASE_BRANCH`,
`LANE_ROOT`, and each port key from `LANE_PORT_VARS` with its per-lane value.
`lane_gc` gets only `LANE_MAIN` and `LANE_ROOT` (it sweeps all lanes, not one).

| Hook | Runs at | Contract |
|---|---|---|
| `lane_project()` | open | Print the project name (DB/hostname prefix). Default `<repo>-<slug>`. |
| `lane_env()` | open; resume `--env` | Print `KEY=VALUE` lines (blank and `#` lines ignored). Each **replaces** every definition of that key. Any other line, or a `LANE_*`/port key, fails the open. |
| `lane_setup()` | open, resume | Dependency install / hook regeneration for the lane. Must be idempotent. |
| `lane_route()` | open, resume | Write the lane's route / provision its resources. Must be idempotent. |
| `lane_start()` | open/resume with `--start` | Start the lane's services. Re-runs on every `resume --start`: stop the old ones first. |
| `lane_retire()` | rm (first) | Drop the lane's routes/resources. Failure keeps the lane unless `--force`. |
| `lane_stop()` | rm | Stop the lane's services — only this lane's (filter by port/project, never a bare `pkill`). |
| `lane_gc()` | gc (CWD=main, under the lock) | Drop lane-owned resources with no live worktree. Runs **before** stale offsets are released; on failure nothing is released. |

Open order: worktree → `lane_project` → env file (main copy, `LANE_*` keys, ports,
`lane_env`) → link `LANE_LINK_DIRS` → `lane_setup` → `lane_route` → `lane_start`
(with `--start`).

## Modes

`LANE_MODE` is a label the recipe branches on; the engine provisions nothing per mode.
`isolated` means isolated only if the recipe makes it so — its `lane_env` points the app
at a per-lane database/stack and `lane_route` (or `lane_setup`) creates it. List a mode
in `LANE_MODES` only once the recipe implements it.

## Engine state

`<LANE_ROOT>/.state/<slug>` holds `OWNER`, `OFFSET`, `MODE`, `PORTS`, `PROJECT`,
`BRANCH`, `BASE`, `PHASE`. It is the engine's source of truth (the app env file is
output, not state). Reservations and existence checks happen under a repo lock
(`.state/.lock`, owner PID recorded; a lock whose owner died is reclaimed).
`lane gc` drops state whose worktree is gone — except a reservation whose opening
process is still running — after `lane_gc` succeeds.

Lanes made by other tooling (no state) are listed by `ls`; the ports their env file
records for `LANE_PORT_VARS` keys (and `LANE_OFFSET`, if present) are never reallocated.
`rm` works on them, passing those recorded ports to `lane_retire`/`lane_stop` (a hook
that needs a port the file doesn't record fails, and `rm` refuses). `resume` does not.

## Env file syntax

The engine reads and replaces `KEY=VALUE` lines, with optional leading whitespace and
`export `, CRLF line endings, and one layer of matching quotes. Each key it sets
(`LANE_*`, ports, `lane_env` output) ends up with exactly one plain `KEY=VALUE` line;
lines for other keys are passed through from main's copy unchanged.

## Example

`lanerc.example` — a minimal Node + Python recipe.
