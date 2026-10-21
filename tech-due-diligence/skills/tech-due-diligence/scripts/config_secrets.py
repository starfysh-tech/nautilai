#!/usr/bin/env python3
"""Find credential-named settings in config files without printing their values.

Stdlib only.

    python3 config_secrets.py scan <repo-path>     # JSON list of findings
    python3 config_secrets.py view <file>          # the file, credential values masked
    python3 config_secrets.py context <repo-path> <gitleaks.json>   # each gitleaks hit, masked

gitleaks matches known token shapes; a hand-picked password in a TOML, YAML, or env file has
no shape, so it passes. This script matches on the setting's name instead.
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path, PurePosixPath

sys.path.insert(0, str(Path(__file__).resolve().parent))
from inventory import list_files  # noqa: E402

CONFIG_SUFFIXES = {
    ".toml", ".yaml", ".yml", ".json", ".ini", ".cfg", ".conf", ".properties",
    ".xcconfig", ".tfvars", ".plist", ".env",
}
ENV_NAME_RE = re.compile(r"^\.env(\..+)?$|\.env$|^env\.(example|sample|template)$")
CRED_URL_RE = re.compile(r"://[^/\s:@'\"]+:[^@\s'\"]+@")
CRED_WORDS = {"pass", "password", "passwd", "pwd", "secret", "token", "credential", "credentials",
              "apikey", "dsn", "passphrase"}
CRED_PAIRS = {("api", "key"), ("access", "key"), ("private", "key"), ("auth", "key"),
              ("signing", "key"), ("encryption", "key"), ("client", "secret")}
NON_CRED_WORDS = {"length", "min", "max", "ttl", "expiry", "expires", "url", "uri", "endpoint",
                  "file", "path", "type", "name", "fail", "policy", "rotation", "enabled", "header", "arn"}
# A trailing "id" names an identifier (APPLICATION_DB_SECRET_ID); a leading one is GitHub's id-token permission.
ID_WORDS = {"id", "ids"}
TEMPLATE_RE = re.compile(r"example|sample|template|\.dist$", re.I)


def is_cred_key(key: str) -> bool:
    words = [w.lower() for w in re.split(r"[_.\-\s]+|(?<=[a-z])(?=[A-Z])", key) if w]
    if not words or NON_CRED_WORDS & set(words) or words[-1] in ID_WORDS or words[0] in ID_WORDS:
        return False
    return bool(CRED_WORDS & set(words)) or any(p in CRED_PAIRS for p in zip(words, words[1:]))


# KEY = 'value' | KEY: value | KEY=value | "key": "value"
ASSIGN_RE = re.compile(
    r"""^(?P<pre>\s*(?:-\s*)?(?:export\s+)?["']?(?P<key>[A-Za-z0-9_.\-]+)["']?\s*(?:=|:)\s*)(?P<val>.*?)\s*,?\s*$"""
)
REFERENCE_RE = re.compile(r"^\$\{|^\$[A-Za-z_]|\{\{|^env\(|^secret\(|^!(Ref|Sub|GetAtt)|^arn:|^vault:|^op://|^ssm:")
PLACEHOLDER_RE = re.compile(
    r"^(|null|none|~|true|false|changeme|change[_-]?me|example|placeholder|dummy|xxx+|\*+|<[^>]*>|your[_-].*|todo|tbd|secret|password|test|\.\.\.)$",
    re.I,
)
MAX_BYTES = 300_000


def is_config(path: str) -> bool:
    p = PurePosixPath(path)
    return p.suffix.lower() in CONFIG_SUFFIXES or bool(ENV_NAME_RE.search(p.name))


def unquote(val: str) -> str:
    val = re.sub(r"\s+#.*$", "", val).strip()
    if len(val) >= 2 and val[0] == val[-1] and val[0] in "'\"":
        val = val[1:-1]
    return val.strip()


def classify(val: str) -> str:
    v = unquote(val)
    if REFERENCE_RE.search(v):
        return "reference"
    if PLACEHOLDER_RE.match(v):
        return "placeholder"
    if v.startswith(("{", "[")) or v in ("|", ">"):
        return "structured"
    if re.fullmatch(r"-?\d+(\.\d+)?", v):
        return "number"
    return "literal"


def scan_lines(text: str, env_file: bool):
    for n, line in enumerate(text.splitlines(), 1):
        if line.lstrip().startswith(("#", "//", ";")):
            continue
        m = ASSIGN_RE.match(line)
        if not m or not m.group("val"):
            continue
        key, val = m.group("key"), m.group("val")
        if env_file or is_cred_key(key) or CRED_URL_RE.search(val):
            yield n, line, m, key, val


def scan(root: Path) -> list[dict]:
    files, source = list_files(root)
    out = []
    for f in files:
        if not is_config(f):
            continue
        path = root / f
        try:
            if path.stat().st_size > MAX_BYTES:
                continue
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        env_file = bool(ENV_NAME_RE.search(PurePosixPath(f).name))
        for n, _line, _m, key, val in scan_lines(text, env_file):
            kind = "credential-url" if CRED_URL_RE.search(val) else classify(val)
            if kind in ("structured", "number") or (not is_cred_key(key) and kind != "credential-url"):
                continue
            out.append({
                "file": f, "line": n, "key": key, "kind": kind,
                "value_length": len(unquote(val)), "env_file": env_file,
                "template": bool(TEMPLATE_RE.search(f)),
                "tracked_in_git": source == "git ls-files",
            })
    return out


def mask_lines(text: str, env_file: bool) -> list[str]:
    masked = text.splitlines()
    for n, line, m, _key, val in scan_lines(text, env_file):
        if env_file or CRED_URL_RE.search(val) or classify(val) in ("literal", "placeholder"):
            masked[n - 1] = f"{m.group('pre')}<redacted, {len(unquote(val))} chars>"
    return masked


def view(path: Path) -> str:
    text = path.read_text(encoding="utf-8", errors="replace")
    masked = mask_lines(text, bool(ENV_NAME_RE.search(path.name)))
    return "\n".join(f"{i:6}\t{l}" for i, l in enumerate(masked, 1))


def _source(root: Path, name: str, commit: str):
    if commit:
        got = subprocess.run(["git", "-C", str(root), "show", f"{commit}:{name}"],
                             capture_output=True, text=True, errors="replace")
        return got.stdout if got.returncode == 0 else None
    path = Path(name) if Path(name).is_absolute() else root / name
    return path.read_text(encoding="utf-8", errors="replace") if path.is_file() else None


def _locate(f: dict, line: str):
    """Span and value of a single-line redacted gitleaks hit, or None when it cannot be pinned."""
    prefix, sep, suffix = f.get("Match", "").partition("REDACTED")
    size = f["EndColumn"] - f["StartColumn"] + 1 - len(prefix) - len(suffix)
    if not sep or size < 1:
        return None
    # Columns drift by one in some gitleaks hits, so find the match text instead of slicing by column.
    hits = list(re.finditer(re.escape(prefix) + f"(.{{{size}}})" + re.escape(suffix), line))
    if not hits:
        return None
    m = min(hits, key=lambda h: abs(h.start() - (f["StartColumn"] - 1)))
    return m.start(), m.end(), m.group(1)


def context(root: Path, report: Path, around: int = 3) -> str:
    findings = json.loads(report.read_text() or "[]") or []
    texts = {(f["File"], f.get("Commit") or ""): None for f in findings}
    for key in texts:
        texts[key] = _source(root, *key)
    spans, values = {}, set()
    for i, f in enumerate(findings):
        text = texts[(f["File"], f.get("Commit") or "")]
        if text is None or f["StartLine"] != (f.get("EndLine") or f["StartLine"]):
            continue
        lines = text.splitlines()
        if f["StartLine"] <= len(lines):
            spans[i] = _locate(f, lines[f["StartLine"] - 1])
            if spans[i] and len(spans[i][2]) >= 4:
                values.add(spans[i][2])
    # The same value often recurs on nearby lines or in other hits, so mask every recovered value everywhere.
    values = sorted(values, key=len, reverse=True)

    out = []
    for i, f in enumerate(findings):
        name, commit = f["File"], f.get("Commit") or ""
        start, end = f["StartLine"], f.get("EndLine") or f["StartLine"]
        out.append(f"## {i + 1}. {f['RuleID']} {name}:{start}" + (f" @ {commit[:8]}" if commit else ""))
        text = texts[(name, commit)]
        if text is None:
            out.append("(source not readable)")
            continue
        raw = text.splitlines()
        masked = mask_lines(text, bool(ENV_NAME_RE.search(PurePosixPath(name).name)))
        for n in range(max(1, start - around), min(len(raw), end + around) + 1):
            line = masked[n - 1]
            if start <= n <= end:
                span = spans.get(i)
                if span:
                    a, b, _ = span
                    line = f"{raw[n - 1][:a]}<redacted match, {b - a} chars>{raw[n - 1][b:]}"
                else:
                    line = "<redacted line>"
            for v in values:
                line = line.replace(v, f"<redacted, {len(v)} chars>")
            out.append(f"{n:6}\t{line}")
    return "\n".join(out)


def main() -> int:
    if sys.argv[1:2] == ["context"] and len(sys.argv) == 4:
        print(context(Path(sys.argv[2]).resolve(), Path(sys.argv[3])))
        return 0
    if len(sys.argv) != 3 or sys.argv[1] not in ("scan", "view"):
        print(__doc__, file=sys.stderr)
        return 2
    target = Path(sys.argv[2]).resolve()
    if sys.argv[1] == "scan":
        json.dump(scan(target), sys.stdout, indent=2)
        print()
    else:
        print(view(target))
    return 0


if __name__ == "__main__":
    sys.exit(main())
