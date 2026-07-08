#!/usr/bin/env python3
"""
List a project's React/TSX components so a wireframe can reference real
component names instead of inventing them, and (optionally) inject that catalog
into the skill's reference doc.

Stdlib only; Python 3.10+. Repo-agnostic — point it at whatever directory holds
your components. Prints a Markdown catalog to stdout (default), JSON, writes a
JSON file, or updates a reference doc in place.

Usage:
    python3 extract_components.py [COMPONENTS_DIR]
    python3 extract_components.py src/components --json
    python3 extract_components.py client/src/components --output catalog.json
    python3 extract_components.py src/components --update-reference
    python3 extract_components.py src/components --update-reference --reference path/to/reference.md
    python3 extract_components.py --help

Exits 0 with an empty catalog (not an error) when the directory is absent, so
callers can fail open: no components found just means "wireframe freehand".
"""

import argparse
import json
import re
import sys
from datetime import datetime
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

# (category, predicate(path_str_lower, name_lower)) — first match wins, in order.
# Notifications and Communication intentionally precede Overlays/Other so that
# notification-drawer and chat/message components land in their own buckets.
CATEGORY_RULES = [
    ("Navigation", lambda _, n: any(k in n for k in ("nav", "sidebar", "topnav"))),
    ("Notifications", lambda p, n: "notification" in p or "notification" in n or ("drawer" in n and "notif" in p)),
    ("Data Display", lambda _, n: any(k in n for k in ("table", "list"))),
    ("Overlays", lambda _, n: any(k in n for k in ("modal", "dialog", "drawer"))),
    ("Form Controls", lambda _, n: any(k in n for k in ("input", "select", "checkbox", "radio", "password", "search", "form", "field"))),
    ("Actions", lambda _, n: "button" in n),
    ("Feedback", lambda _, n: any(k in n for k in ("alert", "error", "empty", "spinner", "toast", "loading"))),
    ("Communication", lambda _, n: any(k in n for k in ("chat", "message"))),
    ("Layout", lambda _, n: any(k in n for k in ("header", "footer", "logo", "layout", "container", "grid"))),
]

ORDERED_CATS = [
    "Navigation", "Layout", "Data Display", "Form Controls", "Actions",
    "Overlays", "Notifications", "Feedback", "Communication", "Other",
]

# Default reference doc is project-local (relative to CWD), not the bundled
# skill doc — the bundled doc lives in the plugin install cache, which is
# shared across projects and wiped on every plugin update.
DEFAULT_REFERENCE = Path(".claude") / "wireframe-catalog.md"

CATALOG_START = "<!-- WIREFRAME-CATALOG-START -->"
CATALOG_END = "<!-- WIREFRAME-CATALOG-END -->"


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


def generate_markdown(components: list[dict], source_label: str | None = None,
                      include_timestamp: bool = False) -> str:
    """Markdown catalog. When source_label is given, prepend an auto-gen header
    line (with an optional timestamp) used by the --update-reference path."""
    by_cat: dict[str, list[dict]] = {}
    for comp in components:
        by_cat.setdefault(comp["category"], []).append(comp)

    md = ""
    if source_label is not None:
        if include_timestamp:
            ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            md += f"_Auto-generated from {source_label} - updated on commit ({ts})._\n\n"
        else:
            md += f"_Auto-generated from {source_label} - updated on commit._\n\n"

    md += f"**Total components**: {len(components)}\n"
    for cat in ORDERED_CATS:
        if cat not in by_cat:
            continue
        md += f"\n### {cat} ({len(by_cat[cat])})\n\n"
        for comp in sorted(by_cat[cat], key=lambda c: c["name"]):
            md += f"**{comp['name']}**\n- File: `{comp['file']}`\n"
            if comp["props_type"]:
                md += f"- Props: `{comp['props_type']}`\n"
            if comp["description"]:
                md += f"- {comp['description']}\n"
            md += "\n"
    return md


def update_reference_md(components: list[dict], reference_path: Path, source_label: str) -> bool:
    """Update the reference doc's catalog block (between the CATALOG markers) in
    place. Idempotent: re-stamps the timestamp only when the catalog content
    actually changed."""
    try:
        content = reference_path.read_text(encoding="utf-8")
    except FileNotFoundError:
        # The project-local catalog doesn't exist yet on first run — scaffold
        # it with the markers rather than erroring.
        content = f"# Wireframe Component Catalog\n\n{CATALOG_START}\n{CATALOG_END}\n"
        try:
            reference_path.parent.mkdir(parents=True, exist_ok=True)
        except OSError as e:
            print(f"Error creating {reference_path.parent}: {e}", file=sys.stderr)
            return False
    except OSError as e:
        print(f"Error reading {reference_path}: {e}", file=sys.stderr)
        return False

    if CATALOG_START not in content or CATALOG_END not in content:
        print(f"Error: Catalog markers not found in {reference_path}", file=sys.stderr)
        return False

    # Compare against existing content with the timestamp normalized out.
    catalog_no_ts = generate_markdown(components, source_label=source_label, include_timestamp=False)

    start_idx = content.find(CATALOG_START) + len(CATALOG_START)
    end_idx = content.find(CATALOG_END)
    existing_catalog = content[start_idx:end_idx]

    existing_no_ts = re.sub(
        re.escape(f"_Auto-generated from {source_label} - updated on commit (")
        + r"[^)]+" + re.escape(")._"),
        f"_Auto-generated from {source_label} - updated on commit._",
        existing_catalog,
    )

    if existing_no_ts.strip() == catalog_no_ts.strip():
        print("reference unchanged, skipping")
        return True

    catalog_md = generate_markdown(components, source_label=source_label, include_timestamp=True)
    new_content = content[:start_idx] + "\n\n" + catalog_md + "\n" + content[end_idx:]

    try:
        reference_path.write_text(new_content, encoding="utf-8")
        return True
    except OSError as e:
        print(f"Error writing {reference_path}: {e}", file=sys.stderr)
        return False


def main() -> int:
    parser = argparse.ArgumentParser(description="List React/TSX components for wireframing")
    parser.add_argument("components_dir", nargs="?", default="src/components",
                        help="Directory to scan for *.tsx/*.jsx components (default: src/components)")
    parser.add_argument("--json", action="store_true", help="Emit JSON to stdout instead of Markdown")
    parser.add_argument("--markdown", action="store_true", help="Force Markdown catalog to stdout (the default)")
    parser.add_argument("--output", default=None,
                        help="Also write the catalog as JSON to this file path")
    parser.add_argument("--update-reference", action="store_true",
                        help="Inject the catalog into the reference doc's CATALOG markers")
    parser.add_argument("--reference", default=None,
                        help=f"Reference doc to update (default: {DEFAULT_REFERENCE})")
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

    components: list[dict] = []
    skipped: list[str] = []
    for ext in ("*.tsx", "*.jsx"):
        for comp_file in components_dir.rglob(ext):
            info = extract_component_info(comp_file, root)
            if info:
                components.append(info)
            else:
                skipped.append(str(comp_file.relative_to(root)))
    components.sort(key=lambda c: c["file"])

    # --update-reference mode: inject into the reference doc and stop.
    if args.update_reference:
        reference_path = Path(args.reference).resolve() if args.reference else (Path.cwd() / DEFAULT_REFERENCE)
        ok = update_reference_md(components, reference_path, source_label=args.components_dir)
        if ok:
            print(f"✓ Updated {reference_path} with {len(components)} components")
            return 0
        return 1

    # Optional JSON file output.
    if args.output:
        output_path = Path(args.output)
        try:
            output_path.parent.mkdir(parents=True, exist_ok=True)
            output_path.write_text(json.dumps(components, indent=2), encoding="utf-8")
            print(f"✓ Saved {len(components)} components to {output_path}", file=sys.stderr)
        except OSError as e:
            print(f"Error writing to {output_path}: {e}", file=sys.stderr)
            return 1

    # Stdout: JSON if asked, otherwise the Markdown catalog.
    if args.json:
        print(json.dumps(components, indent=2))
    else:
        print(generate_markdown(components))

    if skipped:
        print(f"⚠ Skipped {len(skipped)} files (no component exports found)", file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())
