#!/usr/bin/env python3
"""Self-contained tests for tech-due-diligence's inventory.py.

Builds throwaway repos under a temp dir — no network, no third-party runner.
Run directly:

    python3 tech-due-diligence/tests/test_inventory.py
"""
import importlib.util
import os
import subprocess
import sys
import tempfile
from pathlib import Path

# Loaded by path: the script ships standalone, not as an importable package.
_SCRIPT = (
    Path(__file__).resolve().parents[1]
    / "skills" / "tech-due-diligence" / "scripts" / "inventory.py"
)
_spec = importlib.util.spec_from_file_location("inventory", _SCRIPT)
assert _spec and _spec.loader, f"cannot load inventory at {_SCRIPT}"
inv = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(inv)

FAILURES = []


def check(label, cond, detail=""):
    if cond:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label} {detail}")
        FAILURES.append(label)


def write(root, rel, body=""):
    p = Path(root) / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(body)


def git(root, *args, name="t", email="t@example.invalid"):
    # CI runners have no git identity; pass one per call instead of mutating config.
    env = {**os.environ, "GIT_AUTHOR_NAME": name, "GIT_AUTHOR_EMAIL": email,
           "GIT_COMMITTER_NAME": name, "GIT_COMMITTER_EMAIL": email}
    subprocess.run(["git", *args], cwd=root, check=True, capture_output=True, env=env)


def mixed_repo(root):
    write(root, "server/manage.py", "import django\n")
    write(root, "server/requirements.txt", "Django==4.2\ndjangorestframework\ncelery\n")
    write(root, "server/app/settings/__init__.py")
    write(root, "server/app/settings/production.py", "DEBUG = False\n")
    write(root, "server/app/tests/test_views.py", "def test_x():\n    pass\n")
    write(root, "web/package.json", '{"dependencies": {"react": "18", "next": "14"}}')
    write(root, "web/package-lock.json", "{}")
    write(root, "web/src/App.test.tsx", "test('x', () => {})\n")
    write(root, "svc/go.mod", "module x\n")
    write(root, "svc/go.sum", "")
    write(root, "Dockerfile", "FROM python:3.12 AS builder\nRUN true\nFROM builder\n")
    write(root, "docker-compose.yml", "services:\n  db:\n    image: postgres:16-alpine\n")
    write(root, ".github/workflows/ci.yml", "on: push\n")
    write(root, "infra/main.tf", 'resource "x" "y" {}\n')
    write(root, "k8s/deploy.yaml", "apiVersion: apps/v1\nkind: Deployment\nspec:\n  containers:\n    - image: ghcr.io/acme/api:1.4\n")
    write(root, "README.md", "# x\n")
    write(root, "docs/adr/0001-record.md", "# ADR\n")
    write(root, ".env.production", "placeholder\n")
    write(root, ".env.example", "placeholder\n")
    write(root, "config/production.env", "placeholder\n")
    write(root, "env.example", "placeholder\n")
    write(root, ".gitignore", "node_modules/\n.venv/\n")
    # Ignored or untracked trees that must never reach the inventory.
    write(root, "web/node_modules/lodash/package.json", '{"dependencies": {"vue": "3"}}')
    write(root, ".venv/lib/site-packages/pkg/settings.py", "DEBUG = True\n")


def test_git_repo():
    """git ls-files scopes the inventory to tracked files only."""
    with tempfile.TemporaryDirectory() as root:
        mixed_repo(root)
        git(root, "init", "-q")
        git(root, "add", ".")
        git(root, "commit", "-qm", "init")
        write(root, ".claude/worktrees/feature/server/app/settings.py", "DEBUG = True\n")
        d = inv.inventory(Path(root))

        check("file source is git", d["file_source"] == "git ls-files", d["file_source"])
        paths = set()
        for e in d["ecosystems"].values():
            paths.update(e["manifests"] + e["lockfiles"])
        check("node_modules excluded", not any("node_modules" in p for p in paths), paths)
        check("vue from node_modules not detected", "vue" not in d["frameworks"], d["frameworks"])
        check("python, node, go detected", {"python", "node", "go"} <= set(d["ecosystems"]), d["ecosystems"])
        check("node lockfile found", d["ecosystems"]["node"]["lockfiles"] == ["web/package-lock.json"])
        check("django detected via manage.py", "server/manage.py" in d["frameworks"].get("django", []))
        check("react and nextjs detected", {"react", "nextjs"} <= set(d["frameworks"]))
        check("celery detected", "celery" in d["frameworks"])
        check("settings package found", "server/app/settings/production.py" in d["django_settings_modules"],
              d["django_settings_modules"])
        check("worktree and .venv settings excluded",
              not any(".venv" in s or "worktrees" in s for s in d["django_settings_modules"]),
              d["django_settings_modules"])
        for kind in ("dockerfile", "compose", "ci:github-actions", "terraform", "kubernetes"):
            check(f"infra {kind}", kind in d["infra"], d["infra"])
        check("test files counted", d["tests"]["test_files"] == 2, d["tests"])
        check("tracked env files reported, templates skipped",
              sorted(d["tracked_env_files"]) == [".env.production", "config/production.env"],
              d["tracked_env_files"])
        check("adr and readme found", {"adr", "readme"} <= set(d["docs"]), d["docs"])
        refs = {(i["ref"], i["file"]) for i in d["container_images"]}
        check("Dockerfile base image listed", ("python:3.12", "Dockerfile") in refs, d["container_images"])
        check("k8s image listed", ("ghcr.io/acme/api:1.4", "k8s/deploy.yaml") in refs, d["container_images"])
        check("compose image listed", ("postgres:16-alpine", "docker-compose.yml") in refs, d["container_images"])
        check("build stage alias not listed", not any(i["ref"] == "builder" for i in d["container_images"]),
              d["container_images"])
        check("git history counted", d["git"]["commits"] == 1 and d["git"]["authors_all_time"] == 1, d["git"])
        check("python lines counted", d["languages"]["Python"]["files"] >= 3, d["languages"])
        check("largest files listed", d["largest_source_files"][0]["lines"] >= 1, d["largest_source_files"])
        check("churn listed", any(c["path"] == "server/manage.py"
                                  for c in d["git"]["most_changed_files_last_12_months"]), d["git"])


def test_non_git_walk():
    """Outside git, the walk prunes dependency and build trees."""
    with tempfile.TemporaryDirectory() as root:
        mixed_repo(root)
        d = inv.inventory(Path(root))
        check("file source is walk", d["file_source"].startswith("directory walk"), d["file_source"])
        check("git is null", d["git"] is None, d["git"])
        check("walk prunes node_modules", "vue" not in d["frameworks"], d["frameworks"])
        check("walk prunes .venv", not any(".venv" in s for s in d["django_settings_modules"]),
              d["django_settings_modules"])
        check("walk lists env files as untracked", d["tracked_env_files"] == [] and
              sorted(d["untracked_env_files"]) == [".env.production", "config/production.env"], (d["tracked_env_files"], d["untracked_env_files"]))


def test_apple_app():
    """An XcodeGen iOS app with no Package.resolved is detected as apple-app."""
    with tempfile.TemporaryDirectory() as root:
        write(root, "project.yml", "name: App\ntargets:\n  App:\n    type: application\n    platform: iOS\n")
        write(root, "App/Info.plist", "<plist/>\n")
        write(root, "App/App.entitlements", "<plist/>\n")
        write(root, "App/ContentView.swift", "import SwiftUI\n")
        write(root, "docs/project.yml", "name: not-xcode\n")
        write(root, "pods/Podfile.lock", "PODS:\n")
        write(root, "certs/dist.p12", "x")
        write(root, "docs/keyboard.md", "x")
        d = inv.inventory(Path(root))
        check("apple-app detected", "apple-app" in d["frameworks"], d["frameworks"])
        check("apple config listed", sorted(d["apple_config_files"]) ==
              ["App/App.entitlements", "App/Info.plist", "project.yml"], d["apple_config_files"])
        check("swift lockfile found", d["ecosystems"].get("swift", {}).get("lockfiles") == ["pods/Podfile.lock"],
              d["ecosystems"])
        check("key material listed as untracked outside git", d["untracked_key_material"] == ["certs/dist.p12"]
              and d["tracked_key_material"] == [], (d["tracked_key_material"], d["untracked_key_material"]))
        check("swift lines counted", d["languages"].get("Swift", {}).get("files") == 1, d["languages"])


def test_checkout_staleness():
    """A clone that is behind its fetched upstream reports the gap without fetching."""
    with tempfile.TemporaryDirectory() as tmp:
        up, clone = Path(tmp) / "up", Path(tmp) / "clone"
        write(up, "a.txt", "1\n")
        git(up, "init", "-q", "-b", "main")
        git(up, "add", ".")
        git(up, "commit", "-qm", "one")
        git(tmp, "clone", "-q", str(up), str(clone))
        for n in ("two", "three"):
            write(up, "a.txt", n + "\n")
            git(up, "commit", "-qam", n)
        git(clone, "fetch", "-q")
        write(clone, "local.txt", "x\n")
        c = inv.inventory(clone)["git"]["checkout"]
        check("branch and upstream", c["branch"] == "main" and c["upstream"] == "origin/main", c)
        check("behind counted", c["behind"] == 2 and c["ahead"] == 0, c)
        check("last fetch recorded", bool(c["last_fetch"]), c)
        check("uncommitted counted", c["uncommitted_changes"] == 1, c)


def test_identity_merge():
    """One person committing under two names and two emails counts as one author."""
    with tempfile.TemporaryDirectory() as root:
        write(root, "a.txt", "0\n")
        git(root, "init", "-q")
        ids = [("Pat", "pat@home.invalid"), ("Pat Lee", "pat@home.invalid"),
               ("Pat Lee", "pat@work.invalid"), ("Sam", "sam@work.invalid")]
        for i, (name, email) in enumerate(ids):
            write(root, "a.txt", f"{i}\n")
            git(root, "add", ".")
            git(root, "commit", "-qm", str(i), name=name, email=email)
        g = inv.inventory(Path(root))["git"]
        check("two people, not four", g["authors_all_time"] == 2, g["top_authors"])
        check("merged share is 0.75", g["top_authors"][0]["share"] == 0.75, g["top_authors"])


def test_android_app():
    """A Gradle Android app is detected and its config files listed."""
    with tempfile.TemporaryDirectory() as root:
        write(root, "app/build.gradle.kts", 'plugins { id("com.android.application") }\n')
        write(root, "app/src/main/AndroidManifest.xml", "<manifest/>\n")
        write(root, "app/src/main/res/xml/network_security_config.xml", "<network-security-config/>\n")
        write(root, "app/src/main/java/Main.kt", "fun main() {}\n")
        d = inv.inventory(Path(root))
        check("android detected", "android" in d["frameworks"], d["frameworks"])
        check("android config listed", len(d["android_config_files"]) == 2, d["android_config_files"])
        check("kotlin counted", "Kotlin" in d["languages"], d["languages"])


def test_no_manifests():
    """A repo with no package manifests yields empty sections, not errors."""
    with tempfile.TemporaryDirectory() as root:
        write(root, "notes.txt", "x\n")
        write(root, "fly.toml", "app = 'demo'\n\n[build]\n  image = 'acme/app:2.1'\n")
        d = inv.inventory(Path(root))
        check("fly.toml image listed", d["container_images"] == [{"ref": "acme/app:2.1", "file": "fly.toml", "line": 4}],
              d["container_images"])
        check("no ecosystems", d["ecosystems"] == {}, d["ecosystems"])
        check("no frameworks", d["frameworks"] == {}, d["frameworks"])
        check("tools probed", "git" in d["tools"], d["tools"])


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_") and callable(fn):
            print(name)
            fn()
    if FAILURES:
        print(f"\n{len(FAILURES)} failed")
        sys.exit(1)
    print("\nall passed")
