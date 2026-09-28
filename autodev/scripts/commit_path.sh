#!/usr/bin/env bash
# Pick how autodev commits in <repo-root>: prints `commitcraft` when the
# CommitCraft plugin is installed for this repo (user scope, or project scope
# for this exact path), else `script` (commit_lane.sh). Logs the reason on
# stderr. installed_plugins.json is not a documented interface, so any read or
# parse problem falls back to `script`, which runs the same hooks.
#   commit_path.sh <repo-root>
set -uo pipefail
ROOT="${1:?repo root required}"
python3 - "$HOME/.claude/plugins/installed_plugins.json" "$ROOT" <<'PY'
import json, os, sys
path, root = sys.argv[1], os.path.realpath(sys.argv[2])
# Capability, not version: an older CommitCraft stages every changed file.
def supports_files(entry):
    try:
        with open(os.path.join(entry["installPath"], "skills/commitcraft/workflows/commit.md")) as f:
            return "--files" in f.read()
    except (OSError, KeyError, TypeError):
        return False

def installed(data):
    for name, entries in data["plugins"].items():
        if not name.startswith("commitcraft@"):
            continue
        for e in entries if isinstance(entries, list) else [entries]:
            scope = e["scope"]
            if scope == "user" or (scope == "project" and os.path.realpath(e["projectPath"]) == root):
                if supports_files(e):
                    return f"{name} installed ({scope} scope, {e.get('version', '?')}) with commit --files"
                print(f"commit_path: {name} ({scope} scope, {e.get('version', '?')}) has no commit --files", file=sys.stderr)
    return None

try:
    with open(path) as f:
        found = installed(json.load(f))
except Exception as e:  # any shape change: fall back, never crash the commit step
    print(f"commit_path: cannot read {path} ({e.__class__.__name__}); using commit_lane.sh", file=sys.stderr)
    print("script")
    sys.exit(0)
if found:
    print(f"commit_path: {found}; using /commitcraft commit", file=sys.stderr)
    print("commitcraft")
else:
    print("commit_path: no CommitCraft with commit --files for this repo; using commit_lane.sh", file=sys.stderr)
    print("script")
PY
