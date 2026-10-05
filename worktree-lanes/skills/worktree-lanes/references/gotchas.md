# Worktree gotchas

A misbehaving lane is usually environmental, not a bug in the branch. Check these first.

## Worktrees are not relocatable

A venv bakes its absolute path into every shebang; version managers (mise, asdf,
pyenv) trust config by path. Never `mv` a lane — `rm` it and open a new one.

## Linked dependencies

A symlinked `node_modules`/`.venv` is shared with main: a different lockfile on the
branch gives wrong deps, native modules break across versions, and an install inside
the lane rewrites main's copy. Stale or "impossible" import errors in a lane → move the
dir out of `LANE_LINK_DIRS` and install it in `lane_setup`.

## Shared database (host / proxy)

Only `isolated` lanes get their own DB, and only if the recipe provisions one. In host
and proxy mode, migrations and seeds hit every lane. Before running a migration in a
lane, check `LANE_MODE` and the effective DB name in its env file.

## Env file precedence

The engine writes one definition per key it sets, but the shell environment usually wins over a
dotenv file. A key exported in the user's shell (or by direnv/mise) overrides the lane's
value. When a lane talks to the wrong DB/port, compare `env | grep KEY` with the lane
env file.

## Secrets

With `LANE_ENV_COPY=true` (default) every lane's env file holds a copy of main's,
secrets included. `rm` deletes them with the worktree. Don't print lane env files into
transcripts — grep specific keys.

## A route that outlives its lane

Routes are keyed by hostname/port. A route not retired on `rm` silently serves the next
lane that gets the same offset. `lane gc` releases offsets of vanished lanes and runs
the recipe's `lane_gc` to sweep routes. Wrong app on a lane's hostname → `lane gc`.

## Auto-bootstrap hooks

`git worktree add` fires the repo's post-checkout hook, which may run its own full
setup. The engine sets `LANE_WORKTREE_GUARD` (default `SKIP_WORKTREE_SETUP=1`) around
the add; if the repo's hook checks a different variable, set the guard to that, or setup
runs twice.

## A failed open

The lane is kept at its last completed phase (`lane ls` shows it). Fix the cause and
`lane resume <slug>`; or discard with `lane rm <slug> --force`. A fix to `lane_env`
needs `lane resume <slug> --env` (it rewrites the env file, dropping edits to it). An
open that died before creating the worktree leaves a reservation: reopen the slug, or
`lane gc`, once that process has exited.
