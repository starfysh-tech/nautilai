---
name: cc-adoption-audit
description: Audit your Claude Code setup against available features and surface what you're not using but should, plus setup gaps. User-invoked — run /cc-adoption-audit; the agent will not auto-fire it.
allowed-tools: Read, Glob, Grep, Bash, WebFetch
disable-model-invocation: true
---

# CC Adoption Audit

You are running an adoption audit: compare what this user has set up against the **available** Claude Code feature surface, then recommend what to adopt and which setup gaps to close. Be focused and actionable — this is a prioritized audit, not an exhaustive feature dump. For "what's new in Claude Code" specifically, point the user at `/explain-cc-changes`; this audit is about fit against what's available, not release notes.

## Anti-hallucination rule

Every feature you describe as "available" must come from a source you actually fetched in Step 1. If you cannot find it there, mark it `[unverified]` — never invent features, versions, dates, or behavior. Likewise, base "the user has X" on config you actually read in Step 2; if a path doesn't resolve, say "not found" — do not assume absence means the feature is unused.

## Step 1 — What's available (feature surface + freshness)

1. `WebFetch https://code.claude.com/docs/llms.txt` — the authoritative, self-updating docs index. Parse each line of the form `- [title](url): description` into your feature inventory. The titles + descriptions alone usually enumerate the surface; this is your anti-hallucination anchor.
2. Drill into specific pages only when you need detail to justify a recommendation (use the `.md` form):
   `features-overview.md`, `slash-commands.md`, `hooks.md`, `skills.md`, `settings.md`, `plugins-reference.md`, `changelog.md`, `whats-new/index.md` under `https://code.claude.com/docs/en/`.
3. Freshness stamp:
   - `WebFetch https://api.github.com/repos/anthropics/claude-code/releases/latest` → record `tag_name` + `published_at` (latest available version).
   - `claude --version` (Bash) → the user's installed version. **Comparing the user's version to latest is itself a finding** — flag it if they're behind.

## Step 2 — What you have (this environment)

Read these **directly** with Read/Glob/Grep (not shell text-munging). Report what's missing as "not found", never as silent absence. Config lives under `$HOME/.claude/` on macOS/Linux and `%USERPROFILE%\.claude\` on Windows.

- **Global config:** `~/.claude/settings.json`, `~/.claude/CLAUDE.md`, `~/.claude.json` (user-level plugins/MCP live here).
- **Project config:** `.claude/settings.json`, `.claude/settings.local.json`, `./CLAUDE.md`, `./CLAUDE.local.md`.
- **Installed extensions:** dirs under `~/.claude/plugins/`, `~/.claude/skills/`, `~/.claude/commands/`, `~/.claude/agents/`, and the project's `.claude/skills|commands|agents/`.
- **MCP servers:** entries in `~/.claude.json` and project `.mcp.json`.
- **Hooks:** the `hooks` block in the settings files.
- **Stack (generic, via Glob — do not assume Node):** `package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `pom.xml`, `Gemfile`, `.github/workflows/`, `Dockerfile`, plus any CI/deploy config present.

## Step 3 — Gap analysis

Cross-reference Step 1 (available) against Step 2 (configured). Base "already has it" on **config presence**, not usage frequency. Produce two threads:

- **Adoption gaps** — available features that fit this user's stack/workflow but aren't set up. For each: what it is (cite the fetched source), why it fits *them*, and the exact command/config to adopt it.
- **Setup gaps** — incomplete configuration: e.g. plugins installed but no hooks wired, MCP available but none configured, no project `CLAUDE.md`, or an installed CC version behind latest.

Do **not** make "remove unused" / "dead weight" recommendations — you don't have reliable usage data, and false removals are costly.

## Step 4 — Report

Keep it concise and prioritized:

- **Profile** — your CC version (vs latest), detected stack, and what's installed/configured.
- **Adoption recommendations** — ranked P1/P2/P3 by fit and payoff; each with the exact command/config to act on it.
- **Setup gaps** — ranked, each actionable.
- **Freshness** — "Audited against Claude Code `<tag_name>` (published `<published_at>`); your version: `<claude --version>`. Docs index fetched today. For what's new specifically, run `/explain-cc-changes`."

End by offering to set up any of the recommendations.
