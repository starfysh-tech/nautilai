#!/usr/bin/env python3
"""Read a TDD profile and cut the TDD rules into per-role lane files.

Usage:
  profile.py get <file> <key>
      Exit 0: value printed. Exit 3: key absent or `unknown` (callers skip
      the step). Exit 2: unreadable file, missing/unclosed frontmatter, or a
      present-but-empty value — each would otherwise pass as a silent skip.
  profile.py cut <tdd.md> <worker|review> [profile]
      Print the sections marked for the role (stack sections only when the
      profile's `stack` lists them), then the profile's prose body.
"""
import re
import sys


class ProfileError(Exception):
    pass


def frontmatter(path):
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except OSError as e:
        raise ProfileError(f"cannot read {path}: {e.strerror}")
    if not lines or lines[0].strip() != "---":
        raise ProfileError(f"{path}: no frontmatter")
    for i, line in enumerate(lines[1:], start=1):
        if line.strip() == "---":
            return lines[1:i]
    raise ProfileError(f"{path}: frontmatter not closed")


def get(path, key):
    for line in frontmatter(path):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        name, sep, value = line.partition(":")
        if not sep:
            raise ProfileError(f"{path}: frontmatter line has no ':': {line.strip()}")
        if name.strip() != key:
            continue
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        if not value:
            raise ProfileError(f"{path}: {key} is present but empty")
        return None if value == "unknown" else value
    return None


ROLES = {"worker", "review"}
OPEN = re.compile(r"^<!-- tdd: roles=([\w,]+)(?: stack=(\w+))? -->$")
CLOSE = "<!-- /tdd -->"


def body(path):
    with open(path, encoding="utf-8") as f:
        lines = f.read().splitlines()
    end = next(i for i, line in enumerate(lines[1:], start=1) if line.strip() == "---")
    return "\n".join(lines[end + 1:]).strip()


def cut(rules_path, role, profile_path):
    if role not in ROLES:
        raise ProfileError(f"unknown role {role!r}")
    stacks = set()
    if profile_path:
        stacks = {s.strip() for s in (get(profile_path, "stack") or "").split(",") if s.strip()}
    with open(rules_path, encoding="utf-8") as f:
        lines = f.read().splitlines()
    out, keep, inside = [], False, False
    for n, line in enumerate(lines, start=1):
        m = OPEN.match(line.strip())
        if m:
            if inside:
                raise ProfileError(f"{rules_path}:{n}: section opened inside a section")
            roles = set(m.group(1).split(","))
            if not roles <= ROLES:
                raise ProfileError(f"{rules_path}:{n}: unknown role in {sorted(roles - ROLES)}")
            inside, keep = True, role in roles and (m.group(2) is None or m.group(2) in stacks)
            continue
        if line.strip() == CLOSE:
            if not inside:
                raise ProfileError(f"{rules_path}:{n}: close without open")
            inside = False
            if keep:
                out.append("")
            continue
        if line.strip().startswith("<!-- tdd"):
            raise ProfileError(f"{rules_path}:{n}: malformed marker")
        if inside and keep:
            out.append(line)
    if inside:
        raise ProfileError(f"{rules_path}: section not closed")
    if not out:
        raise ProfileError(f"{rules_path}: no section for role {role!r}")
    out.append("## Project TDD profile\n")
    out.append(body(profile_path) if profile_path else "no project TDD profile")
    return "\n".join(out) + "\n"


def main(argv):
    try:
        if len(argv) == 4 and argv[1] == "get":
            value = get(argv[2], argv[3])
            if value is None:
                return 3
            print(value)
            return 0
        if len(argv) in (4, 5) and argv[1] == "cut":
            profile_path = argv[4] if len(argv) == 5 and argv[4] else None
            sys.stdout.write(cut(argv[2], argv[3], profile_path))
            return 0
    except ProfileError as e:
        print(f"profile.py: {e}", file=sys.stderr)
        return 2
    print("usage: profile.py get <file> <key> | cut <tdd.md> <worker|review> [profile]", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
