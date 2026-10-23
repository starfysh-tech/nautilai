#!/usr/bin/env python3
"""Build a stack inventory of a repo for tech-due-diligence.

Stdlib only. Prints one JSON document to stdout:

    python3 inventory.py <repo-path>

The file list comes from `git ls-files`, so ignored and untracked trees
(dependency installs, virtualenvs, build output, nested worktrees) never enter
the audit. Outside a git repo it falls back to a pruned directory walk.
"""
from __future__ import annotations

import argparse
import glob
import heapq
import json
import os
import re
import shutil
import subprocess
import sys
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path, PurePosixPath

PRUNE_DIRS = {
    ".git", "node_modules", ".venv", "venv", "env", "__pycache__", ".tox",
    "dist", "build", "target", "vendor", ".next", ".nuxt", "coverage",
    "htmlcov", ".pytest_cache", ".mypy_cache", "bower_components",
}

LANGUAGES = {
    ".py": "Python", ".js": "JavaScript", ".jsx": "JavaScript", ".mjs": "JavaScript",
    ".cjs": "JavaScript", ".ts": "TypeScript", ".tsx": "TypeScript", ".go": "Go",
    ".rs": "Rust", ".rb": "Ruby", ".java": "Java", ".kt": "Kotlin", ".kts": "Kotlin",
    ".scala": "Scala", ".cs": "C#", ".php": "PHP", ".swift": "Swift",
    ".m": "Objective-C", ".c": "C", ".h": "C", ".cc": "C++", ".cpp": "C++",
    ".hpp": "C++", ".ex": "Elixir", ".exs": "Elixir", ".dart": "Dart",
    ".vue": "Vue", ".svelte": "Svelte", ".sql": "SQL", ".sh": "Shell",
    ".bash": "Shell", ".tf": "HCL",
}

# filename -> (ecosystem, kind)
MANIFESTS = {
    "pyproject.toml": ("python", "manifest"), "setup.py": ("python", "manifest"),
    "setup.cfg": ("python", "manifest"), "Pipfile": ("python", "manifest"),
    "Pipfile.lock": ("python", "lockfile"), "poetry.lock": ("python", "lockfile"),
    "uv.lock": ("python", "lockfile"), "pdm.lock": ("python", "lockfile"),
    "package.json": ("node", "manifest"), "package-lock.json": ("node", "lockfile"),
    "npm-shrinkwrap.json": ("node", "lockfile"), "yarn.lock": ("node", "lockfile"),
    "pnpm-lock.yaml": ("node", "lockfile"), "bun.lockb": ("node", "lockfile"),
    "go.mod": ("go", "manifest"), "go.sum": ("go", "lockfile"),
    "Cargo.toml": ("rust", "manifest"), "Cargo.lock": ("rust", "lockfile"),
    "Gemfile": ("ruby", "manifest"), "Gemfile.lock": ("ruby", "lockfile"),
    "pom.xml": ("java", "manifest"), "build.gradle": ("java", "manifest"),
    "build.gradle.kts": ("java", "manifest"), "gradle.lockfile": ("java", "lockfile"),
    "composer.json": ("php", "manifest"), "composer.lock": ("php", "lockfile"),
    "packages.lock.json": ("dotnet", "lockfile"), "mix.exs": ("elixir", "manifest"),
    "mix.lock": ("elixir", "lockfile"), "pubspec.yaml": ("dart", "manifest"),
    "pubspec.lock": ("dart", "lockfile"),
    "Package.swift": ("swift", "manifest"), "Package.resolved": ("swift", "lockfile"),
    "Podfile": ("swift", "manifest"), "Podfile.lock": ("swift", "lockfile"),
    "Cartfile": ("swift", "manifest"), "Cartfile.resolved": ("swift", "lockfile"),
}
APPLE_CONFIG_RE = re.compile(
    r"(^|/)(Info\.plist|project\.pbxproj)$|\.(entitlements|xcprivacy|xcconfig|storekit)$"
)
ANDROID_CONFIG_RE = re.compile(
    r"(^|/)(AndroidManifest\.xml|network_security_config\.xml|google-services\.json"
    r"|proguard-rules\.pro|gradle\.properties)$"
)
XCODEGEN_RE = re.compile(r"^\s*platform:\s*(iOS|macOS|tvOS|watchOS|visionOS)\b", re.M)
REQUIREMENTS_RE = re.compile(r"^requirements([-_.][\w.-]+)?\.(txt|in)$")

CI_FILES = {
    ".gitlab-ci.yml": "gitlab-ci", ".circleci/config.yml": "circleci",
    "Jenkinsfile": "jenkins", "azure-pipelines.yml": "azure-pipelines",
    "bitbucket-pipelines.yml": "bitbucket-pipelines", ".travis.yml": "travis",
    ".buildkite/pipeline.yml": "buildkite",
}

DOC_SIGNALS = {
    "readme": re.compile(r"(^|/)README(\.\w+)?$", re.I),
    "license": re.compile(r"(^|/)(LICENSE|LICENCE|COPYING)(\.\w+)?$", re.I),
    "security_policy": re.compile(r"(^|/)SECURITY\.md$", re.I),
    "codeowners": re.compile(r"(^|/)CODEOWNERS$"),
    "contributing": re.compile(r"(^|/)CONTRIBUTING\.md$", re.I),
    "adr": re.compile(r"(^|/)(adr|adrs|decisions)/", re.I),
    "runbook": re.compile(r"runbook", re.I),
    "changelog": re.compile(r"(^|/)CHANGELOG(\.\w+)?$", re.I),
}

COVERAGE_REPORTS = {"coverage.xml", "lcov.info", "coverage-final.json", "coverage.json", "jacoco.xml"}

TEST_RE = re.compile(
    r"(^|/)(tests?|__tests__|spec)/|(^|/)test_[^/]+\.py$|_test\.(py|go)$"
    r"|\.(test|spec)\.[jt]sx?$|_spec\.rb$|Tests?\.(java|kt|cs)$"
)

KEY_MATERIAL_RE = re.compile(
    r"\.(p12|pfx|pem|key|keystore|jks|mobileprovision|provisionprofile|cer|der|ppk)$"
    r"|(^|/)id_(rsa|dsa|ecdsa|ed25519)$", re.I
)
ENV_NAME_RE = re.compile(r"^\.env(\..+)?$|\.env$|^env\.(example|sample|template)$")
ENV_TEMPLATE_RE = re.compile(r"\.(example|sample|template|dist|defaults?)$", re.I)

TOOLS = [
    "git", "gitleaks", "trufflehog", "semgrep", "osv-scanner", "trivy",
    "pip-audit", "pip-licenses", "npm", "pnpm", "yarn", "license-checker",
    "bundle-audit", "bundler-audit", "govulncheck", "cargo-audit", "cargo",
    "hadolint", "checkov", "tflint", "scc", "cloc",
]
# Agent sandboxes often run with a truncated PATH that omits package-manager bins.
EXTRA_BIN_DIRS = [
    "/opt/homebrew/bin", "/usr/local/bin", "/home/linuxbrew/.linuxbrew/bin",
    "~/.local/bin", "~/go/bin", "~/.cargo/bin", "~/.npm-global/bin",
    "~/.local/share/gem/ruby/*/bin", "~/.gem/ruby/*/bin",
]

LINE_COUNT_MAX_BYTES = 2_000_000


def is_env_file(path: str) -> bool:
    return bool(ENV_NAME_RE.search(PurePosixPath(path).name))


def run(cmd: list[str], cwd: Path, errors: str | None = None) -> str | None:
    try:
        out = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, errors=errors, timeout=120, check=False)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return out.stdout if out.returncode == 0 else None


def list_files(root: Path) -> tuple[list[str], str]:
    out = run(["git", "ls-files", "-z"], root)
    if out is not None:
        return [f for f in out.split("\0") if f], "git ls-files"
    files: list[str] = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in PRUNE_DIRS]
        rel = Path(dirpath).relative_to(root)
        files.extend(str(PurePosixPath(rel / f)) for f in filenames)
    return sorted(files), "directory walk (not a git repo)"


def read_text(root: Path, rel: str, limit: int = 200_000) -> str:
    try:
        with open(root / rel, "r", encoding="utf-8", errors="replace") as fh:
            return fh.read(limit)
    except OSError:
        return ""


def probe_tools() -> dict[str, str | None]:
    found = {}
    extra = os.pathsep.join(p for d in EXTRA_BIN_DIRS for p in glob.glob(os.path.expanduser(d)))
    search = os.environ.get("PATH", "") + os.pathsep + extra
    for tool in TOOLS:
        found[tool] = shutil.which(tool, path=search)
    return found


PY_FRAMEWORKS = [("django", r"\bdjango\b"), ("flask", r"\bflask\b"),
                 ("fastapi", r"\bfastapi\b"), ("celery", r"\bcelery\b"),
                 ("djangorestframework", r"djangorestframework")]
NODE_FRAMEWORKS = [("react", "react"), ("next", "nextjs"), ("vue", "vue"),
                   ("nuxt", "nuxt"), ("@angular/core", "angular"),
                   ("svelte", "svelte"), ("express", "express"),
                   ("@nestjs/core", "nestjs"), ("react-native", "react-native")]


def package_deps(root: Path, path: str) -> dict:
    if PurePosixPath(path).name != "package.json":
        return {}
    try:
        pkg = json.loads(read_text(root, path))
    except ValueError:
        return {}
    return {**pkg.get("dependencies", {}), **pkg.get("devDependencies", {})}


def file_frameworks(root: Path, f: str) -> list[str]:
    name = PurePosixPath(f).name
    if name == "manage.py":
        return ["django"]
    if f.endswith("config/application.rb"):
        return ["rails"]
    if name in ("pom.xml", "build.gradle", "build.gradle.kts"):
        text = read_text(root, f)
        found = ["spring-boot"] if "spring-boot" in text else []
        return found + (["android"] if re.search(r"com\.android\.(application|library)", text) else [])
    if name == "AndroidManifest.xml":
        return ["android"]
    return ["apple-app"] if is_apple_config(root, f) else []


def detect_frameworks(root: Path, files: list[str], manifests: list[dict]) -> dict[str, list[str]]:
    fw: dict[str, list[str]] = {}

    def add(name: str, evidence: str) -> None:
        fw.setdefault(name, [])
        if evidence not in fw[name] and len(fw[name]) < 10:
            fw[name].append(evidence)

    py_text = "".join(read_text(root, m["path"]).lower() + "\n" for m in manifests if m["ecosystem"] == "python")
    for name, pat in PY_FRAMEWORKS:
        if re.search(pat, py_text):
            add(name, "python dependency")
    for m in manifests:
        deps = package_deps(root, m["path"])
        for dep, name in NODE_FRAMEWORKS:
            if dep in deps:
                add(name, m["path"])
    for f in files:
        for name in file_frameworks(root, f):
            add(name, f)
    return fw


def is_apple_config(root: Path, f: str) -> bool:
    return bool(APPLE_CONFIG_RE.search(f)
                or (PurePosixPath(f).name == "project.yml" and XCODEGEN_RE.search(read_text(root, f))))


def django_settings(files: list[str]) -> list[str]:
    return [f for f in files if (p := PurePosixPath(f)).suffix == ".py"
            and (p.name == "settings.py" or p.parent.name == "settings")]


INFRA_NAMES = {
    "Chart.yaml": "helm", "kustomization.yaml": "kustomize", "kustomization.yml": "kustomize",
    "Pulumi.yaml": "pulumi", "serverless.yml": "serverless", "serverless.yaml": "serverless",
    "cdk.json": "aws-cdk",
    **dict.fromkeys(("Procfile", "app.yaml", "fly.toml", "render.yaml", "vercel.json", "netlify.toml"), "paas"),
}


def sniff_infra(head: str) -> str | None:
    if "AWSTemplateFormatVersion" in head:
        return "cloudformation"
    if re.search(r"^apiVersion:", head, re.M) and re.search(r"^kind:", head, re.M):
        return "kubernetes"
    return None


def infra_kind(root: Path, f: str) -> str | None:
    p = PurePosixPath(f)
    name = p.name
    if name.startswith("Dockerfile") or name.endswith(".dockerfile"):
        return "dockerfile"
    if re.match(r"^(docker-)?compose[\w.-]*\.ya?ml$", name):
        return "compose"
    if f.startswith(".github/workflows/") and p.suffix in (".yml", ".yaml"):
        return "ci:github-actions"
    if f in CI_FILES:
        return "ci:" + CI_FILES[f]
    if p.suffix == ".tf":
        return "terraform"
    if name in INFRA_NAMES:
        return INFRA_NAMES[name]
    if p.suffix in (".yml", ".yaml", ".json") and not name.startswith("."):
        return sniff_infra(read_text(root, f, 4_000))
    return None


def detect_infra(root: Path, files: list[str]) -> dict[str, list[str]]:
    infra: dict[str, list[str]] = {}
    for f in files:
        kind = infra_kind(root, f)
        if kind:
            infra.setdefault(kind, []).append(f)
    return infra


def merge_identities(raw: list[list[str]]) -> list[str]:
    """Label each commit with one person, joining author names and emails that co-occur."""
    parent: dict[str, str] = {}

    def find(k: str) -> str:
        while parent.setdefault(k, k) != k:
            parent[k] = parent[parent[k]]
            k = parent[k]
        return k

    for name, email, _ in raw:
        a, b = find("n:" + name.strip().lower()), find("e:" + email.strip().lower())
        if a != b:
            parent[a] = b
    names: dict[str, Counter] = {}
    for name, email, _ in raw:
        names.setdefault(find("e:" + email.strip().lower()), Counter())[name] += 1
    label = {root: c.most_common(1)[0][0] for root, c in names.items()}
    return [label[find("e:" + email.strip().lower())] for _, email, _ in raw]


IMAGE_LINE_RE = re.compile(r"^\s*(?:-\s*)?image:\s*['\"]?([^'\"\s#]+)", re.M)
TOML_IMAGE_RE = re.compile(r"^\s*image\s*=\s*['\"]([^'\"]+)['\"]", re.M)
FROM_LINE_RE = re.compile(r"^\s*FROM\s+(?:--platform=\S+\s+)?(\S+)", re.M | re.I)


def container_images(root: Path, files: list[str], infra: dict[str, list[str]]) -> list[dict]:
    """Image references named by compose, Kubernetes, Helm, and Dockerfiles, as written."""
    found = []
    yaml_files = set(infra.get("compose", []) + infra.get("kubernetes", []))
    if infra.get("helm"):
        yaml_files.update(f for f in files if "/templates/" in f and f.endswith((".yaml", ".yml")))
    tomls = [f for f in infra.get("paas", []) if f.endswith(".toml")]
    for rx, group in ((IMAGE_LINE_RE, sorted(yaml_files)), (TOML_IMAGE_RE, tomls)):
        for f in group:
            text = read_text(root, f)
            for m in rx.finditer(text):
                found.append({"ref": m.group(1), "file": f, "line": text.count("\n", 0, m.start()) + 1})
    for f in infra.get("dockerfile", []):
        stages = {"scratch"}
        for n, line in enumerate(read_text(root, f).splitlines(), 1):
            frm = FROM_LINE_RE.match(line)
            if not frm:
                continue
            if frm.group(1).lower() not in stages:
                found.append({"ref": frm.group(1), "file": f, "line": n})
            alias = re.search(r"\bAS\s+(\S+)", line, re.I)
            if alias:
                stages.add(alias.group(1).lower())
    return found


def git_out(root: Path, *args: str) -> str | None:
    return (run(["git", *args], root) or "").strip() or None


def git_checkout(root: Path) -> dict:
    checkout = {
        "branch": git_out(root, "rev-parse", "--abbrev-ref", "HEAD"),
        "head": git_out(root, "rev-parse", "--short", "HEAD"),
        "upstream": git_out(root, "rev-parse", "--abbrev-ref", "@{u}"),
        "ahead": None, "behind": None, "last_fetch": None,
        "uncommitted_changes": len((git_out(root, "status", "--porcelain") or "").splitlines()),
    }
    if checkout["upstream"]:
        counts = (git_out(root, "rev-list", "--left-right", "--count", "HEAD...@{u}") or "").split()
        if len(counts) == 2:
            checkout["ahead"], checkout["behind"] = int(counts[0]), int(counts[1])
    fetch_head = git_out(root, "rev-parse", "--git-path", "FETCH_HEAD")
    if fetch_head:
        try:
            mtime = (root / fetch_head).stat().st_mtime
            checkout["last_fetch"] = datetime.fromtimestamp(mtime, timezone.utc).isoformat(timespec="seconds")
        except OSError:
            pass
    return checkout


def author_stats(rows: list[tuple[str, str]]) -> dict:
    authors = Counter(a for a, _ in rows)
    year_ago = datetime.now(timezone.utc) - timedelta(days=365)
    recent = Counter(a for a, d in rows if datetime.fromisoformat(d.replace("Z", "+00:00")) >= year_ago)
    recent_total = sum(recent.values())
    return {
        "authors_all_time": len(authors),
        "authors_last_12_months": len(recent),
        "commits_last_12_months": recent_total,
        "top_authors": [{"name": a, "commits": n, "share": round(n / len(rows), 3)} for a, n in authors.most_common(10)],
        "top_author_share_last_12_months": round(recent.most_common(1)[0][1] / recent_total, 3) if recent else None,
    }


def churn(root: Path) -> list[dict]:
    names = run(["git", "log", "--no-merges", "--since=12 months ago", "--format=", "--name-only"], root) or ""
    counts = Counter(n for n in names.splitlines() if n)
    return [{"path": p, "commits": n} for p, n in counts.most_common(20)]


def git_history(root: Path) -> dict | None:
    if run(["git", "rev-parse", "--git-dir"], root) is None:
        return None
    log = run(["git", "log", "--no-merges", "--format=%aN%x09%aE%x09%aI"], root)
    if log is None:
        return {"commits": 0}
    raw = [line.split("\t", 2) for line in log.splitlines() if line.count("\t") == 2]
    if not raw:
        return {"commits": 0}
    rows = list(zip(merge_identities(raw), (r[2] for r in raw)))
    return {
        "commits": len(rows),
        "checkout": git_checkout(root),
        "shallow_clone": git_out(root, "rev-parse", "--is-shallow-repository") == "true",
        "first_commit": rows[-1][1],
        "last_commit": rows[0][1],
        **author_stats(rows),
        "most_changed_files_last_12_months": churn(root),
    }


def count_lines(root: Path, files: list[str]) -> tuple[dict[str, dict[str, int]], list[dict]]:
    langs: dict[str, dict[str, int]] = {}
    sizes: list[dict] = []
    for f in files:
        lang = LANGUAGES.get(PurePosixPath(f).suffix.lower())
        if not lang:
            continue
        entry = langs.setdefault(lang, {"files": 0, "lines": 0})
        entry["files"] += 1
        try:
            path = root / f
            if path.stat().st_size > LINE_COUNT_MAX_BYTES:
                continue
            data = path.read_bytes()
            n = data.count(b"\n") + (bool(data) and not data.endswith(b"\n"))
        except OSError:
            continue
        entry["lines"] += n
        sizes.append({"path": f, "lines": n})
    largest = heapq.nlargest(20, sizes, key=lambda s: s["lines"])
    return dict(sorted(langs.items(), key=lambda kv: -kv[1]["lines"])), largest


def find_manifests(files: list[str]) -> list[dict]:
    manifests = []
    for f in files:
        name = PurePosixPath(f).name
        if name in MANIFESTS:
            eco, kind = MANIFESTS[name]
        elif REQUIREMENTS_RE.match(name):
            eco, kind = "python", "requirements"
        elif name.endswith(".csproj"):
            eco, kind = "dotnet", "manifest"
        else:
            continue
        manifests.append({"path": f, "dir": str(PurePosixPath(f).parent), "ecosystem": eco, "kind": kind})
    return manifests


def group_ecosystems(manifests: list[dict]) -> dict[str, dict[str, list[str]]]:
    ecosystems: dict[str, dict[str, list[str]]] = {}
    for m in manifests:
        e = ecosystems.setdefault(m["ecosystem"], {"dirs": [], "lockfiles": [], "manifests": []})
        if m["dir"] not in e["dirs"]:
            e["dirs"].append(m["dir"])
        e["lockfiles" if m["kind"] == "lockfile" else "manifests"].append(m["path"])
    return ecosystems


def platform_configs(root: Path, files: list[str], frameworks: dict[str, list[str]]) -> dict[str, list[str]]:
    return {
        "django_settings_modules": django_settings(files) if "django" in frameworks else [],
        "apple_config_files": [f for f in files if is_apple_config(root, f)] if "apple-app" in frameworks else [],
        "android_config_files": [f for f in files if ANDROID_CONFIG_RE.search(f)] if "android" in frameworks else [],
    }


def secret_files(files: list[str], in_git: bool) -> dict[str, list[str]]:
    env_files = [f for f in files if is_env_file(f) and not ENV_TEMPLATE_RE.search(f)]
    key_files = [f for f in files if KEY_MATERIAL_RE.search(f)]
    # Outside git nothing is "tracked": the files are only present on disk.
    return {
        "tracked_env_files": env_files if in_git else [],
        "tracked_key_material": key_files if in_git else [],
        "untracked_env_files": [] if in_git else env_files,
        "untracked_key_material": [] if in_git else key_files,
    }


def inventory(root: Path) -> dict:
    files, source = list_files(root)
    manifests = find_manifests(files)
    frameworks = detect_frameworks(root, files, manifests)
    docs = {k: [f for f in files if rx.search(f)][:20] for k, rx in DOC_SIGNALS.items()}
    languages, largest = count_lines(root, files)
    infra = detect_infra(root, files)
    return {
        "root": str(root),
        "file_source": source,
        "file_count": len(files),
        "languages": languages,
        "largest_source_files": largest,
        "ecosystems": group_ecosystems(manifests),
        "frameworks": frameworks,
        **platform_configs(root, files, frameworks),
        "infra": infra,
        "container_images": container_images(root, files, infra),
        "tests": {"test_files": sum(1 for f in files if TEST_RE.search(f)),
                  "coverage_reports": [f for f in files if PurePosixPath(f).name in COVERAGE_REPORTS]},
        "docs": {k: v for k, v in docs.items() if v},
        **secret_files(files, source == "git ls-files"),
        "git": git_history(root),
        "tools": probe_tools(),
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("repo", nargs="?", default=".")
    args = ap.parse_args()
    root = Path(args.repo).resolve()
    if not root.is_dir():
        print(f"not a directory: {root}", file=sys.stderr)
        return 2
    json.dump(inventory(root), sys.stdout, indent=2)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
