# Plugins for Claude Code

**nautilai** is a [Starfysh](https://starfysh.net) marketplace of Claude Code
plugins — AI coding agents, skills, and commands. One spiral shell per plugin.

## Install

Add the marketplace once, then install any plugin from it:

```text
/plugin marketplace add starfysh-tech/nautilai
/plugin install <plugin>@nautilai
```

Reload plugins if prompted, then invoke the plugin's skill.

## Plugins

| Plugin | What it does |
|---|---|
| [**commitcraft**](https://github.com/starfysh-tech/nautilai/tree/main/commitcraft#readme) | AI git workflow toolkit — conventional commits, issue validation, PR creation, branch-protection provisioning, and release guidance. |

*More plugins will surface here over time.*

## commitcraft, at a glance

```text
/commitcraft commit     # AI-generated conventional commit
/commitcraft push       # commit + push with issue tracking
/commitcraft pr         # PR with an AI-generated description
/commitcraft release    # semantic version bump + release notes
/commitcraft setup      # configure tooling (runs in chat)
/commitcraft check      # validate configuration
```

## Links

- [Source on GitHub](https://github.com/starfysh-tech/nautilai)
- [commitcraft README](https://github.com/starfysh-tech/nautilai/tree/main/commitcraft#readme)
- [Starfysh](https://starfysh.net)
