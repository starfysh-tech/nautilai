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
3. **Outputs prioritized recommendations** — a report with two threads: **adoption** (features and plugins worth picking up, ranked by fit and payoff) and **setup** (configuration gaps worth closing), each ordered by priority, with the exact command or config to act on it.

It defers "what's new in Claude Code" to `/explain-cc-changes` — this audit is about fit against *available* features, not release notes. It recommends what to adopt and where setup is incomplete; it makes no "remove unused" claims and won't tell you to tear anything out.

## License

MIT
