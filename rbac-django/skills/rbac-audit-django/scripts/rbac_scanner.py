#!/usr/bin/env python3
"""
RBAC Scanner — Deterministic inventory of Django/DRF authorization surface.

Self-discovers patterns from the codebase rather than hardcoding them:
- Role/group names are extracted from the group-setup management command
- PHI mixin is identified by finding classes that reference PHI_FIELDS
- Membership/through-model viewsets are identified by model relationship analysis
- Unclassified items are flagged rather than silently skipped

Stdlib-only at the core (Python 3.10+). Two external CLIs are *preferred* but
optional — `ast-grep` (structural matching) and `rg`/ripgrep (fast search). If
either is absent the scanner degrades to slower stdlib AST/file walks rather
than failing, so it runs on a clean machine with no install step.

Usage (the skill invokes it via ${CLAUDE_PLUGIN_ROOT} — never a hardcoded path):
    python3 rbac_scanner.py <backend-path>
    python3 rbac_scanner.py server/
"""

import ast
import json
import shutil
import subprocess
import sys
from datetime import date
from pathlib import Path

# Resolve preferred external tools once. None → use the stdlib fallback.
_AST_GREP = shutil.which("ast-grep")
_RG = shutil.which("rg")

# ---------------------------------------------------------------------------
# Shell helpers
# ---------------------------------------------------------------------------


def run_cmd(cmd: list[str], cwd: str | None = None) -> str:
    """Run a command, returning stdout. Fails open: a missing binary or a
    non-zero exit yields '' rather than raising, so an absent optional tool
    degrades the scan instead of crashing it."""
    try:
        result = subprocess.run(  # noqa: S603
            cmd, capture_output=True, text=True, cwd=cwd, check=False
        )
    except (FileNotFoundError, OSError):
        return ""
    return result.stdout


def run_ast_grep(pattern: str, path: str, lang: str = "python") -> list[dict]:
    """Structural search via ast-grep. Returns [] when ast-grep is absent —
    the stdlib file-walk scanners (_scan_file_viewsets etc.) are the backstop."""
    if not _AST_GREP:
        return []
    raw = run_cmd([_AST_GREP, "--pattern", pattern, "--lang", lang, path, "--json"])
    if not raw.strip():
        return []
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return []


# Extensions for the stdlib ripgrep fallback, keyed by ripgrep's --type value.
_TYPE_EXTENSIONS = {
    "py": (".py",),
    "ts": (".ts", ".tsx"),
}


def _grep_stdlib(pattern: str, path: str, type_filter: str) -> list[dict]:
    """Pure-Python substring/regex search used when rg is unavailable."""
    import re as _re

    try:
        rx = _re.compile(pattern)
    except _re.error:
        rx = None
    exts = _TYPE_EXTENSIONS.get(type_filter, (".py",))
    results = []
    base = Path(path)
    files = base.rglob("*") if base.is_dir() else [base]
    for fp in files:
        if not fp.is_file() or fp.suffix not in exts:
            continue
        try:
            for i, line in enumerate(fp.read_text(encoding="utf-8", errors="ignore").splitlines(), 1):
                hit = rx.search(line) if rx else (pattern in line)
                if hit:
                    results.append({"file": str(fp), "line": i, "text": line.strip()})
        except OSError:
            continue
    return results


def run_rg(pattern: str, path: str, type_filter: str = "py") -> list[dict]:
    if not _RG:
        return _grep_stdlib(pattern, path, type_filter)
    raw = run_cmd([_RG, pattern, path, "--type", type_filter, "-n", "--json"])
    if not raw.strip():
        return []
    results = []
    for line in raw.strip().split("\n"):
        if not line:
            continue
        try:
            entry = json.loads(line)
            if entry.get("type") == "match":
                data = entry["data"]
                results.append({
                    "file": data["path"]["text"],
                    "line": data["line_number"],
                    "text": data["lines"]["text"].strip(),
                })
        except (json.JSONDecodeError, KeyError):
            continue
    return results


# ---------------------------------------------------------------------------
# AST helpers
# ---------------------------------------------------------------------------


def parse_file(filepath: str) -> ast.Module | None:
    try:
        with open(filepath, encoding='utf-8', errors='ignore') as f:
            return ast.parse(f.read(), filename=filepath)
    except (SyntaxError, OSError, UnicodeDecodeError):
        return None


def get_class_attr_names(node: ast.ClassDef, attr_name: str) -> list[str]:
    """Extract names from a class attribute like permission_classes = [Foo, Bar]."""
    for item in node.body:
        if isinstance(item, ast.Assign):
            for target in item.targets:
                if isinstance(target, ast.Name) and target.id == attr_name:
                    return _extract_names(item.value)
    return []


def _extract_names(node: ast.expr) -> list[str]:
    names = []
    if isinstance(node, (ast.List, ast.Tuple)):
        for elt in node.elts:
            names.extend(_extract_names(elt))
    elif isinstance(node, ast.Name):
        names.append(node.id)
    elif isinstance(node, ast.Attribute):
        names.append(ast.unparse(node))
    return names


def has_method(node: ast.ClassDef, method_name: str) -> bool:
    return any(
        isinstance(item, ast.FunctionDef) and item.name == method_name
        for item in node.body
    )


def get_string_literals(node: ast.AST) -> list[str]:
    strings = []
    for child in ast.walk(node):
        if isinstance(child, ast.Constant) and isinstance(child.value, str):
            strings.append(child.value)
    return strings


def get_base_classes(node: ast.ClassDef) -> list[str]:
    names = []
    for base in node.bases:
        if isinstance(base, ast.Name):
            names.append(base.id)
        elif isinstance(base, ast.Attribute):
            names.append(ast.unparse(base))
    return names


def find_action_decorators(node: ast.ClassDef) -> list[dict]:
    actions = []
    for item in node.body:
        if not isinstance(item, ast.FunctionDef):
            continue
        for dec in item.decorator_list:
            if isinstance(dec, ast.Call):
                func = dec.func
                is_action = (
                    (isinstance(func, ast.Name) and func.id == "action")
                    or (isinstance(func, ast.Attribute) and func.attr == "action")
                )
                if is_action:
                    perms = None
                    for kw in dec.keywords:
                        if kw.arg == "permission_classes":
                            perms = _extract_names(kw.value)
                    actions.append({
                        "method": item.name,
                        "line": item.lineno,
                        "permission_classes": perms,
                    })
    return actions


def _classify_permission_state(node: ast.ClassDef) -> str:
    """Distinguish 'no permission_classes attr' (DEFAULT) from 'permission_classes = ()' (EMPTY)."""
    for item in node.body:
        if isinstance(item, ast.Assign):
            for target in item.targets:
                if isinstance(target, ast.Name) and target.id == "permission_classes":
                    if isinstance(item.value, (ast.List, ast.Tuple)) and len(item.value.elts) == 0:
                        return "EMPTY"
    return "DEFAULT"


def _extract_model_from_queryset_attr(node: ast.ClassDef) -> str | None:
    """Extract model name from `queryset = Model.objects...` class attribute."""
    for item in node.body:
        if isinstance(item, ast.Assign):
            for target in item.targets:
                if isinstance(target, ast.Name) and target.id == "queryset":
                    current = item.value
                    while isinstance(current, ast.Call):
                        current = current.func
                    while isinstance(current, ast.Attribute):
                        current = current.value
                    if isinstance(current, ast.Name):
                        return current.id
    return None


def _has_permission_classes_or_queryset(node: ast.ClassDef) -> bool:
    for item in node.body:
        if isinstance(item, ast.Assign):
            for target in item.targets:
                if isinstance(target, ast.Name) and target.id in ("permission_classes", "queryset"):
                    return True
    return False


def _python_files(scope: str, filename: str = "*.py") -> list[Path]:
    """List Python files in scope, excluding tests and migrations."""
    return [
        fp for fp in Path(scope).rglob(filename)
        if "/tests/" not in str(fp) and "/migrations/" not in str(fp)
    ]


def _model_files(scope: str) -> list[Path]:
    """Model modules: `models.py` or any file inside a `models/` package.

    Django projects commonly split models into a package (models/user.py, …);
    matching only `models.py` would miss those.
    """
    return [
        fp for fp in _python_files(scope)
        if fp.name == "models.py" or "/models/" in fp.as_posix()
    ]


def _view_files(scope: str) -> list[Path]:
    """View modules: `views.py`, `api.py`, `viewsets.py`, or any file inside a
    `views/` package. Mirrors `_model_files` — matching only `views.py` would
    miss projects that split views into a package or use DRF's common `api.py`/
    `viewsets.py` naming conventions.
    """
    return [
        fp for fp in _python_files(scope)
        if fp.name in ("views.py", "api.py", "viewsets.py") or "/views/" in fp.as_posix()
    ]


# ---------------------------------------------------------------------------
# Self-discovery: derive patterns from the codebase
# ---------------------------------------------------------------------------


def _discover_from_permission_vars(scope: str) -> set[str]:
    """Find role names from *_PERMISSIONS = [...] variable names."""
    role_names: set[str] = set()
    for match in run_rg("_PERMISSIONS\\s*=\\s*\\[", scope, "py"):
        if "/tests/" in match["file"]:
            continue
        tree = parse_file(match["file"])
        if not tree:
            continue
        for node in ast.walk(tree):
            if isinstance(node, ast.Assign):
                for target in node.targets:
                    if isinstance(target, ast.Name) and target.id.endswith("_PERMISSIONS"):
                        role_names.add(target.id.replace("_PERMISSIONS", "").lower())
    return role_names


def _discover_from_group_creates(scope: str) -> set[str]:
    """Find role names from Group.objects.get_or_create(name="...") calls."""
    role_names: set[str] = set()
    for match in run_ast_grep("Group.objects.get_or_create($$$)", scope):
        tree = parse_file(match["file"])
        if not tree:
            continue
        for node in ast.walk(tree):
            if isinstance(node, ast.Call):
                for kw in getattr(node, "keywords", []):
                    if kw.arg == "name" and isinstance(kw.value, ast.Constant) and isinstance(kw.value.value, str):
                        role_names.add(kw.value.value)
    return role_names


def _discover_from_group_filters(scope: str) -> set[str]:
    """Find role names from groups.filter(name=...) or name__in=[...] calls."""
    role_names: set[str] = set()
    for match in run_rg("groups\\.filter\\(name", scope, "py"):
        if "/tests/" in match["file"]:
            continue
        tree = parse_file(match["file"])
        if not tree:
            continue
        for node in ast.walk(tree):
            if not isinstance(node, ast.Call):
                continue
            for kw in getattr(node, "keywords", []):
                if kw.arg == "name" and isinstance(kw.value, ast.Constant) and isinstance(kw.value.value, str):
                    role_names.add(kw.value.value)
                elif kw.arg == "name__in" and isinstance(kw.value, (ast.List, ast.Tuple)):
                    for elt in kw.value.elts:
                        if isinstance(elt, ast.Constant) and isinstance(elt.value, str):
                            role_names.add(elt.value)
    return role_names


def discover_role_names(scope: str) -> list[str]:
    """Extract group names from the codebase.

    Primary source: *_PERMISSIONS variable names in setup commands (authoritative).
    Secondary: Group.objects.get_or_create in non-test/non-seed management commands.
    Tertiary: groups.filter(name=...) in permission modules only.

    Strategies 2 and 3 are restricted to specific directories to avoid
    picking up test fixture strings from seed data and test factories.
    """
    role_names: set[str] = set()
    # Strategy 1 is authoritative — always use it
    role_names |= _discover_from_permission_vars(scope)
    # Only add strategies 2-3 if strategy 1 found nothing
    if not role_names:
        role_names |= _discover_from_group_creates(scope)
        role_names |= _discover_from_group_filters(scope)
    return sorted(role_names)


def discover_phi_mixin_name(scope: str) -> str | None:
    """Find the PHI filter mixin by looking for classes that reference PHI_FIELDS."""
    for filepath in _python_files(scope):
        tree = parse_file(str(filepath))
        if not tree:
            continue
        for node in ast.walk(tree):
            if not isinstance(node, ast.ClassDef):
                continue
            body_str = ast.dump(node)
            if "PHI_FIELDS" not in body_str and "phi_field" not in body_str.lower():
                continue
            bases = get_base_classes(node)
            if not any("Serializer" in b for b in bases):
                return node.name
            if "Mixin" in node.name or "Filter" in node.name:
                return node.name
    return None


def _find_through_refs(node: ast.ClassDef) -> set[str]:
    """Extract through= model names from a class body."""
    through_models: set[str] = set()
    for item in node.body:
        if not isinstance(item, ast.Assign):
            continue
        for val in ast.walk(item):
            if not isinstance(val, ast.Call):
                continue
            for kw in getattr(val, "keywords", []):
                if kw.arg == "through" and isinstance(kw.value, ast.Constant) and isinstance(kw.value.value, str):
                    through_models.add(kw.value.value)
                elif kw.arg == "through" and isinstance(kw.value, ast.Name):
                    through_models.add(kw.value.id)
    return through_models



def discover_through_model_names(scope: str) -> set[str]:
    """Find through-models via M2M through= refs only (precise, no heuristics)."""
    through_models: set[str] = set()
    for filepath in _model_files(scope):
        tree = parse_file(str(filepath))
        if not tree:
            continue
        for node in ast.walk(tree):
            if isinstance(node, ast.ClassDef):
                through_models |= _find_through_refs(node)
    return through_models


# ---------------------------------------------------------------------------
# Scanners (using discovered patterns)
# ---------------------------------------------------------------------------

DRF_VIEW_BASES = {
    "ModelViewSet", "ReadOnlyModelViewSet", "ViewSet",
    "GenericViewSet", "ViewSetMixin",
    "CreateAPIView", "ListAPIView", "RetrieveAPIView",
    "DestroyAPIView", "UpdateAPIView", "ListCreateAPIView",
    "RetrieveUpdateAPIView", "RetrieveDestroyAPIView",
    "RetrieveUpdateDestroyAPIView",
    "APIView",
}

DRF_SERIALIZER_BASES = {
    "ModelSerializer", "Serializer", "HyperlinkedModelSerializer",
    "ListSerializer",
}


def _is_drf_view(bases: list[str]) -> bool:
    return any(base.split(".")[-1] in DRF_VIEW_BASES for base in bases)


def _is_drf_serializer(bases: list[str]) -> bool:
    return any(base.split(".")[-1] in DRF_SERIALIZER_BASES for base in bases)


def _build_viewset_entry(
    node: ast.ClassDef, filepath: str, line: int, through_models: set[str],
) -> dict:
    """Build a viewset inventory entry from a class node."""
    perms = get_class_attr_names(node, "permission_classes")
    bases = get_base_classes(node)
    model_name = _extract_model_from_queryset_attr(node)
    is_through = (
        model_name in through_models if model_name
        else "membership" in node.name.lower()
    )
    return {
        "name": node.name,
        "file": filepath,
        "line": line,
        "bases": bases,
        "model": model_name,
        "permission_classes": perms if perms else _classify_permission_state(node),
        "has_get_queryset": has_method(node, "get_queryset"),
        "has_perform_create": has_method(node, "perform_create"),
        "has_perform_update": has_method(node, "perform_update"),
        "has_perform_destroy": has_method(node, "perform_destroy"),
        "is_through_model_viewset": is_through,
        "actions": find_action_decorators(node),
    }


def _scan_ast_grep_viewsets(
    scope: str, through_models: set[str], seen: set[str],
) -> list[dict]:
    """Find class-based views via ast-grep patterns."""
    viewsets = []
    patterns = [
        "class $NAME(viewsets.$BASE)",
        "class $NAME(generics.$BASE)",
        "class $NAME(APIView)",
    ]
    for pattern in patterns:
        for match in run_ast_grep(pattern, scope):
            filepath = match["file"]
            if "/tests/" in filepath or "/migrations/" in filepath:
                continue
            line = match["range"]["start"]["line"] + 1
            tree = parse_file(filepath)
            if not tree:
                continue
            for node in ast.walk(tree):
                if isinstance(node, ast.ClassDef) and node.lineno == line:
                    key = f"{filepath}:{node.name}"
                    if key in seen:
                        continue
                    seen.add(key)
                    viewsets.append(_build_viewset_entry(node, filepath, line, through_models))
    return viewsets


def _scan_file_viewsets(
    scope: str, through_models: set[str], seen: set[str],
) -> tuple[list[dict], list[dict]]:
    """Walk view files for ViewSets the ast-grep patterns missed."""
    viewsets = []
    unclassified = []
    for filepath in _view_files(scope):
        filepath_str = str(filepath)
        tree = parse_file(filepath_str)
        if not tree:
            continue
        for node in ast.walk(tree):
            if not isinstance(node, ast.ClassDef):
                continue
            key = f"{filepath_str}:{node.name}"
            if key in seen:
                continue
            bases = get_base_classes(node)
            if _is_drf_view(bases):
                seen.add(key)
                viewsets.append(_build_viewset_entry(node, filepath_str, node.lineno, through_models))
            elif _has_permission_classes_or_queryset(node):
                seen.add(key)
                unclassified.append({
                    "name": node.name, "file": filepath_str, "line": node.lineno,
                    "bases": bases, "reason": "Has permission_classes or queryset but unknown base class",
                })
    return viewsets, unclassified


def _has_api_view_decorator(node: ast.FunctionDef) -> bool:
    for dec in node.decorator_list:
        if isinstance(dec, ast.Call):
            func = dec.func
            if (isinstance(func, ast.Name) and func.id == "api_view") or (
                isinstance(func, ast.Attribute) and func.attr == "api_view"
            ):
                return True
    return False


def _scan_fbv_viewsets_stdlib(scope: str, seen: set[str]) -> list[dict]:
    """Stdlib AST fallback for `_scan_fbv_viewsets` when ast-grep is unavailable.
    Restricted to view files (see `_view_files`), unlike the ast-grep path which
    searches the whole scope — a reduced-coverage tradeoff noted in main()'s
    tool_warnings.
    """
    viewsets = []
    for filepath in _view_files(scope):
        filepath_str = str(filepath)
        if "/tests/" in filepath_str:
            continue
        tree = parse_file(filepath_str)
        if not tree:
            continue
        for node in ast.walk(tree):
            if not isinstance(node, ast.FunctionDef) or not _has_api_view_decorator(node):
                continue
            key = f"{filepath_str}:{node.name}"
            if key in seen:
                continue
            seen.add(key)
            has_perms = any(
                isinstance(d, ast.Call) and (
                    (isinstance(d.func, ast.Name) and d.func.id == "permission_classes")
                    or (isinstance(d.func, ast.Attribute) and d.func.attr == "permission_classes")
                )
                for d in node.decorator_list
            )
            viewsets.append({
                "name": node.name, "file": filepath_str, "line": node.lineno,
                "bases": ["@api_view"], "model": None,
                "permission_classes": "EXPLICIT" if has_perms else "DEFAULT",
                "has_get_queryset": False, "has_perform_create": False,
                "has_perform_update": False, "has_perform_destroy": False,
                "is_through_model_viewset": False, "actions": [],
            })
    return viewsets


def _scan_fbv_viewsets(scope: str, seen: set[str]) -> list[dict]:
    """Find function-based views via @api_view decorator."""
    if not _AST_GREP:
        return _scan_fbv_viewsets_stdlib(scope, seen)
    viewsets = []
    for match in run_ast_grep("@api_view($$$)", scope):
        filepath = match["file"]
        if "/tests/" in filepath:
            continue
        line = match["range"]["start"]["line"] + 1
        tree = parse_file(filepath)
        if not tree:
            continue
        for node in ast.walk(tree):
            if not (isinstance(node, ast.FunctionDef) and abs(node.lineno - line) <= 3):
                continue
            has_perms = any(
                isinstance(d, ast.Call) and (
                    (isinstance(d.func, ast.Name) and d.func.id == "permission_classes")
                    or (isinstance(d.func, ast.Attribute) and d.func.attr == "permission_classes")
                )
                for d in node.decorator_list
            )
            key = f"{filepath}:{node.name}"
            if key in seen:
                continue
            seen.add(key)
            viewsets.append({
                "name": node.name, "file": filepath, "line": node.lineno,
                "bases": ["@api_view"], "model": None,
                "permission_classes": "EXPLICIT" if has_perms else "DEFAULT",
                "has_get_queryset": False, "has_perform_create": False,
                "has_perform_update": False, "has_perform_destroy": False,
                "is_through_model_viewset": False, "actions": [],
            })
    return viewsets


def scan_viewsets(scope: str, through_models: set[str]) -> tuple[list[dict], list[dict]]:
    """Find all ViewSet, APIView, and @api_view endpoints."""
    seen: set[str] = set()
    viewsets = _scan_ast_grep_viewsets(scope, through_models, seen)
    file_vs, unclassified = _scan_file_viewsets(scope, through_models, seen)
    viewsets.extend(file_vs)
    viewsets.extend(_scan_fbv_viewsets(scope, seen))
    return viewsets, unclassified


def _scan_permission_classes_stdlib(scope: str, discovered_role_names: list[str]) -> list[dict]:
    """Stdlib AST fallback for `scan_permission_classes` when ast-grep is
    unavailable — walks every Python file in scope for classes subclassing
    BasePermission (adapted from rbac-remediation-playbooks/scripts/discover_platform.py
    `discover_permission_classes`, extended with the has_has_permission /
    has_has_object_permission / hardcoded_role_names fields this scanner needs).
    """
    results = []
    seen: set[str] = set()
    for filepath in _python_files(scope):
        filepath_str = str(filepath)
        if "/tests/" in filepath_str:
            continue
        tree = parse_file(filepath_str)
        if not tree:
            continue
        for node in ast.walk(tree):
            if not isinstance(node, ast.ClassDef):
                continue
            bases = get_base_classes(node)
            if not any(b.split(".")[-1] == "BasePermission" for b in bases):
                continue
            key = f"{filepath_str}:{node.name}"
            if key in seen:
                continue
            seen.add(key)
            strings = get_string_literals(node)
            results.append({
                "name": node.name, "file": filepath_str, "line": node.lineno,
                "bases": bases,
                "has_has_permission": has_method(node, "has_permission"),
                "has_has_object_permission": has_method(node, "has_object_permission"),
                "hardcoded_role_names": [s for s in strings if s in discovered_role_names],
            })
    return results


def scan_permission_classes(scope: str, discovered_role_names: list[str]) -> list[dict]:
    """Find all DRF permission classes."""
    if not _AST_GREP:
        return _scan_permission_classes_stdlib(scope, discovered_role_names)
    results = []
    patterns = ["class $NAME(permissions.$BASE)", "class $NAME(BasePermission)"]
    seen: set[str] = set()
    for pattern in patterns:
        for match in run_ast_grep(pattern, scope):
            filepath = match["file"]
            if "/tests/" in filepath:
                continue
            line = match["range"]["start"]["line"] + 1
            tree = parse_file(filepath)
            if not tree:
                continue
            for node in ast.walk(tree):
                if isinstance(node, ast.ClassDef) and node.lineno == line:
                    key = f"{filepath}:{node.name}"
                    if key in seen:
                        continue
                    seen.add(key)
                    strings = get_string_literals(node)
                    results.append({
                        "name": node.name, "file": filepath, "line": line,
                        "bases": get_base_classes(node),
                        "has_has_permission": has_method(node, "has_permission"),
                        "has_has_object_permission": has_method(node, "has_object_permission"),
                        "hardcoded_role_names": [s for s in strings if s in discovered_role_names],
                    })
    return results


def scan_queryset_managers(scope: str) -> list[dict]:
    """Find custom QuerySet/Manager methods that accept user/tenant parameters."""
    results = []
    seen: set[str] = set()
    tenant_params = {
        "user", "clinic", "organization", "tenant", "study",
        "team", "workspace", "account", "company",
    }

    for filepath in _model_files(scope):
        filepath_str = str(filepath)
        tree = parse_file(filepath_str)
        if not tree:
            continue
        for cls_node in ast.walk(tree):
            if not isinstance(cls_node, ast.ClassDef):
                continue
            bases = get_base_classes(cls_node)
            if not any("QuerySet" in b or "Manager" in b for b in bases):
                continue
            for item in cls_node.body:
                if not isinstance(item, ast.FunctionDef) or item.name.startswith("_"):
                    continue
                arg_names = [a.arg for a in item.args.args if a.arg != "self"]
                if not any(a in tenant_params for a in arg_names):
                    continue
                key = f"{filepath_str}:{cls_node.name}.{item.name}"
                if key in seen:
                    continue
                seen.add(key)
                results.append({
                    "method": item.name, "file": filepath_str, "line": item.lineno,
                    "class": cls_node.name, "params": arg_names,
                    "has_staff_bypass": "is_staff" in ast.dump(item),
                })
    return results


def scan_role_name_strings(scope: str, discovered_role_names: list[str]) -> dict:
    """Find hardcoded role/group name strings using discovered role names."""
    results: dict = {}
    for role_name in discovered_role_names:
        for quote in ['"', "'"]:
            pattern = f"{quote}{role_name}{quote}"
            matches = run_rg(pattern, scope, "py")
            filtered = [m for m in matches if "/tests/" not in m["file"]]
            if not filtered:
                continue
            if role_name not in results:
                results[role_name] = {"count": 0, "locations": []}
            existing = {f"{loc['file']}:{loc['line']}" for loc in results[role_name]["locations"]}
            for match in filtered:
                key = f"{match['file']}:{match['line']}"
                if key not in existing:
                    results[role_name]["locations"].append({"file": match["file"], "line": match["line"]})
                    existing.add(key)
            results[role_name]["count"] = len(results[role_name]["locations"])
    return results


# Frontend dir names to probe for a React/TS source root, in order. Generic —
# covers the common React layouts rather than assuming one project's structure.
_FRONTEND_ROOTS = (("frontend", "src"), ("client", "src"), ("web", "src"), ("src",))

# Common role-coupling identifiers in React/TS frontends. Heuristic, not
# exhaustive — these are the usual names for role enums and route guards.
_FRONTEND_ROLE_PATTERNS = (
    "primaryRole",
    "RequireRole",
    "canAccessRoute",
    "routeRoleMap",
    "useRole",
    "usePermission",
    "hasRole",
)


def _find_frontend_src(base_path: str) -> str | None:
    """Walk up from the scan scope to find a React/TS source root.

    Tries common layouts (frontend/src, client/src, web/src, src) rather than
    assuming any one project's directory names.
    """
    search_dir = Path(base_path).resolve()
    for _ in range(5):  # Walk up at most 5 levels
        for parts in _FRONTEND_ROOTS:
            candidate = search_dir.joinpath(*parts)
            if candidate.is_dir():
                return str(candidate)
        if search_dir.parent == search_dir:
            break
        search_dir = search_dir.parent
    return None


def scan_frontend_role_coupling(base_path: str) -> dict:
    """Find frontend role-enum values and role-based routing (.ts/.tsx).

    Self-locates the frontend source root; reports a note if none is found
    rather than failing. The identifiers searched are common conventions, not a
    fixed contract — treat hits as leads to read, not confirmed coupling.
    """
    frontend_src = _find_frontend_src(base_path)
    if not frontend_src:
        return {"note": "no frontend src root (frontend/client/web/src) found walking up from scope"}

    results: dict = {"frontend_src": frontend_src}
    for pattern in _FRONTEND_ROLE_PATTERNS:
        matches = run_rg(pattern, frontend_src, "ts")
        if matches:
            results[pattern] = [{"file": m["file"], "line": m["line"]} for m in matches]
    return results


def _parse_permission_list(node: ast.expr) -> tuple[list[str], dict[str, list[str]]]:
    """Parse a PERMISSIONS = [(Model, ["view", "add"]), ...] list."""
    models: list[str] = []
    perms_per_model: dict[str, list[str]] = {}
    if not isinstance(node, ast.List):
        return models, perms_per_model
    for elt in node.elts:
        if not isinstance(elt, (ast.Tuple, ast.List)) or len(elt.elts) < 2:
            continue
        model_node, perm_node = elt.elts[0], elt.elts[1]
        model_name = model_node.id if isinstance(model_node, ast.Name) else ast.unparse(model_node)
        models.append(model_name)
        perm_list: list[str] = []
        if isinstance(perm_node, (ast.List, ast.Tuple)):
            perm_list = [str(p.value) for p in perm_node.elts if isinstance(p, ast.Constant)]
        perms_per_model[model_name] = perm_list
    return models, perms_per_model


def scan_group_permission_setup(scope: str) -> dict:
    matches = run_rg("_PERMISSIONS\\s*=\\s*\\[", scope, "py")
    setup_files = [m for m in matches if "/tests/" not in m["file"]]
    if not setup_files:
        return {"note": "No group permission setup file found"}

    result: dict = {"groups": {}, "setup_file": None}
    for match in setup_files:
        filepath = match["file"]
        result["setup_file"] = filepath
        tree = parse_file(filepath)
        if not tree:
            continue
        for node in ast.walk(tree):
            if not isinstance(node, ast.Assign):
                continue
            for target in node.targets:
                if not (isinstance(target, ast.Name) and target.id.endswith("_PERMISSIONS")):
                    continue
                group_name = target.id.replace("_PERMISSIONS", "").lower()
                models, perms_per_model = _parse_permission_list(node.value)
                result["groups"][group_name] = {
                    "models_with_permissions": models,
                    "permissions_by_model": perms_per_model,
                    "line": node.lineno,
                }
    return result


def scan_serializer_phi_coverage(scope: str, phi_mixin_name: str | None) -> list[dict]:
    """Find serializers and check for PHI filter mixin usage.

    Resolves transitive inheritance: if PatientSerializer has PHIFilterMixin
    and PatientDetailSerializer inherits PatientSerializer, the detail
    serializer is marked as having the mixin too.
    """
    # First pass: collect all serializers and their direct bases
    all_serializers: dict[str, dict] = {}
    for filepath in _python_files(scope):
        tree = parse_file(str(filepath))
        if not tree:
            continue
        for node in ast.walk(tree):
            if not isinstance(node, ast.ClassDef):
                continue
            bases = get_base_classes(node)
            if not _is_drf_serializer(bases) and not (phi_mixin_name and phi_mixin_name in bases):
                if not any("Serializer" in b for b in bases):
                    continue
            key = f"{filepath}:{node.name}"
            if key in all_serializers:
                continue
            has_direct_phi = (
                phi_mixin_name in bases if phi_mixin_name
                else any("PHI" in b for b in bases)
            )
            all_serializers[key] = {
                "name": node.name, "file": str(filepath), "line": node.lineno,
                "bases": bases, "has_phi_filter_mixin": has_direct_phi,
            }

    # Second pass: resolve transitive PHI inheritance
    # Build a name → has_phi lookup from direct results
    phi_by_name: set[str] = {
        s["name"] for s in all_serializers.values() if s["has_phi_filter_mixin"]
    }
    # Propagate: if any base class name is in phi_by_name, mark this one too
    changed = True
    while changed:
        changed = False
        for info in all_serializers.values():
            if info["has_phi_filter_mixin"]:
                continue
            if any(b in phi_by_name for b in info["bases"]):
                info["has_phi_filter_mixin"] = True
                phi_by_name.add(info["name"])
                changed = True

    return list(all_serializers.values())


# ---------------------------------------------------------------------------
# Summary and output
# ---------------------------------------------------------------------------


def build_summary(inventory: dict) -> dict:
    viewsets = inventory["viewsets"]
    perms = inventory["permission_classes"]
    serializers = inventory["serializer_phi_coverage"]
    role_strings = inventory["role_name_strings"]
    unclassified = inventory["unclassified_views"]

    through_viewsets = [v for v in viewsets if v["is_through_model_viewset"]]
    through_without_create = [v for v in through_viewsets if not v["has_perform_create"]]

    return {
        "total_viewsets": len(viewsets),
        "viewsets_without_explicit_permissions": sum(
            1 for v in viewsets if v["permission_classes"] == "DEFAULT"
        ),
        "viewsets_without_get_queryset": sum(
            1 for v in viewsets
            if not v["has_get_queryset"]
            and v["bases"] != ["@api_view"]
            and v.get("model") is not None  # Only count model-backed viewsets
        ),
        "through_model_viewsets": len(through_viewsets),
        "through_model_viewsets_without_perform_create": len(through_without_create),
        "through_model_viewsets_without_perform_create_names": [
            v["name"] for v in through_without_create
        ],
        "permission_classes_without_object_permission": sum(
            1 for p in perms if not p["has_has_object_permission"]
        ),
        "total_serializers": len(serializers),
        "serializers_with_phi_filter": sum(1 for s in serializers if s["has_phi_filter_mixin"]),
        "serializers_without_phi_filter": sum(1 for s in serializers if not s["has_phi_filter_mixin"]),
        "hardcoded_role_name_locations": sum(v["count"] for v in role_strings.values()),
        "unclassified_view_count": len(unclassified),
    }


def main():
    if len(sys.argv) < 2:
        print("Usage: rbac_scanner.py <path>", file=sys.stderr)
        sys.exit(1)

    scope = sys.argv[1]

    # Phase 0: Self-discovery — derive patterns from the codebase
    discovered_roles = discover_role_names(scope)
    phi_mixin = discover_phi_mixin_name(scope)
    through_models = discover_through_model_names(scope)

    # Phase 1: Scan using discovered patterns
    viewsets, unclassified = scan_viewsets(scope, through_models)

    # Degrade loudly: if a preferred tool is missing, say so in the output so
    # the skill can note reduced structural coverage rather than trust a thin scan.
    tool_availability = {
        "ast_grep": bool(_AST_GREP),
        "ripgrep": bool(_RG),
    }
    tool_warnings = []
    if not _AST_GREP:
        tool_warnings.append(
            "ast-grep not found — permission_classes discovery (scan_permission_classes), "
            "function-based-view discovery (@api_view, _scan_fbv_viewsets), and class-based "
            "viewset matching fall back to stdlib AST file-walks restricted to views.py/"
            "api.py/viewsets.py/views/ and models.py/models/. Coverage of non-standard "
            "layouts may be reduced."
        )
    if not _RG:
        tool_warnings.append(
            "ripgrep (rg) not found — using a slower stdlib search fallback."
        )

    inventory = {
        "scan_date": date.today().isoformat(),
        "scope": scope,
        "tool_availability": tool_availability,
        "tool_warnings": tool_warnings,
        "discovered_patterns": {
            "role_names": discovered_roles,
            "phi_mixin_name": phi_mixin,
            "through_model_names": sorted(through_models),
        },
        "viewsets": viewsets,
        "unclassified_views": unclassified,
        "permission_classes": scan_permission_classes(scope, discovered_roles),
        "queryset_managers": scan_queryset_managers(scope),
        "role_name_strings": scan_role_name_strings(scope, discovered_roles),
        "frontend_role_coupling": scan_frontend_role_coupling(scope),
        "group_permissions": scan_group_permission_setup(scope),
        "serializer_phi_coverage": scan_serializer_phi_coverage(scope, phi_mixin),
    }
    inventory["summary"] = build_summary(inventory)

    print(json.dumps(inventory, indent=2, default=str))


if __name__ == "__main__":
    main()
