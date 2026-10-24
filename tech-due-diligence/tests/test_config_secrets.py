#!/usr/bin/env python3
"""Self-contained tests for tech-due-diligence's config_secrets.py.

Builds throwaway config files under a temp dir. Run directly:

    python3 tech-due-diligence/tests/test_config_secrets.py
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

_SCRIPTS = Path(__file__).resolve().parents[1] / "skills" / "tech-due-diligence" / "scripts"
sys.path.insert(0, str(_SCRIPTS))
import config_secrets as cs  # noqa: E402

FAILURES = []

# Assembled at runtime so no secret-shaped literal sits in this repo.
LIVE = "Kq7" + "-mule-Orbit-" + "Fen42"
DB_URL = "postgres://app:" + LIVE + "@db:5432/app"


def check(label, cond, detail=""):
    print(f"  {'ok  ' if cond else 'FAIL'} {label}" + ("" if cond else f" {detail}"))
    if not cond:
        FAILURES.append(label)


def write(root, rel, body):
    p = Path(root) / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(body)


def by_key(found):
    return {(f["file"], f["key"]): f for f in found}


def test_scan_and_view():
    with tempfile.TemporaryDirectory() as root:
        write(root, "fly.toml", f"[env]\n  SMTP_PASS = '{LIVE}'\n  APP_PORT = '8080'\n  API_TOKEN = '${{API_TOKEN}}'\n")
        write(root, "config/app.yaml", f"db:\n  password: changeme\n  url: {DB_URL}\n  min_password_length: 12\n")
        write(root, "deploy.yml", "permissions:\n  id-token: write\nenv:\n  DB_SECRET_ID: prod/app/db\n")
        write(root, "env.example", f"SECRET_KEY={LIVE}\n")
        write(root, ".env", f"BUCKET=assets\nAWS_SECRET_ACCESS_KEY={LIVE}\n")
        found = by_key(cs.scan(Path(root)))

        check("literal password in fly.toml found", found.get(("fly.toml", "SMTP_PASS"), {}).get("kind") == "literal", found)
        check("value length reported, not value", found[("fly.toml", "SMTP_PASS")]["value_length"] == len(LIVE))
        check("no value anywhere in scan output", LIVE not in repr(list(found.values())))
        check("env reference classified", found.get(("fly.toml", "API_TOKEN"), {}).get("kind") == "reference", found)
        check("non-credential key skipped", ("fly.toml", "APP_PORT") not in found, found)
        check("placeholder classified", found.get(("config/app.yaml", "password"), {}).get("kind") == "placeholder", found)
        check("credential URL found", found.get(("config/app.yaml", "url"), {}).get("kind") == "credential-url", found)
        check("numeric length setting skipped", ("config/app.yaml", "min_password_length") not in found, found)
        check("id-token permission skipped", ("deploy.yml", "id-token") not in found, found)
        check("secret identifier skipped", ("deploy.yml", "DB_SECRET_ID") not in found, found)
        check("template flagged", found.get(("env.example", "SECRET_KEY"), {}).get("template") is True, found)
        check("env file secret found", found.get((".env", "AWS_SECRET_ACCESS_KEY"), {}).get("env_file") is True, found)
        check("non-credential env key skipped", (".env", "BUCKET") not in found, found)
        check("outside git, nothing is tracked", not any(f["tracked_in_git"] for f in found.values()))

        for rel in ("fly.toml", "config/app.yaml", ".env"):
            text = cs.view(Path(root) / rel)
            check(f"view of {rel} hides the value", LIVE not in text, text)
        env_view = cs.view(Path(root) / ".env")
        check("view masks every value in an env file", "assets" not in env_view and "<redacted" in env_view, env_view)
        check("view keeps ordinary settings", "8080" in cs.view(Path(root) / "fly.toml"))


def test_context():
    with tempfile.TemporaryDirectory() as root:
        git = ["git", "-C", root, "-c", "user.name=t", "-c", "user.email=t@example.invalid"]
        body = f"import os\n\n\ndef client():\n    key = '{LIVE}'\n    backup = '{LIVE}'\n    return key\n"
        write(root, "app/client.py", body)
        write(root, "notes.txt", f"one\ntwo\n{LIVE}\nfour\n")
        subprocess.run(git[:3] + ["init", "-q"], check=True)
        subprocess.run(git + ["add", "."], check=True)
        subprocess.run(git + ["commit", "-qm", "add"], check=True)
        commit = subprocess.run(git[:3] + ["rev-parse", "HEAD"], capture_output=True, text=True, check=True).stdout.strip()
        write(root, "app/client.py", "import os\n")
        col = body.splitlines()[4].index("key") + 1
        report = [
            # Columns shifted by one, as gitleaks reports for some hits.
            {"RuleID": "generic-api-key", "File": "app/client.py", "Commit": commit, "StartLine": 5, "EndLine": 5,
             "StartColumn": col + 1, "EndColumn": col + len(f"key = '{LIVE}'"), "Match": "key = 'REDACTED'"},
            {"RuleID": "private-key", "File": "notes.txt", "Commit": "", "StartLine": 2, "EndLine": 3,
             "StartColumn": 1, "EndColumn": 4, "Match": "REDACTED"},
        ]
        rp = Path(root) / "gitleaks.json"
        rp.write_text(json.dumps(report))
        out = cs.context(Path(root), rp)
        check("context hides the flagged value", LIVE not in out, out)
        check("context hides the value on an unflagged nearby line", "backup = '<redacted" in out, out)
        check("context reads the flagged commit, not the working tree", "def client" in out, out)
        check("context keeps surrounding lines", "return key" in out and "four" in out, out)
        check("context masks a multi-line hit whole", out.count("<redacted line>") == 2, out)


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_") and callable(fn):
            print(name)
            fn()
    if FAILURES:
        print(f"\n{len(FAILURES)} failed")
        sys.exit(1)
    print("\nall passed")
