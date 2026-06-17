# nautilai

> **nau·ti·lai** — a [Starfysh](https://starfysh.net) marketplace of Claude Code plugins:
> AI coding agents, skills, and commands.

## The name

*nautilai* layers a few meanings, on purpose:

- **nautilus + AI** — the spiral-shelled cephalopod with intelligence woven in; the
  navigator of the deep, here to navigate your codebase.
- **"many nautiluses"** — a playful (and gleefully incorrect) faux-Latin plural, the way
  *nautilus → nautili* might tempt you to say it out loud. This repo is a *collection*, so
  the plural fits: one shell per plugin.
- **nautical + lai** — a sea shanty for shipping software; tools that ride the
  [starfysh](https://github.com/starfysh-tech) tide.

Say it however feels right. They all point at the same thing: a growing reef of
well-crafted tools.

## Install a plugin

```text
/plugin marketplace add starfysh-tech/nautilai
/plugin install <plugin>@nautilai
```

After installing, reload plugins if prompted, then invoke the plugin's skill.

## Plugins

| Plugin | Description | Docs |
|---|---|---|
| **commitcraft** | AI git workflow toolkit — conventional commits, issue validation, PR creation, and release guidance. | [commitcraft/](./commitcraft/README.md) |

_More plugins will surface here over time._

## Repository layout

```text
nautilai/
├── .claude-plugin/
│   └── marketplace.json      # Marketplace catalog (lists every plugin)
├── commitcraft/              # One plugin = one top-level directory
│   ├── .claude-plugin/plugin.json
│   ├── skills/ scripts/ templates/
│   └── README.md
└── README.md                 # You are here
```

Each plugin is self-contained in its own directory with a `.claude-plugin/plugin.json`
manifest. The marketplace catalog at `.claude-plugin/marketplace.json` points at each one
by relative path.

## Contributing a plugin

1. Create a top-level directory named for the plugin (kebab-case).
2. Add `.claude-plugin/plugin.json` and the plugin's components (`skills/`, `commands/`,
   `agents/`, `hooks/`, etc.) at the plugin root.
3. Reference any bundled scripts, binaries, or config with `${CLAUDE_PLUGIN_ROOT}` — never
   a hardcoded path, since the install cache path changes on every update.
4. Register the plugin in `.claude-plugin/marketplace.json`.
5. Validate before pushing: `claude plugin validate ./<plugin> --strict`.

## License

MIT — see [LICENSE](./LICENSE).
