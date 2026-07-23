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

7. **Add an entry to the docs index** — `docs/index.html` renders the plugin directory
   from a **JavaScript object registry**, not hand-written markup. Append one object to
   that array (it sits just above the `FILTERLABEL` map), copying an existing entry's
   shape rather than writing HTML:

```js
{id:'<name>',cat:'<Audit & validate|Git & PRs|Context & planning|Security>',cf:'<audit|git|context|security>',tag:'<short-tag>',desc:'…',badges:['…','…'],install:'/plugin install <name>@nautilai',run:'/<primary-command>',runNote:'<what that run does>',more:['/<other>','/<other>'],docs:'plugins/<name>.html'},
```

   `cat` is the human label and `cf` its filter key — they must correspond via
   `FILTERLABEL`, or the entry vanishes when that filter is active. Omit `more` for a
   single-command plugin. Every command string carries its leading `/`; the copy buttons
   are generated from these values, so a missing slash ships a broken copy-to-clipboard.
   Also add the plugin to the footer link list (plain `<a href="plugins/<name>.html">`).

8. **Generate the themed docs page** — create `docs/plugins/<name>.html` from
   `docs/plugins/_TEMPLATE.html`, filling every slot per `docs/plugins/_slots.md`
   (source the copy from the plugin's `README.md` and `plugin.json`, not the
   marketplace one-liner). **CI requires this page** — `check-marketplace-sync.sh`
   fails if a marketplace entry has no `docs/plugins/<name>.html`.

9. **Register in the bug-report form** — append the new `<name>` to the plugin
   `dropdown` `options` in `.github/ISSUE_TEMPLATE/bug.yml`. **CI requires this** —
   `check-marketplace-sync.sh` asserts the dropdown lists exactly the marketplace
   plugins, so a new plugin isn't reportable until it's here.

10. **Add a row to the root README plugin table** — append one row to the table under
    `## Plugins` in the repo-root `README.md`, keeping it in the same order as
    `marketplace.json`: `| **<name>** | <one-line description> | `/plugin install
    <name>@nautilai` | [<name>/](./<name>/README.md) |`. **Not CI-enforced** — unlike the
    docs page and the bug-report dropdown, nothing checks this table, so it drifts
    silently if you skip it (it fell eight plugins behind once). It is the human-facing
    index; `marketplace.json` stays the canonical registry.

11. **Validate**:

```bash
claude plugin validate ./<name> --strict
jq -e . .claude-plugin/marketplace.json
jq -e . release-please-config.json
python3 -c "from html.parser import HTMLParser; HTMLParser().feed(open('docs/index.html').read())"  # page parses
bash .github/scripts/check-marketplace-sync.sh  # docs page + dropdown + version sync
```

12. Report the created files and remind: commit with a `feat:` conventional commit (release-please will bump the linked version on release).
