# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

`nautilai` is a **Claude Code plugin marketplace** — not a buildable app. Each plugin is one top-level directory; there is no root package manager, build step, or test suite. Plugins are distributed via `/plugin install`, not compiled.

## Layout

- `.claude-plugin/marketplace.json` — marketplace catalog; every plugin must be listed in its `plugins` array.
- `<plugin>/.claude-plugin/plugin.json` — per-plugin manifest.
- `<plugin>/skills/<name>/SKILL.md` + `workflows/*.md` — skill definitions.
- `<plugin>/{scripts,templates}/` — bundled shell scripts and config templates copied into end-user repos.

Adding a plugin means creating its directory **and** registering it in `marketplace.json`. Keep `name` and `description` in sync between `plugin.json` and the marketplace entry; the `version` is kept in sync automatically by release-please `extra-files` (add an entry for the new plugin's `plugin.json` and its `marketplace.json` index — the `.claude/skills/new-plugin` skill scaffolds all of this).

## Conventions

House conventions for authoring plugins — patterns we hold across plugins that
aren't covered by Anthropic's skill guidance or this file — live in
[`docs/conventions/`](docs/conventions/README.md). Notably, every review/audit
skill follows the [finding-dispositions](docs/conventions/finding-dispositions.md)
standard (`auto-fix` / `report` / `ask-user`). Check a new plugin against these,
or note a deliberate exception in its README.

## Validation

Before pushing plugin changes, validate the manifest:

```bash
claude plugin validate ./<plugin> --strict
```

## Versioning

Versions are managed by **release-please** — this repo's own config is the root `release-please-config.json` + `.release-please-manifest.json`. All plugins share one **linked** repo version: release-please's `extra-files` entries fan each bump into every `plugin.json` and its `marketplace.json` entry. Do not hand-edit the `version` field to cut a release — let release-please bump it from conventional commits.

> Note: `commitcraft/templates/release-please-config.json` is a *template CommitCraft ships into end-user repos* during `setup` — it is **not** nautilai's own release config. Don't edit it to manage this repo's versions.

## Commit & git conventions

This repo follows the CommitCraft conventions it ships (see `commitcraft/README.md`):

- **Conventional Commits**: `<type>(<scope>): <subject>` — types `feat|fix|docs|style|refactor|test|chore|perf|ci|revert`; imperative, lowercase subject ≤50 chars, no emoji, no attribution footers (`Co-Authored-By`, etc.).
- **Stage files individually** with `git add <file>` — never `git add -A`.
- **Never use `--no-verify`.** Hook failures (gitleaks secrets, commitlint, tests) are hard stops, not bypasses. Auto-fixers (prettier/eslint) are soft blocks — re-stage and retry.
- **Pre-commit hooks take 60–90s** — run them in the foreground and wait; never background them.
- **Branch from `main`**: branches are `<type>/<slugified-subject>[-<issue>]`. PR titles use Conventional Commits.
- Prefer the CommitCraft skill / `mcp__github__*` tools over raw git/`gh` for commits and PRs.
