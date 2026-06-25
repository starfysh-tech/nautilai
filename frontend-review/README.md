# Frontend Review

Two read-only audits for a React + Tailwind frontend, bundled as one plugin:

- **react-component-architecture** — oversized components, prop drilling, duplicated UI
  patterns that should be extracted to primitives, loose-string variant props, and
  folder organization.
- **tailwind-design-token-validator** — Tailwind design-token violations: arbitrary
  values (`bg-[#3b82f6]`), dynamic class concatenation that breaks purging, `@apply`
  overuse, inline styles, and basic accessibility gaps.

Both auto-detect the frontend source root (and, for Tailwind, the config) — no
hardcoded path. Every finding cites `file:line`.

Distributed as a plugin via the [**nautilai**](../README.md) marketplace.

## Install

```text
/plugin marketplace add starfysh-tech/nautilai
/plugin install frontend-review@nautilai
```

No runtime dependencies — both skills run entirely on `Glob`/`Grep`/`Read` (the
Tailwind skill also uses `Edit`, gated, for exact token swaps).

## Use

```text
/react-component-architecture                 # auto-detect the source root, audit it
/react-component-architecture src/features    # audit a path

/tailwind-design-token-validator              # auto-detect root + tailwind config
/tailwind-design-token-validator src/         # audit a path
```

Both are **user-invoked** (`disable-model-invocation: true`) — they won't auto-fire
mid-conversation.

## What it does

The skills perform the analysis directly (the model is the analyzer); they don't ship
a separate engine. Each:

1. **Resolves the frontend root** by finding the React `package.json` and its source
   dir, rather than assuming `client/` or `src/`. The Tailwind skill also finds the
   project's `tailwind.config.*` (or v4 CSS `@theme`) and treats it as the source of
   truth for what a "token" is.
2. **Runs its checks** over `.tsx`/`.jsx`/`.css` files and reports findings-first —
   leading with what's wrong, omitting clean categories, citing `file:line`.

## Conventions

This plugin follows the [nautilai conventions](../docs/conventions/README.md):

- **Finding dispositions (#1).** `react-component-architecture` is propose-only:
  **auto-fix** none, **report** every finding, **ask-user** before any restructuring.
  `tailwind-design-token-validator` is the same except for one **auto-fix** case — an
  arbitrary value that maps 1:1 to a defined token with an identical computed value
  (e.g. `bg-[#3b82f6]` → `bg-primary`), applied via `Edit` only after the user opts in,
  reported as `file:line  old → new`, and VCS-visible per the auto-fix safety contract.
  Any approximate or structural change is **ask-user** and is never self-resolved.
- **Findings-first (#2).** No "✓ all good" padding, no per-step narration.
- **Cite `file:line` (#5).** Every claim about the user's code is grounded.
- **Declare invocation intent (#10).** Both skills are `disable-model-invocation: true`
  and read-heavy (`context: fork`).
- **Shoals (#11).** Each skill captures explicit behavioral corrections to
  `.claude/shoals/frontend-review.<skill>.md` in your project and reads them back on
  the next run — append-only, committed by default (teammates inherit them),
  `.gitignore` the path if you'd rather keep them per-developer.

### Note on the port

These skills were ported from a private repo where they shipped a set of Python
modules. Those modules had **no CLI entrypoint** (importable libraries, never wired to
run), so shipping them would be dead code that violates the spirit of the bundled-script
convention (#8 — scripts must be invokable and `${CLAUDE_PLUGIN_ROOT}`-rooted). The
audit logic they described is now carried out by the model via `Glob`/`Grep`/`Read`,
which is simpler and removes the hardcoded `client/` source path.

## Shoals (project corrections)

When you correct a threshold, a token mapping, or a pattern you don't want flagged, the
skill records the lesson in `.claude/shoals/frontend-review.<skill>.md` in your project
and honors it next run. Append-only and committed by default; `.gitignore` it for
per-developer shoals.

## License

MIT
