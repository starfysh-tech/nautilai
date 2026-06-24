# CC Adoption Audit

Audit your current Claude Code setup against available features and get prioritized recommendations for what to adopt and which setup gaps to close.

Distributed as a plugin via the [**nautilai**](../README.md) marketplace.

## Install

```text
/plugin marketplace add starfysh-tech/nautilai
/plugin install cc-adoption-audit@nautilai
```

## Use

```text
/cc-adoption-audit
```

User-invoked only — the agent won't auto-fire it.

## What it does

1. **Reads your setup and stack** — inspects your Claude Code configuration (settings, hooks, permissions), the plugins, skills, and MCP servers you have installed, and the project's stack (languages, frameworks, tooling) to build a profile of how you work today.
2. **Compares against available CC features** — anchors on the official docs index (`llms.txt`) so the feature surface is authoritative and never stale, then maps your profile to the capabilities you could be using but aren't. It also checks your installed Claude Code version against the latest release.
3. **Outputs prioritized recommendations** — a report with three threads: **adoption** (features and plugins worth picking up, ranked by fit and payoff), **setup** (configuration gaps worth closing), and **what's new** (features shipped in the last ~30 days you haven't adopted yet) — each with the exact command or config to act on it.

It recommends what to adopt and where setup is incomplete; it makes no "remove unused" claims and won't tell you to tear anything out.

## Shoals (project corrections)

This plugin deliberately does **not** use the shoals convention (auto-captured
project corrections). It's a one-shot, full-repo audit — there's no run-to-run
behavior for a project to accumulate corrections against.

## License

MIT
