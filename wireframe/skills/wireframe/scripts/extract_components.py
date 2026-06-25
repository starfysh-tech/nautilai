#!/usr/bin/env python3
"""
List a project's React/TSX components so a wireframe can reference real
component names instead of inventing them.

Stdlib only; Python 3.10+. Repo-agnostic — point it at whatever directory
holds your components. Prints a Markdown catalog to stdout (default) or JSON.

Usage:
    python3 extract_components.py [COMPONENTS_DIR]
    python3 extract_components.py src/components --json
    python3 extract_components.py --help

Exits 0 with an empty catalog (not an error) when the directory is absent,
so callers can fail open: no components found just means "wireframe freehand".
"""

import argparse
import json
import re
import sys
from pathlib import Path

# (regex, name-group, props-group-or-None) — first match wins per file.
COMPONENT_PATTERNS = [
    (r"export const (\w+):\s*React\.FC(?:<(\w+)>)?", 1, 2),
    (r"export default function (\w+)", 1, None),
    (r"export function (\w+)", 1, None),
    # PascalCase arrow components: `export const Foo = (props) => …` / `const Foo = _ => …`
    (r"export const ([A-Z]\w+)\s*=\s*(?:\([^)]*\)|_|\w+)\s*=>", 1, None),
    (r"const ([A-Z]\w+)\s*=\s*(?:\([^)]*\)|_|\w+)\s*=>", 1, None),
    (r"const (\w+):\s*React\.FC(?:<(\w+)>)?", 1, 2),
    (r"const (\w+)\s*=\s*forwardRef", 1, None),
    (r"export const (\w+)\s*=\s*forwardRef", 1, None),
]

CATEGORY_RULES = [
    ("Navigation", lambda _, n: any(k in n for k in ("nav", "sidebar", "topnav"))),
    ("Data Display", lambda _, n: any(k in n for k in ("table", "list"))),
    ("Overlays", lambda _, n: any(k in n for k in ("modal", "dialog", "drawer"))),
    ("Form Controls", lambda _, n: any(k in n for k in ("input", "select", "checkbox", "radio", "password", "search", "form", "field"))),
    ("Actions", lambda _, n: "button" in n),
    ("Feedback", lambda _, n: any(k in n for k in ("alert", "error", "empty", "spinner", "toast", "loading"))),
    ("Layout", lambda _, n: any(k in n for k in ("header", "footer", "logo", "layout", "container", "grid"))),
]

ORDERED_CATS = [
    "Navigation", "Layout", "Data Display", "Form Controls",
    "Actions", "Overlays", "Feedback", "Other",
]


def categorize(file_path: Path, name: str) -> str:
    path_str = str(file_path).lower()
    name_lower = name.lower()
    for cat, rule in CATEGORY_RULES:
        if rule(path_str, name_lower):
            return cat
    return "Other"


def extract_component_info(file_path: Path, root: Path) -> dict | None:
    try:
        content = file_path.read_text(encoding="utf-8")
    except (FileNotFoundError, PermissionError, UnicodeDecodeError) as e:
        print(f"Warning: skipping {file_path}: {e}", file=sys.stderr)
        return None

    name = props = None
    match = None
    for pattern, name_grp, props_grp in COMPONENT_PATTERNS:
        match = re.search(pattern, content)
        if match:
            name = match.group(name_grp)
            props = match.group(props_grp) if props_grp and len(match.groups()) >= props_grp else None
            break
    if not name or match is None:
        return None

    # First line of the JSDoc block immediately preceding the component (not the
    # file-level header comment, which a whole-file search would match first).
    description = None
    preceding = content[:match.start()]
    jsdoc_blocks = list(re.finditer(r"/\*\*\s*\n((?:\s*\*[^\n]*\n)+)\s*\*/", preceding))
    if jsdoc_blocks:
        raw = re.sub(r"^\s*\*\s*", "", jsdoc_blocks[-1].group(1).strip(), flags=re.MULTILINE).strip()
        description = raw.split("\n")[0] if raw else None

    return {
        "name": name,
        "file": str(file_path.relative_to(root)),
        "props_type": props,
        "description": description,
        "category": categorize(file_path, name),
    }


def generate_markdown(components: list[dict]) -> str:
    by_cat: dict[str, list[dict]] = {}
    for comp in components:
        by_cat.setdefault(comp["category"], []).append(comp)

    md = f"**Total components**: {len(components)}\n"
    for cat in ORDERED_CATS:
        if cat not in by_cat:
            continue
        md += f"\n### {cat} ({len(by_cat[cat])})\n\n"
        for comp in sorted(by_cat[cat], key=lambda c: c["name"]):
            md += f"**{comp['name']}**\n- File: `{comp['file']}`\n"
            if comp["props_type"]:
                md += f"- Props: `{comp['props_type']}`\n"
            if comp["description"]:
                md += f"- Description: {comp['description']}\n"
            md += "\n"
    return md


def main() -> int:
    parser = argparse.ArgumentParser(description="List React/TSX components for wireframing")
    parser.add_argument("components_dir", nargs="?", default="src/components",
                        help="Directory to scan for *.tsx components (default: src/components)")
    parser.add_argument("--json", action="store_true", help="Emit JSON instead of Markdown")
    args = parser.parse_args()

    root = Path.cwd()
    components_dir = (root / args.components_dir).resolve()

    # Fail open: an absent dir is "no catalog", not an error.
    if not components_dir.exists():
        if args.json:
            print("[]")
        else:
            print(f"No components directory at {args.components_dir} — wireframe without a component catalog.")
        return 0

    components = []
    for ext in ("*.tsx", "*.jsx"):
        for comp_file in components_dir.rglob(ext):
            info = extract_component_info(comp_file, root)
            if info:
                components.append(info)
    components.sort(key=lambda c: c["file"])

    if args.json:
        print(json.dumps(components, indent=2))
    else:
        print(generate_markdown(components))
    return 0


if __name__ == "__main__":
    sys.exit(main())
