#!/usr/bin/env python3
"""
Discover the current RBAC platform context by reading the codebase.

Auto-detects the Django backend layout rather than assuming a fixed path —
it locates the directory tree containing ``manage.py`` (or falls back to the
project root) and discovers permission classes, group/permission setup, PHI
filtering, and role docs from whatever the repo actually uses.

Stdlib-only: uses Python's ``ast`` module for structural discovery, so it runs
on a clean machine with no install step. Emits JSON to stdout for the
rbac-remediation-playbooks skill.

Requirements:
    - Python 3.10+ (standard library only)
    - Run from the project root, or pass the project root as the one argument.

Exit codes:
    0 — success, JSON on stdout (fail-open: gaps are surfaced as "notes",
        never a hard exit)
    2 — usage error
"""

import argparse
import ast
import json
import os
import re
import sys
from pathlib import Path

# Vendored / build dirs we never want to descend into — pruned in-place during
# os.walk so a large node_modules or .venv doesn't dominate the scan.
_PRUNE_DIRS = {".git", "node_modules", "venv", ".venv", "env", "dist", "build", "__pycache__"}


def _iter_python_files(root: Path):
    """Yield non-test, non-migration .py files under root."""
    for r, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in _PRUNE_DIRS]
        for f in files:
            if not f.endswith(".py"):
                continue
            fp = Path(r) / f
            s = fp.as_posix()
            if "/tests/" in s or "/migrations/" in s:
                continue
            yield fp


def _parse(fp: Path):
    try:
        return ast.parse(fp.read_text(encoding="utf-8"), filename=str(fp))
    except (SyntaxError, OSError, UnicodeDecodeError):
        return None


def _base_names(node: ast.ClassDef) -> list[str]:
    names = []
    for base in node.bases:
        if isinstance(base, ast.Name):
            names.append(base.id)
        elif isinstance(base, ast.Attribute):
            names.append(ast.unparse(base))
    return names


# ---------------------------------------------------------------------------
# Backend root detection
# ---------------------------------------------------------------------------


def detect_backend_root(project_root: Path) -> Path:
    """Find the directory holding manage.py; fall back to project root.

    Picks the shallowest manage.py so a nested example project doesn't win.
    """
    candidates = []
    for r, dirs, files in os.walk(project_root):
        dirs[:] = [d for d in dirs if d not in _PRUNE_DIRS]
        if "manage.py" in files:
            candidates.append(Path(r))
    candidates.sort(key=lambda p: len(p.parts))
    if candidates:
        return candidates[0]
    return project_root


# ---------------------------------------------------------------------------
# Discovery (stdlib AST)
# ---------------------------------------------------------------------------


def discover_permission_classes(root: Path) -> list[dict]:
    """Find DRF permission classes (BasePermission subclasses)."""
    classes = []
    seen = set()
    for fp in _iter_python_files(root):
        tree = _parse(fp)
        if not tree:
            continue
        for node in ast.walk(tree):
            if not isinstance(node, ast.ClassDef):
                continue
            bases = _base_names(node)
            if not any("BasePermission" in b for b in bases):
                continue
            key = f"{fp}:{node.name}"
            if key in seen:
                continue
            seen.add(key)
            classes.append(
                {
                    "name": node.name,
                    "base": next((b for b in bases if "BasePermission" in b), bases[0] if bases else ""),
                    "file": str(fp),
                    "line": node.lineno,
                }
            )
    return classes


def discover_phi(root: Path, phi_mixin: str | None = None) -> dict:
    """Find a PHI filter mixin and the serializers that use it.

    Generic detection (no hardcoded class names):
    - PHI fields come from a ``*_FIELDS`` set/frozenset/tuple naming PHI.
    - The mixin is the class — preferentially PHI-named — that is *applied as a
      base* to the most serializer classes. Ranking by name + actual application
      (not "mentions PHI anywhere in its body") avoids matching unrelated
      helpers such as a logging ``Filter`` that merely references PHI in a
      docstring.
    - ``phi_mixin`` (the ``--phi-mixin`` flag) overrides detection outright.
    """
    phi_fields: list[str] = []
    phi_file = None
    classes: dict[str, str] = {}           # class name -> defining file
    base_users: dict[str, list[str]] = {}  # base class name -> subclasses using it

    for fp in _iter_python_files(root):
        tree = _parse(fp)
        if not tree:
            continue
        if not phi_fields:
            text = fp.read_text(encoding="utf-8", errors="ignore")
            m = re.search(
                r"(\w*PHI\w*_FIELDS|PHI_FIELDS)\s*=\s*(?:frozenset\()?\s*[\{\[\(](.*?)[\}\]\)]",
                text,
                re.DOTALL,
            )
            if m:
                phi_fields = re.findall(r'["\'](\w+)["\']', m.group(2))
                phi_file = str(fp)
        for node in ast.walk(tree):
            if not isinstance(node, ast.ClassDef):
                continue
            classes.setdefault(node.name, str(fp))
            for b in _base_names(node):
                base_users.setdefault(b, []).append(node.name)

    def serializer_uses(name: str) -> int:
        return sum(1 for u in base_users.get(name, []) if "Serializer" in u)

    # Select the mixin.
    if phi_mixin:
        mixin_name = phi_mixin  # explicit override wins, found or not
    else:
        applied = [c for c in classes if base_users.get(c)]
        phi_named = [c for c in applied if "PHI" in c.upper()]
        pool = phi_named or [c for c in applied if serializer_uses(c)]
        mixin_name = max(
            pool,
            key=lambda c: (serializer_uses(c), len(base_users.get(c, []))),
            default=None,
        )

    applied_to = sorted(set(base_users.get(mixin_name, []))) if mixin_name else []
    if mixin_name and not phi_file:
        phi_file = classes.get(mixin_name)

    return {
        "mixin_class": mixin_name,
        "fields": phi_fields,
        "file": phi_file,
        "applied_to": applied_to,
    }


def discover_groups(root: Path) -> list[dict]:
    """Parse group/permission definitions from any *_PERMISSIONS = [...] list."""
    groups = []
    for fp in _iter_python_files(root):
        text = fp.read_text(encoding="utf-8", errors="ignore")
        if "_PERMISSIONS" not in text:
            continue
        block_pattern = re.compile(r"(\w+)_PERMISSIONS\s*=\s*\[")
        for block_match in block_pattern.finditer(text):
            group_name = block_match.group(1).lower()
            start = block_match.end()
            depth, pos = 1, start
            while pos < len(text) and depth > 0:
                if text[pos] == "[":
                    depth += 1
                elif text[pos] == "]":
                    depth -= 1
                pos += 1
            block = text[start : pos - 1]
            permissions = []
            for entry in re.finditer(r"\((\w+),\s*\[([^\]]+)\]\)", block):
                actions = [a.strip().strip("\"'") for a in entry.group(2).split(",")]
                permissions.append([entry.group(1), actions])
            groups.append({"name": group_name, "permissions": permissions, "file": str(fp)})
    return groups


def discover_finding_types(script_file: Path | None = None) -> list[str]:
    """Extract the finding-type vocabulary from the sibling audit skill's SKILL.md.

    Keeps the remediation finding-type vocabulary in sync with the audit skill
    rather than hardcoding it. Locates the audit SKILL.md relative to this
    script (skills/rbac-audit-django/SKILL.md) instead of a hardcoded project
    path. Fail-open: returns [] if the file can't be found or read.

    Preserves the original extraction logic exactly — every backtick-wrapped
    first-column table cell in the audit SKILL.md (the finding-type table).
    """
    script_file = script_file or Path(__file__)
    # script is at skills/rbac-remediation-playbooks/scripts/ → parents[2] = skills/
    audit_skill = script_file.resolve().parents[2] / "rbac-audit-django" / "SKILL.md"
    if not audit_skill.is_file():
        return []
    try:
        content = audit_skill.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return []
    types = []
    for match in re.finditer(r"\|\s*`(\w[\w-]+)`\s*\|", content):
        types.append(match.group(1))
    return types


def discover_roles(project_root: Path) -> list[dict]:
    """Extract role definitions from an RBAC docs file, if one exists.

    Searches docs/ for a markdown file whose name suggests RBAC/authorization.
    """
    docs = project_root / "docs"
    if not docs.is_dir():
        return []
    roles = []
    role_pattern = re.compile(
        r"###\s+\d+\.\s+(.+?)(?:\n|\r\n).*?\*\*Capabilities:\*\*\s*\n(.*?)(?=\n###|\n##|\Z)",
        re.DOTALL,
    )
    for fp in docs.rglob("*.md"):
        name = fp.name.lower()
        if not any(k in name for k in ("rbac", "role", "permission", "authz", "authorization")):
            continue
        content = fp.read_text(encoding="utf-8", errors="ignore")
        for match in role_pattern.finditer(content):
            bullets = re.findall(r"^-\s+(.+)$", match.group(2).strip(), re.MULTILINE)
            roles.append(
                {"name": match.group(1).strip(), "access": "; ".join(bullets[:3]), "source": str(fp)}
            )
    return roles


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Discover Django/DRF RBAC + PHI platform context as JSON"
    )
    parser.add_argument("project_root", nargs="?", default=".", help="Project root (default: cwd)")
    parser.add_argument(
        "--phi-mixin",
        help="Override PHI mixin detection with this exact class name",
    )
    args = parser.parse_args()

    project_root = Path(args.project_root).resolve()
    backend_root = detect_backend_root(project_root)

    output = {
        "project_root": str(project_root),
        "backend_root": str(backend_root),
        "permission_classes": discover_permission_classes(backend_root),
        "groups": discover_groups(backend_root),
        "phi": discover_phi(backend_root, args.phi_mixin),
        "roles": discover_roles(project_root),
        "finding_types": discover_finding_types(),
        "notes": [],
    }

    # Fail open: surface gaps as notes, never a hard exit.
    if not output["permission_classes"]:
        output["notes"].append(
            "No DRF BasePermission subclasses found under the backend root — "
            "verify this is a Django/DRF project, or pass the backend path explicitly."
        )
    if not output["groups"]:
        output["notes"].append("No *_PERMISSIONS group-setup blocks found.")
    if not output["phi"]["mixin_class"]:
        output["notes"].append("No PHI filter mixin detected (may be a non-PHI codebase).")
    if not output["roles"]:
        output["notes"].append("No RBAC docs found under docs/ — roles inferred from code only.")
    if not output["finding_types"]:
        output["notes"].append(
            "Could not read finding-type vocabulary from the sibling audit "
            "SKILL.md — finding types will fall back to the table in this skill."
        )

    json.dump(output, sys.stdout, indent=2)
    print()


if __name__ == "__main__":
    main()
