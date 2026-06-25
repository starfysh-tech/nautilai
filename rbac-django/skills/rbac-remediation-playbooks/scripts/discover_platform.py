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

import ast
import json
import re
import sys
from pathlib import Path


def _iter_python_files(root: Path):
    """Yield non-test, non-migration .py files under root."""
    for fp in root.rglob("*.py"):
        s = str(fp)
        if "/tests/" in s or "/migrations/" in s or "/node_modules/" in s:
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
    candidates = sorted(
        (p for p in project_root.rglob("manage.py") if "/node_modules/" not in str(p)),
        key=lambda p: len(p.parts),
    )
    if candidates:
        return candidates[0].parent
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


def discover_phi(root: Path) -> dict:
    """Find a PHI filter mixin and the serializers that use it.

    Generic: the mixin is identified by a class that references PHI fields (a
    *_FIELDS frozenset/set naming PHI, or a class whose name contains
    PHI/Filter). No hardcoded class or field names.
    """
    mixin_name = None
    phi_fields: list[str] = []
    phi_file = None

    for fp in _iter_python_files(root):
        tree = _parse(fp)
        if not tree:
            continue
        text = fp.read_text(encoding="utf-8", errors="ignore")
        if not phi_fields:
            m = re.search(
                r"(\w*PHI\w*_FIELDS|PHI_FIELDS)\s*=\s*(?:frozenset\()?\s*[\{\[](.*?)[\}\]]",
                text,
                re.DOTALL,
            )
            if m:
                phi_fields = re.findall(r'["\'](\w+)["\']', m.group(2))
                phi_file = str(fp)
        if mixin_name:
            continue
        for node in ast.walk(tree):
            if not isinstance(node, ast.ClassDef):
                continue
            dumped = ast.dump(node)
            if "PHI" in dumped or "phi_field" in dumped.lower():
                bases = _base_names(node)
                if "Mixin" in node.name or "Filter" in node.name or not any("Serializer" in b for b in bases):
                    mixin_name = node.name
                    if not phi_file:
                        phi_file = str(fp)
                    break

    applied_to = []
    if mixin_name:
        for fp in _iter_python_files(root):
            tree = _parse(fp)
            if not tree:
                continue
            for node in ast.walk(tree):
                if isinstance(node, ast.ClassDef) and mixin_name in _base_names(node):
                    applied_to.append(node.name)

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
    if len(sys.argv) > 2:
        print("Usage: discover_platform.py [project-root]", file=sys.stderr)
        sys.exit(2)

    project_root = Path(sys.argv[1]).resolve() if len(sys.argv) == 2 else Path.cwd()
    backend_root = detect_backend_root(project_root)

    output = {
        "project_root": str(project_root),
        "backend_root": str(backend_root),
        "permission_classes": discover_permission_classes(backend_root),
        "groups": discover_groups(backend_root),
        "phi": discover_phi(backend_root),
        "roles": discover_roles(project_root),
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

    json.dump(output, sys.stdout, indent=2)
    print()


if __name__ == "__main__":
    main()
