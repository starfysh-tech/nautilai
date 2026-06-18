---
name: new-plugin
description: Scaffold a new plugin in this nautilai marketplace — creates the plugin directory, manifest, skill skeleton, and registers it in marketplace.json. Use when adding a new plugin to the repo, or when the user says "new plugin", "scaffold a plugin", or "/new-plugin <name>".
disable-model-invocation: true
---

# Scaffold a new marketplace plugin

Create a new plugin in this repo and register it. Plugin name comes from `$ARGUMENTS` (kebab-case). If missing, ask for it.

## Steps

1. **Validate the name**: kebab-case, not already a directory at repo root, and not already in `.claude-plugin/marketplace.json`. Stop if it collides.

2. **Create the structure** under `<name>/`:
   - `<name>/.claude-plugin/plugin.json`
   - `<name>/skills/<name>/SKILL.md`
   - `<name>/README.md`
   - `<name>/CHANGELOG.md`

3. **Write `<name>/.claude-plugin/plugin.json`** matching the existing convention (mirror `commitcraft/.claude-plugin/plugin.json`):

```json
{
  "$schema": "https://json.schemastore.org/claude-code-plugin-manifest.json",
  "name": "<name>",
  "displayName": "<DisplayName>",
  "version": "0.1.0",
  "description": "<one-line description>",
  "author": { "name": "Randall Noval", "email": "randall@starfysh.net", "url": "https://github.com/starfysh-tech" },
  "homepage": "https://github.com/starfysh-tech/nautilai/tree/main/<name>#readme",
  "repository": "https://github.com/starfysh-tech/nautilai",
  "license": "MIT",
  "keywords": ["claude-code"],
  "skills": "./skills/"
}
```

4. **Write `<name>/skills/<name>/SKILL.md`** with valid frontmatter (`name`, `description`) and a short body describing what it does.

5. **Register in `.claude-plugin/marketplace.json`** — append to the `plugins` array, keeping `name`, `version`, and `description` identical to `plugin.json`:

```json
{
  "name": "<name>",
  "source": "./<name>",
  "description": "<same description>",
  "version": "0.1.0",
  "author": { "name": "Randall Noval" },
  "homepage": "https://github.com/starfysh-tech/nautilai/tree/main/<name>#readme",
  "license": "MIT"
}
```

6. **Validate**:

```bash
claude plugin validate ./<name> --strict
jq -e . .claude-plugin/marketplace.json
```

7. Report the created files and remind: commit with a `feat:` conventional commit (release-please will set the real version on release).
