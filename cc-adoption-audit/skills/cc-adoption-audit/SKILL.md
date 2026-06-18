---
name: cc-adoption-audit
description: Audit your Claude Code setup against available features and surface what you're not using but should, plus setup gaps. User-invoked — run /cc-adoption-audit; the agent will not auto-fire it.
allowed-tools: Read, Glob, Grep, Bash, WebFetch
disable-model-invocation: true
---

# CC Adoption Audit

You are running an adoption audit: compare what this user has set up against the **available** Claude Code feature surface, then recommend what to adopt and which setup gaps to close. Be focused and actionable — this is a prioritized audit, not an exhaustive feature dump. It covers both what you should adopt from the full feature surface **and** what shipped recently that you haven't picked up yet.

## Anti-hallucination rule

Every feature you describe as "available" must come from a source you actually fetched in Step 1. If you cannot find it there, mark it `[unverified]` — never invent features, versions, dates, or behavior. Likewise, base "the user has X" on config you actually read in Step 2; if a path doesn't resolve, say "not found" — do not assume absence means the feature is unused.

## Step 1 — What's available (feature surface + freshness)

1. `WebFetch https://code.claude.com/docs/llms.txt` — the authoritative, self-updating docs index. Parse each line of the form `- [title](url): description` into your feature inventory. The titles + descriptions alone usually enumerate the surface; this is your anti-hallucination anchor.
2. Drill into specific pages only when you need detail to justify a recommendation (use the `.md` form):
   `features-overview.md`, `slash-commands.md`, `hooks.md`, `skills.md`, `settings.md`, `plugins-reference.md`, `changelog.md`, `whats-new/index.md` under `https://code.claude.com/docs/en/`.
3. Freshness + recent window:
   - `WebFetch https://api.github.com/repos/anthropics/claude-code/releases?per_page=30` → the newest entry's `tag_name` + `published_at` is the latest available version; entries with `published_at` within the last ~30 days of today are the **recent launches**.
   - `claude --version` (Bash) → the user's installed version. **Comparing the user's version to latest is itself a finding** — flag it if they're behind.
4. Recent launch detail: `WebFetch https://raw.githubusercontent.com/anthropics/claude-code/refs/heads/main/CHANGELOG.md` → the per-version feature bullets. Map the in-window versions from step 3 to their changelog entries to get the feature text for the "What's new" section. (Stateless: always the last ~30 days — no per-run memory.)

## Step 2 — What you have (this environment)

First resolve the absolute home directory (`echo "$HOME"` via Bash, or `%USERPROFILE%` on Windows) — Read/Glob/Grep require absolute paths and do **not** expand `~` or `$HOME`. Use that resolved path for every read below. Report what's missing as "not found", never as silent absence. Config lives under `<home>/.claude/` on macOS/Linux and `%USERPROFILE%\.claude\` on Windows.

- **Global config:** `<home>/.claude/settings.json`, `<home>/.claude/CLAUDE.md`, `<home>/.claude.json` (user-level plugins/MCP live here).
- **Project config:** `.claude/settings.json`, `.claude/settings.local.json`, `./CLAUDE.md`, `./CLAUDE.local.md`.
- **Installed extensions:** dirs under `<home>/.claude/plugins/`, `<home>/.claude/skills/`, `<home>/.claude/commands/`, `<home>/.claude/agents/`, and the project's `.claude/skills|commands|agents/`.
- **MCP servers:** entries in `<home>/.claude.json` and project `.mcp.json`.
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
- **What's new (last ~30 days)** — notable features from the recent launches (Step 1.3–1.4) as *feature → why it matters → how to use it*. Cross-reference Step 2 and **highlight the ones you haven't adopted yet** — those are also adoption candidates. Keep it to high-impact items, not a full changelog dump; if nothing notable shipped in the window, say so in one line.
- **Freshness** — "Audited against Claude Code `<tag_name>` (published `<published_at>`); your version: `<claude --version>`. Docs index + changelog fetched today."

End by offering to set up any of the recommendations.
