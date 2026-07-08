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

if errors:
    for e in errors:
        print(f"MISMATCH: {e}", file=sys.stderr)
    print(f"\n{len(errors)} mismatch(es) found", file=sys.stderr)
    sys.exit(1)

print(f"OK: {len(manifest_paths)} plugin(s) in sync with marketplace.json")
PY
