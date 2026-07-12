# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

`nautilai` is a **Claude Code plugin marketplace** — not a buildable app. Each plugin is one top-level directory; there is no root package manager, build step, or test suite. Plugins are distributed via `/plugin install`, not compiled.

## Layout

- `.claude-plugin/marketplace.json` — marketplace catalog; every plugin must be listed in its `plugins` array.
- `<plugin>/.claude-plugin/plugin.json` — per-plugin manifest.
- `<plugin>/skills/<name>/SKILL.md` + `workflows/*.md` — skill definitions.
- `<plugin>/{scripts,templates}/` — bundled shell scripts and config templates copied into end-user repos.

Reference any bundled script, binary, or config from a skill/workflow with
`${CLAUDE_PLUGIN_ROOT}/…`, never a hardcoded path — the install cache path changes
on every plugin update, so a literal path breaks after the next release.

Adding a plugin means creating its directory **and** registering it in `marketplace.json`. A plugin's identity is one invariant across five surfaces that must stay consistent: `plugin.json`, the `marketplace.json` entry (`name`, `description`, and `version` are CI-enforced by `.github/scripts/check-marketplace-sync.sh`), the skill's `SKILL.md` frontmatter description (semantically consistent, not verbatim — it's the model-facing trigger), the plugin's docs page `docs/plugins/<name>.html` (regenerated per `docs/plugins/_slots.md`), and its entry in `docs/llms.txt` (the agent-facing index — say which runtimes it supports). The `version` field itself is kept in sync automatically by release-please `extra-files` (add an entry for the new plugin's `plugin.json` and its `marketplace.json` index — the `.claude/skills/new-plugin` skill scaffolds all of this).

## Conventions

House conventions for authoring plugins — patterns we hold across plugins that
aren't covered by Anthropic's skill guidance or this file — live in
[`docs/conventions/`](docs/conventions/README.md). Notably, every review/audit
skill follows the [finding-dispositions](docs/conventions/finding-dispositions.md)
standard (`auto-fix` / `report` / `ask-user`). Check a new plugin against these,
or note a deliberate exception in its README.

## Agent-facing docs

`docs/llms.txt` ([llmstxt.org](https://llmstxt.org/)) is the **agent-facing** index of the
marketplace, served at `starfysh-tech.github.io/nautilai/llms.txt`. It is deliberately
*separate* from the human docs pages — never bury agent guidance inside
`docs/plugins/*.html`.

A new plugin must be added there too (see the surface list above). Its "Notes for agents"
section carries the non-obvious runtime facts an agent would otherwise have to rediscover
(e.g. `hermes skills tap add` indexes nothing; Hermes strips the executable bit) — keep it
short and keep it true.

> We do **not** publish `/.well-known/agent-skills/index.json`. Two incompatible specs are
> live (Hermes reads the older `/.well-known/skills/` path, single-file skills only; the
> agentskills.io RFC renamed it and is still at 0.2.0), and skills.sh already distributes
> these skills *with* their bundled scripts. Revisit when the RFC settles.

## Hermes Agent (dual-runtime)

CommitCraft and the review skills also install into **Hermes Agent** via skills.sh
(`hermes skills install skills-sh/starfysh-tech/nautilai/<skill>`). Hermes ships the
**skill directory only**, so a plugin's root-level `scripts/` and `templates/` would not
reach it.

`hermes/sync-resources.sh` mirrors them into the skill dir. **The plugin-root copies stay
the source of truth and are what Claude Code uses** — the mirror under
`commitcraft/skills/commitcraft/{scripts,templates}/` is **generated**, inert to Claude, and
CI-gated (`hermes/sync-resources.sh --check`). Never hand-edit it; edit the plugin-root copy
and re-run the script.

Hermes support must stay **additive** — no Claude Code path, manifest, script, or test
changes. A skill serves both runtimes via a "Resource paths" adapter section naming
`${CLAUDE_PLUGIN_ROOT}` and `${HERMES_SKILL_DIR}`; each runtime resolves only its own token
and ignores the other. `autodev` is Claude-only (no Hermes subagent primitive).

The rules, and the lessons behind them (including which published Hermes docs proved wrong),
are in [`docs/conventions/dual-runtime.md`](docs/conventions/dual-runtime.md). Read it before
porting another plugin.

## Validation

Every PR runs `claude plugin validate --strict` over **all** plugins via the
`validate` workflow (`.github/workflows/validate.yml`), and it's a **required
status check** on `main` — a malformed manifest or skill can't merge. Run the same
check locally before pushing:

```bash
claude plugin validate ./<plugin> --strict
```

Bundled scripts that have logic worth testing carry a self-contained bash suite
(currently `commitcraft/` and `autodev/`). Run them directly — they build
throwaway fixtures (commitcraft stubs `gh`), so they're offline and
side-effect-free:

```bash
bash commitcraft/tests/detect-rp.test.sh
bash autodev/tests/scripts.test.sh
```

## Versioning

Versions are managed by **release-please** — this repo's own config is the root `release-please-config.json` + `.release-please-manifest.json`. All plugins share one **linked** repo version: release-please's `extra-files` entries fan each bump into every `plugin.json` and its `marketplace.json` entry. Do not hand-edit the `version` field to cut a release — let release-please bump it from conventional commits.

Releases are **fully automated** (`.github/workflows/release-please.yml`): a push to
`main` opens (or updates) a release PR, which **auto-merges once required checks
pass** — publishing the tag + GitHub Release with no manual step. Merging a
`feat:`/`fix:` PR is all it takes to ship. The workflow runs under a
`RELEASE_PLEASE_TOKEN` PAT rather than `GITHUB_TOKEN` so the release PR's checks
actually run and the merge re-triggers the release; if releases stop publishing,
check that secret first.

> Note: `commitcraft/templates/release-please-config.json` is a *template CommitCraft ships into end-user repos* during `setup` — it is **not** nautilai's own release config. Don't edit it to manage this repo's versions.

## Plugin changelog

`docs/plugin-changelog.md` is a **hand-curated** log of major, user-visible plugin
changes (new plugin/skill/subcommand, a convention adopted, a behavior change).
It is **separate from** the root `CHANGELOG.md`, which release-please generates
per-release from commits — never hand-edit that one.

Update `docs/plugin-changelog.md` when a change is worth a human skim, in the same
PR that makes the change:

- Add entries under a `## <YYYY-MM-DD>` heading (newest at top; reuse the heading if one exists for today).
- One bullet per change; name the plugin(s) affected and link the relevant doc/skill.
- **Lead with the *why*, not the *what*.** The diff already shows what changed;
  this file records the motivation — the problem it solved or the decision behind
  it. A bullet a reader could regenerate from the commit subject isn't worth
  adding. (The commit *bodies* are the source for this — mine them, don't restate
  subjects.)
- Skip routine churn (typo fixes, dep bumps, internal refactors) — those live in
  the release `CHANGELOG.md` via commits. This log is **plugins only**; marketing
  site / docs-page changes don't belong here.

This repo follows the CommitCraft conventions it ships (see `commitcraft/README.md`):

- **Conventional Commits**: `<type>(<scope>): <subject>` — types `feat|fix|docs|style|refactor|test|chore|perf|ci|revert`; imperative, lowercase subject ≤72 chars, no emoji, no attribution footers (`Co-Authored-By`, etc.).
- **Stage files individually** with `git add <file>` — never `git add -A`.
- **Never use `--no-verify`.** Hook failures (gitleaks secrets, commitlint, tests) are hard stops, not bypasses. Auto-fixers (prettier/eslint) are soft blocks — re-stage and retry.
- **Pre-commit hooks take 60–90s** — run them in the foreground and wait; never background them.
- **Branch from `main`**: branches are `<type>/<slugified-subject>[-<issue>]`. PR titles use Conventional Commits.
- **Commits and PRs go through CommitCraft** (`/commitcraft commit`, `/commitcraft pr`) — never raw `git commit`/`gh pr create`, even when following its conventions by hand. Prefer `mcp__github__*` over `gh` for other GitHub operations.
