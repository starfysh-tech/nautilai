# Setup — discover the stack, write a `.lanerc`

Read `${CLAUDE_PLUGIN_ROOT}/skills/worktree-lanes/references/contract.md` first.
`$LANE` below is `bash "${CLAUDE_PLUGIN_ROOT}/scripts/lane"`.

## 1. Existing tooling first

- `.lanerc` exists → show it; offer targeted hook changes if the stack moved; stop.
- The repo already has worktree tooling (a `lane`/`worktree` script, mise/just/make
  task, `.claude/hooks/*worktree*`, a post-checkout hook that bootstraps worktrees) →
  the recipe's hooks should **call that tooling**, not reimplement it. Note the env
  variable its post-checkout hook checks to skip auto-setup → `LANE_WORKTREE_GUARD`.

## 2. Discover

Read the repo's bootstrap and run paths: `Makefile`, `package.json` scripts,
`mise.toml`, `justfile`, `Procfile`, `docker-compose.yml` / `compose.yaml`,
`setup.sh` / `scripts/*` / `bin/*`, `.env.example`, lockfiles, CI setup steps.
Establish, citing the file for each:

1. **Install** — the commands that make a fresh checkout runnable. Default to running
   them per lane in `lane_setup`. Use `LANE_LINK_DIRS` only for a dir you can show is
   identical across branches.
2. **Services and ports** — every service that binds a port → `LANE_PORT_VARS`, and how
   the service is told its port (flag, env var) → used in `lane_start` / `lane_env`.
3. **Config** — the gitignored env file the app reads → `LANE_ENV_FILE`. If config is
   not a dotenv file (JSON/YAML, multiple files), generate it in `lane_setup` from the
   exported `LANE_*`/port vars.
4. **Isolation** — what collides between two running copies: DB name, Compose project
   name, volumes, hostnames, caches. Decide which modes the recipe will really support
   → `LANE_MODES`. Only list `isolated` if `lane_env` + `lane_route` actually create and
   point at a per-lane database/stack.
5. **Routing** — hostname-based access (reverse proxy, traefik) → `lane_route`,
   `lane_retire`, `lane_gc`.

## 3. Draft

Start from `${CLAUDE_PLUGIN_ROOT}/skills/worktree-lanes/references/lanerc.example`.
Comment each hook with the file it was derived from. Rules:

- Hooks must be idempotent (`lane_setup`/`lane_route` re-run on `resume`).
- `lane_stop` touches only this lane's processes (PID files under
  `$LANE_MAIN/$LANE_ROOT/.run/$LANE_SLUG`, a Compose project name) — never a bare
  `pkill -f`.
- Keep lane runtime files out of the worktree, or `rm` will see them as uncommitted work.
- `LANE_ENV_COPY=true` (default) copies main's env, secrets included. Set `false` and
  generate only what the lane needs when copying main's secrets isn't acceptable.

## 4. Confirm (user stop)

Show the full draft and the evidence per hook. Setup is always a user stop:

- User available → on confirmation write `.lanerc`, suggest committing it.
- No user → write `.lanerc.draft`, report `awaiting_setup` with
  `mv .lanerc.draft .lanerc`, stop.

## 5. Smoke-test

Use a unique throwaway slug, the most demanding declared mode, and `--start`:

```bash
SLUG="zz-setup-$(date +%s)"
$LANE open "$SLUG" --start              # host-only recipe
$LANE open "$SLUG" --start --isolated   # if it declares isolated
```

Then prove it works: hit each service on the lane's printed ports (e.g.
`curl -fsS localhost:<port>/health`), and for `isolated` confirm the app is on the
lane's DB name, not main's. On failure, fix the recipe and run
`$LANE resume "$SLUG" --start` — add `--env` when the fix was in `lane_env`.
Do not print the lane's env file — it holds main's secrets; grep the specific keys.

Clean up only what the smoke test made:

```bash
$LANE rm "$SLUG" --force
git branch -D "$SLUG"
```

Setup is done only when a lane opened, served, and was removed cleanly.
