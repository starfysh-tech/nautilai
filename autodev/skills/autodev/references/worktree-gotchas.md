# Worktree gotchas

Worktree failures are often environmental, not code bugs. Check these before
classifying a failure as `implementation`.

## JS workspaces (pnpm/yarn)

Workspace symlinks don't survive worktree creation — a fresh install is
needed in the worktree itself.

- Pinned `packageManager` hits a corepack signature error → retry with
  `COREPACK_INTEGRITY_KEYS=0`.
- A transitive native build aborts the install (surfacing later as
  `<runner>: command not found`) → retry with `--ignore-scripts`.

Both are environment failures, not task failures.

## Gitignored env files

`.env.local`, `.secrets.local`, and similar don't survive worktree creation
either, and the symptom is misleading — tests fail on the *wrong-credential*
path (e.g. a 401 where a 400 is expected), which reads like a real bug.

If the suite is env-dependent and self-contained, generate fresh
lane-scoped **dummy** credentials in the worktree; never copy real secrets.
