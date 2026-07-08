#!/usr/bin/env bash
# Every plugin.json must have exactly one matching entry in marketplace.json —
# same name, description, and version, and a source pointing at a real dir.
# A drift here ships a marketplace listing that lies about what's installed.
set -euo pipefail
shopt -s nullglob

cd "$(git rev-parse --show-toplevel)"

manifests=(*/.claude-plugin/plugin.json)
if [ ${#manifests[@]} -eq 0 ]; then
  echo "No plugin manifests found" >&2
  exit 1
fi

python3 - "${manifests[@]}" <<'PY'
import json
import os
import sys

manifest_paths = sys.argv[1:]

with open(".claude-plugin/marketplace.json") as f:
    marketplace = json.load(f)

entries = marketplace["plugins"]
by_source = {}
errors = []

for entry in entries:
    source = entry.get("source")
    if not source:
        errors.append(f"marketplace.json: entry {entry.get('name', 'unknown')!r} is missing 'source' field")
        continue
    by_source.setdefault(source, []).append(entry)

for source, group in by_source.items():
    if len(group) > 1:
        errors.append(f"marketplace.json: source {source!r} listed {len(group)} times, expected once")

seen_sources = set()

for path in manifest_paths:
    plugin_dir = "./" + path.split("/.claude-plugin/plugin.json")[0]
    seen_sources.add(plugin_dir)

    with open(path) as f:
        plugin = json.load(f)

    matches = by_source.get(plugin_dir, [])
    if not matches:
        errors.append(f"{path}: no marketplace.json entry with source {plugin_dir!r}")
        continue

    entry = matches[0]
    for field in ("name", "description", "version"):
        plugin_value = plugin.get(field)
        entry_value = entry.get(field)
        if plugin_value != entry_value:
            errors.append(
                f"{path}: {field} mismatch — plugin.json has {plugin_value!r}, "
                f"marketplace.json has {entry_value!r}"
            )

for source in by_source:
    if source not in seen_sources:
        if not os.path.isdir(source):
            errors.append(f"marketplace.json: source {source!r} does not exist on disk")
        else:
            errors.append(f"marketplace.json: source {source!r} is missing a plugin.json manifest")

# Two more surfaces a new plugin must register on, both mechanically checkable so a
# half-registered plugin can't ride a green build: its themed docs page, and the bug
# report form's plugin dropdown.
marketplace_names = {e.get("name") for e in entries if e.get("name")}

for name in sorted(marketplace_names):
    page = os.path.join("docs", "plugins", f"{name}.html")
    if not os.path.isfile(page):
        errors.append(f"marketplace.json: plugin {name!r} has no docs page {page!r}")

# bug.yml's plugin dropdown must list exactly the marketplace plugins. Hand-parse the
# one dropdown we care about (no PyYAML on the runner): find `id: plugin`, then its
# `options:` list, collecting items until the block dedents to the next key.
bug_form = os.path.join(".github", "ISSUE_TEMPLATE", "bug.yml")
if not os.path.isfile(bug_form):
    errors.append(f"{bug_form}: bug report form not found")
else:
    options, in_plugin, in_options = [], False, False
    with open(bug_form) as f:
        for raw in f:
            stripped = raw.strip()
            if stripped == "id: plugin":
                in_plugin = True
            elif in_plugin and not in_options and stripped == "options:":
                in_options = True
            elif in_options:
                if stripped.startswith("- "):
                    options.append(stripped[2:].strip())
                elif stripped and not stripped.startswith("#"):
                    break  # dedented to validations: — options list ended
    dropdown = set(options)
    for name in sorted(marketplace_names - dropdown):
        errors.append(f"{bug_form}: plugin dropdown is missing {name!r}")
    for name in sorted(dropdown - marketplace_names):
        errors.append(f"{bug_form}: plugin dropdown lists unknown plugin {name!r}")

if errors:
    for e in errors:
        print(f"MISMATCH: {e}", file=sys.stderr)
    print(f"\n{len(errors)} mismatch(es) found", file=sys.stderr)
    sys.exit(1)

print(f"OK: {len(manifest_paths)} plugin(s) in sync with marketplace.json")
PY
