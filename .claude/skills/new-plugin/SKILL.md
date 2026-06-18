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

   (No `CHANGELOG.md` — release-please generates it on the first release.)

   **Versioning is linked**, not independent: every plugin shares the repo's single
   release-please version. Read the current version from `.release-please-manifest.json`
   (`["."]`) and use that exact value for `<version>` below — do **not** start a new plugin
   at `0.1.0`. Install granularity comes from separate `marketplace.json` entries, not from
   per-plugin version numbers.

3. **Write `<name>/.claude-plugin/plugin.json`** matching the existing convention (mirror `commitcraft/.claude-plugin/plugin.json`), with `<version>` = the current repo version:

```json
{
  "$schema": "https://json.schemastore.org/claude-code-plugin-manifest.json",
  "name": "<name>",
  "displayName": "<DisplayName>",
  "version": "<version>",
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
  "version": "<version>",
  "author": { "name": "Randall Noval" },
  "homepage": "https://github.com/starfysh-tech/nautilai/tree/main/<name>#readme",
  "license": "MIT"
}
```

6. **Wire release-please versioning** — in `release-please-config.json`, append two
   `extra-files` entries to the `.` package so the linked version syncs into the new files
   on every release (paths are repo-root-relative; `plugins[N]` is the new entry's index in
   `marketplace.json`):

```json
{ "type": "json", "path": "<name>/.claude-plugin/plugin.json", "jsonpath": "$.version" },
{ "type": "json", "path": ".claude-plugin/marketplace.json", "jsonpath": "$.plugins[N].version" }
```

   release-please merges multiple `extra-files` targeting the same file (`marketplace.json`)
   via a `CompositeUpdater`, so two jsonpaths into one file is supported.

7. **Add a card to the docs page** — in `docs/index.html`, copy the `<div class="feature">`
   block of an existing plugin and adapt it: heading, description, badges, the
   `handoff#readme`-style docs link, and a `feature-term` with copy-fields. Give each command
   its own `.copyfield` with a `.copy-btn` whose `data-copy` is the **exact** command
   (including the leading `/`) — including a `/plugin install <name>@nautilai` field so users
   never have to substitute a placeholder. Also add the plugin to the footer link list.

8. **Validate**:

```bash
claude plugin validate ./<name> --strict
jq -e . .claude-plugin/marketplace.json
jq -e . release-please-config.json
python3 -c "from html.parser import HTMLParser; HTMLParser().feed(open('docs/index.html').read())"  # page parses
```

9. Report the created files and remind: commit with a `feat:` conventional commit (release-please will bump the linked version on release).
