#!/usr/bin/env python3
"""ontology.py: a local-first typed graph of an application, for coding agents.

The graph lives in <repo>/.ontology/ (override with --dir or ONTOLOGY_DIR):
  schema.json   types, properties and relations this repo allows
  graph.jsonl   append-only log of operations, replayed on every read

Every write is validated against the schema before anything is appended.
A batch (`apply`) is all-or-nothing. Entities carry `sources` (repo-relative
`path` or `path:line`) and the git commit they were last verified at, so
`stale` can report entities whose code changed since.

Standard library only. Python 3.10+.

Exit codes: 0 ok, 1 validation failure or not found, 2 usage or missing store.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import uuid
from collections import deque
from datetime import datetime, timezone
from pathlib import Path

try:
    import fcntl  # POSIX only; writes are unlocked where it is missing.
except ImportError:  # pragma: no cover
    fcntl = None

SCRIPT_DIR = Path(__file__).resolve().parent
TEMPLATE_DIRS = [SCRIPT_DIR.parent / "templates", SCRIPT_DIR / "templates"]
CARDINALITIES = {"many_to_many", "many_to_one", "one_to_many", "one_to_one"}
TYPE_CHECKS = {
    "string": lambda v: isinstance(v, str),
    "number": lambda v: isinstance(v, (int, float)) and not isinstance(v, bool),
    "boolean": lambda v: isinstance(v, bool),
    "array": lambda v: isinstance(v, list),
    "object": lambda v: isinstance(v, dict),
}
# Never store secrets in a file agents read. Schemas may add to this list.
DEFAULT_FORBIDDEN = ["password", "secret", "token", "api_key", "private_key", "credential"]


class OntologyError(Exception):
    """A validation failure or missing entity. Exit code 1."""


class UsageError(Exception):
    """A bad invocation or missing store. Exit code 2."""


# ---------------------------------------------------------------- utilities

def now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def git(args: list[str], cwd: Path, stdin: str | None = None) -> str | None:
    try:
        out = subprocess.run(["git", *args], cwd=cwd, input=stdin, capture_output=True, text=True, check=True)
    except (OSError, subprocess.CalledProcessError):
        return None
    return out.stdout.strip()


def slug(text: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return s[:48].rstrip("-")


def parse_json(text: str, what: str) -> dict:
    try:
        value = json.loads(text)
    except json.JSONDecodeError as e:
        raise UsageError(f"{what} is not valid JSON: {e}") from None
    if not isinstance(value, dict):
        raise UsageError(f"{what} must be a JSON object")
    return value


def emit(value) -> None:
    print(json.dumps(value, indent=2, sort_keys=False))


# ---------------------------------------------------------------- store

class Store:
    def __init__(self, directory: Path):
        self.dir = directory
        self.schema_path = directory / "schema.json"
        self.graph_path = directory / "graph.jsonl"
        self.lock_path = directory / ".lock"
        top = git(["rev-parse", "--show-toplevel"], directory.parent if directory.parent.exists() else Path.cwd())
        self.repo_root = Path(top) if top else directory.parent

    @staticmethod
    def locate(explicit: str | None) -> "Store":
        if explicit:
            return Store(Path(explicit).resolve())
        env = os.environ.get("ONTOLOGY_DIR")
        if env:
            return Store(Path(env).resolve())
        top = git(["rev-parse", "--show-toplevel"], Path.cwd())
        return Store((Path(top) if top else Path.cwd()) / ".ontology")

    def exists(self) -> bool:
        return self.schema_path.exists()

    def require(self) -> None:
        if not self.exists():
            raise UsageError(f"no ontology at {self.dir}; run the setup wizard (`/ontology setup`) or `init`")

    def schema(self) -> dict:
        self.require()
        try:
            schema = json.loads(self.schema_path.read_text())
        except json.JSONDecodeError as e:
            raise UsageError(f"{self.schema_path} is not valid JSON: {e}") from None
        schema.setdefault("types", {})
        schema.setdefault("relations", {})
        return schema

    def head(self) -> str | None:
        return git(["rev-parse", "HEAD"], self.repo_root)

    def load(self) -> "Graph":
        graph = Graph()
        if not self.graph_path.exists():
            return graph
        with open(self.graph_path) as f:
            for n, line in enumerate(f, 1):
                line = line.strip()
                if not line:
                    continue
                try:
                    graph.replay(json.loads(line))
                except (json.JSONDecodeError, KeyError) as e:
                    raise UsageError(f"{self.graph_path}:{n}: unreadable record ({e})") from None
        return graph

    def append(self, records: list[dict]) -> None:
        self.dir.mkdir(parents=True, exist_ok=True)
        with open(self.graph_path, "a") as f:
            for r in records:
                f.write(json.dumps(r, sort_keys=True) + "\n")

    def lock(self):
        return _Lock(self.lock_path)


class _Lock:
    def __init__(self, path: Path):
        self.path = path
        self.fh = None

    def __enter__(self):
        if fcntl is not None:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            self.fh = open(self.path, "w")
            fcntl.flock(self.fh, fcntl.LOCK_EX)
        return self

    def __exit__(self, *exc):
        if self.fh:
            fcntl.flock(self.fh, fcntl.LOCK_UN)
            self.fh.close()


# ---------------------------------------------------------------- graph

class Graph:
    def __init__(self):
        self.entities: dict[str, dict] = {}
        self.edges: dict[tuple[str, str, str], dict] = {}

    def copy(self) -> "Graph":
        g = Graph()
        g.entities = copy.deepcopy(self.entities)
        g.edges = copy.deepcopy(self.edges)
        return g

    def replay(self, r: dict) -> None:
        op = r["op"]
        if op == "add":
            e = r["entity"]
            self.entities[e["id"]] = e
        elif op == "update":
            e = self.entities.get(r["id"])
            if e is None:
                return
            e["props"].update(r.get("set", {}))
            for k in r.get("unset", []):
                e["props"].pop(k, None)
            if "sources" in r:
                e["sources"] = r["sources"]
            if "verified" in r:
                e["verified"] = r["verified"]
            e["updated"] = r.get("ts", e.get("updated"))
        elif op == "remove":
            self.entities.pop(r["id"], None)
            self.edges = {k: v for k, v in self.edges.items() if r["id"] not in (k[0], k[2])}
        elif op == "link":
            self.edges[(r["from"], r["rel"], r["to"])] = {
                "from": r["from"], "rel": r["rel"], "to": r["to"], "props": r.get("props", {})}
        elif op == "unlink":
            self.edges.pop((r["from"], r["rel"], r["to"]), None)

    def out_edges(self, eid: str, rel: str | None = None) -> list[dict]:
        return [e for k, e in self.edges.items() if k[0] == eid and (rel is None or k[1] == rel)]

    def in_edges(self, eid: str, rel: str | None = None) -> list[dict]:
        return [e for k, e in self.edges.items() if k[2] == eid and (rel is None or k[1] == rel)]

    def reaches(self, start: str, goal: str, rel: str) -> bool:
        seen, stack = set(), [start]
        while stack:
            cur = stack.pop()
            if cur == goal:
                return True
            if cur in seen:
                continue
            seen.add(cur)
            stack.extend(e["to"] for e in self.out_edges(cur, rel))
        return False


# ---------------------------------------------------------------- validation

def forbidden_for(schema: dict, tdef: dict) -> set[str]:
    return set(schema.get("forbidden_properties", DEFAULT_FORBIDDEN)) | set(tdef.get("forbidden", []))


def check_props(schema: dict, etype: str, props: dict, eid: str) -> list[str]:
    errors = []
    tdef = schema["types"].get(etype)
    if tdef is None:
        if schema.get("strict", True):
            known = ", ".join(sorted(schema["types"])) or "none"
            return [f"{eid}: unknown type '{etype}' (schema allows: {known})"]
        tdef = {}
    for p in tdef.get("required", []):
        if props.get(p) in (None, ""):
            errors.append(f"{eid}: missing required property '{p}' for {etype}")
    bad = forbidden_for(schema, tdef) & {k.lower() for k in props}
    for p in sorted(bad):
        errors.append(f"{eid}: property '{p}' is forbidden (store a reference, never the secret)")
    pdefs = tdef.get("properties", {})
    for name, value in props.items():
        pdef = pdefs.get(name)
        if pdef is None:
            if tdef.get("additional_properties") is False:
                errors.append(f"{eid}: property '{name}' is not defined for {etype} "
                              f"(allowed: {', '.join(sorted(pdefs)) or 'none'}); "
                              "code locations go in sources, not properties")
            continue
        if "enum" in pdef and value not in pdef["enum"]:
            errors.append(f"{eid}: '{name}' must be one of {pdef['enum']}, got {value!r}")
        t = pdef.get("type")
        if t in TYPE_CHECKS and not TYPE_CHECKS[t](value):
            errors.append(f"{eid}: '{name}' must be a {t}, got {type(value).__name__}")
    return errors


def check_link(schema: dict, g: Graph, src: str, rel: str, dst: str, new: bool) -> list[str]:
    label = f"{src} -{rel}-> {dst}"
    errors = []
    for eid in (src, dst):
        if eid not in g.entities:
            errors.append(f"{label}: entity '{eid}' does not exist")
    if errors:
        return errors
    rdef = schema["relations"].get(rel)
    if rdef is None:
        if schema.get("strict", True):
            known = ", ".join(sorted(schema["relations"])) or "none"
            return [f"{label}: unknown relation '{rel}' (schema allows: {known})"]
        return []
    stype, dtype = g.entities[src]["type"], g.entities[dst]["type"]
    allowed_from, allowed_to = rdef.get("from", ["*"]), rdef.get("to", ["*"])
    if "*" not in allowed_from and stype not in allowed_from:
        errors.append(f"{label}: '{rel}' cannot start at a {stype} (allowed: {allowed_from})")
    if "*" not in allowed_to and dtype not in allowed_to:
        errors.append(f"{label}: '{rel}' cannot end at a {dtype} (allowed: {allowed_to})")
    card = rdef.get("cardinality", "many_to_many")
    outs = [e for e in g.out_edges(src, rel) if e["to"] != dst]
    ins = [e for e in g.in_edges(dst, rel) if e["from"] != src]
    if card in ("many_to_one", "one_to_one") and outs:
        errors.append(f"{label}: {src} already has a '{rel}' ({outs[0]['to']}); {card} allows one")
    if card in ("one_to_many", "one_to_one") and ins:
        errors.append(f"{label}: {dst} already has an incoming '{rel}' ({ins[0]['from']}); {card} allows one")
    if rdef.get("acyclic") and (src == dst or (new and g.reaches(dst, src, rel))):
        errors.append(f"{label}: would create a cycle in acyclic relation '{rel}'")
    return errors


def normalize_sources(store: Store, sources: list[str]) -> list[str]:
    out = []
    for s in sources:
        path, sep, loc = s.partition(":")
        p = Path(path)
        if p.is_absolute():
            try:
                p = p.resolve().relative_to(store.repo_root.resolve())
            except ValueError:
                raise OntologyError(f"source '{s}' is outside the repo ({store.repo_root})") from None
        out.append(p.as_posix() + (sep + loc if sep else ""))
    return out


def source_path(s: str) -> str:
    return s.split(":", 1)[0]


def _under(child: str, parent: str) -> bool:
    return child == parent or child.startswith(parent.rstrip("/") + "/")


def _hash_fs(root: Path, rel: str) -> str:
    """Content hash of a file or directory tree, for repos without git."""
    h = hashlib.sha256()
    target = root / rel
    files = [target] if target.is_file() else sorted(
        f for f in target.rglob("*") if f.is_file() and not any(part.startswith(".") for part in f.relative_to(target).parts))
    for f in files:
        h.update(f.relative_to(root).as_posix().encode() + b"\0")
        try:
            h.update(f.read_bytes())
        except OSError:
            h.update(b"<unreadable>")
    return h.hexdigest()


def fingerprints(store: Store, path_sets: list[list[str]]) -> list[str]:
    """One content fingerprint per path set, computed from the working tree.

    It changes when any file under those paths is edited, added (tracked or
    untracked, not ignored) or deleted, and is identical before and after
    committing the same content or switching to a branch with the same content.
    """
    root = store.repo_root
    every = sorted({p for ps in path_sets for p in ps})
    if not every:
        return ["" for _ in path_sets]
    listed = git(["ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", *every], root)
    if listed is None:
        cache = {p: _hash_fs(root, p) for p in every}
        return [hashlib.sha256("\n".join(f"{p}={cache[p]}" for p in sorted(ps)).encode()).hexdigest()
                for ps in path_sets]
    files = sorted({f for f in listed.split("\0") if f and (root / f).is_file()})
    ids = (git(["hash-object", "--stdin-paths"], root, "".join(f + "\n" for f in files)) or "").splitlines()
    blob = dict(zip(files, ids))
    out = []
    for ps in path_sets:
        h = hashlib.sha256()
        for f in files:
            if any(_under(f, p) for p in ps):
                h.update(f"{f}={blob.get(f, '?')}\n".encode())
        out.append(h.hexdigest())
    return out


def stamp(store: Store, sources: list[str], ts: str) -> dict | None:
    paths = sorted({source_path(s) for s in sources})
    if not paths:
        return None
    return {"fingerprint": fingerprints(store, [paths])[0], "commit": store.head(), "at": ts}


# ---------------------------------------------------------------- operations

def make_id(schema: dict, g: Graph, etype: str, props: dict) -> str:
    tdef = schema["types"].get(etype, {})
    prefix = tdef.get("prefix") or slug(etype)[:4] or "ent"
    for key in tdef.get("id_from", ["name", "title", "statement"]):
        if isinstance(props.get(key), str) and slug(props[key]):
            candidate = f"{prefix}:{slug(props[key])}"
            if candidate in g.entities:
                raise OntologyError(
                    f"id '{candidate}' already exists; pass an explicit id or update the existing entity")
            return candidate
    return f"{prefix}:{uuid.uuid4().hex[:6]}"


def apply_ops(store: Store, ops: list[dict], dry_run: bool = False) -> dict:
    """Validate a batch against the current graph, then append it whole or not at all."""
    schema = store.schema()
    with store.lock():
        g = store.load().copy()
        records, results, errors = [], [], []
        for i, op in enumerate(ops):
            kind = op.get("op")
            ts = now()
            where = f"op {i + 1} ({kind})"
            try:
                if kind == "add":
                    etype = op.get("type") or ""
                    props = op.get("props", {})
                    eid = op.get("id") or make_id(schema, g, etype, props)
                    if eid in g.entities:
                        raise OntologyError(f"{eid}: already exists; use update")
                    errs = check_props(schema, etype, props, eid)
                    if errs:
                        raise OntologyError("; ".join(errs))
                    sources = normalize_sources(store, op.get("sources", []))
                    entity = {"id": eid, "type": etype, "props": props, "sources": sources,
                              "verified": stamp(store, sources, ts), "created": ts, "updated": ts}
                    rec = {"op": "add", "entity": entity, "ts": ts}
                    results.append({"added": eid})
                elif kind == "update":
                    eid = op.get("id")
                    e = g.entities.get(eid)
                    if e is None:
                        raise OntologyError(f"{eid}: not found")
                    merged = {**e["props"], **op.get("set", {})}
                    for k in op.get("unset", []):
                        merged.pop(k, None)
                    errs = check_props(schema, e["type"], merged, eid)
                    if errs:
                        raise OntologyError("; ".join(errs))
                    rec = {"op": "update", "id": eid, "set": op.get("set", {}),
                           "unset": op.get("unset", []), "ts": ts}
                    if "sources" in op:
                        rec["sources"] = normalize_sources(store, op["sources"])
                    if "sources" in op or op.get("verify"):
                        rec["verified"] = stamp(store, rec.get("sources", e.get("sources", [])), ts)
                    results.append({"updated": eid})
                elif kind == "remove":
                    eid = op.get("id")
                    if eid not in g.entities:
                        raise OntologyError(f"{eid}: not found")
                    dropped = len(g.out_edges(eid)) + len(g.in_edges(eid))
                    rec = {"op": "remove", "id": eid, "ts": ts}
                    results.append({"removed": eid, "edges_removed": dropped})
                elif kind == "link":
                    src, rel, dst = op.get("from"), op.get("rel"), op.get("to")
                    key = (src, rel, dst)
                    exists = key in g.edges
                    errs = check_link(schema, g, src, rel, dst, new=not exists)
                    if errs:
                        raise OntologyError("; ".join(errs))
                    if exists and g.edges[key]["props"] == op.get("props", {}):
                        results.append({"exists": f"{src} -{rel}-> {dst}"})
                        continue
                    rec = {"op": "link", "from": src, "rel": rel, "to": dst,
                           "props": op.get("props", {}), "ts": ts}
                    results.append({"linked": f"{src} -{rel}-> {dst}"})
                elif kind == "unlink":
                    key = (op.get("from"), op.get("rel"), op.get("to"))
                    if key not in g.edges:
                        raise OntologyError(f"{key[0]} -{key[1]}-> {key[2]}: no such relation")
                    rec = {"op": "unlink", "from": key[0], "rel": key[1], "to": key[2], "ts": ts}
                    results.append({"unlinked": f"{key[0]} -{key[1]}-> {key[2]}"})
                else:
                    raise OntologyError(f"unknown op {kind!r} (add, update, remove, link, unlink)")
            except OntologyError as e:
                errors.append(f"{where}: {e}")
                continue
            g.replay(rec)
            records.append(rec)
        if errors:
            raise OntologyError("batch rejected, nothing written:\n  " + "\n  ".join(errors))
        if not dry_run:
            store.append(records)
    return {"dry_run": dry_run, "written": 0 if dry_run else len(records), "results": results}


def validate_all(store: Store) -> list[str]:
    schema = store.schema()
    g = store.load()
    errors = []
    for t, tdef in schema["types"].items():
        for p, pdef in tdef.get("properties", {}).items():
            if pdef.get("type") and pdef["type"] not in TYPE_CHECKS:
                errors.append(f"schema: {t}.{p} has unknown type '{pdef['type']}'")
    for r, rdef in schema["relations"].items():
        if rdef.get("cardinality", "many_to_many") not in CARDINALITIES:
            errors.append(f"schema: relation '{r}' has unknown cardinality '{rdef.get('cardinality')}'")
        for side in ("from", "to"):
            for t in rdef.get(side, ["*"]):
                if t != "*" and t not in schema["types"]:
                    errors.append(f"schema: relation '{r}' names unknown type '{t}' in '{side}'")
    for eid, e in sorted(g.entities.items()):
        errors.extend(check_props(schema, e["type"], e["props"], eid))
    for (src, rel, dst) in sorted(g.edges):
        # Re-check each edge with itself removed so it doesn't conflict with itself.
        probe = g.copy()
        probe.edges.pop((src, rel, dst))
        errors.extend(check_link(schema, probe, src, rel, dst, new=True))
    return errors


def stale_report(store: Store, ids: list[str] | None = None) -> list[dict]:
    g = store.load()
    report, pending = [], []
    for eid, e in sorted(g.entities.items()):
        if ids and eid not in ids:
            continue
        paths = sorted({source_path(s) for s in e.get("sources", [])})
        if not paths:
            continue
        missing = [p for p in paths if not (store.repo_root / p).exists()]
        if missing:
            report.append({"id": eid, "status": "missing", "paths": missing})
        elif not (e.get("verified") or {}).get("fingerprint"):
            report.append({"id": eid, "status": "unverified", "paths": paths})
        else:
            pending.append((eid, paths, e["verified"]))
    current = fingerprints(store, [ps for _, ps, _ in pending])
    for (eid, paths, verified), fp in zip(pending, current):
        if fp != verified["fingerprint"]:
            row = {"id": eid, "status": "changed", "paths": paths, "verified_at": verified.get("at")}
            if verified.get("commit"):
                row["verified_commit"] = verified["commit"][:12]
            report.append(row)
    return sorted(report, key=lambda r: r["id"])


# ---------------------------------------------------------------- reads

def entity_view(g: Graph, eid: str) -> dict:
    e = g.entities.get(eid)
    if e is None:
        raise OntologyError(f"{eid}: not found")
    return {**e,
            "out": [{"rel": x["rel"], "to": x["to"], **({"props": x["props"]} if x["props"] else {})}
                    for x in g.out_edges(eid)],
            "in": [{"rel": x["rel"], "from": x["from"], **({"props": x["props"]} if x["props"] else {})}
                   for x in g.in_edges(eid)]}


def brief(e: dict) -> dict:
    p = e["props"]
    label = next((p[k] for k in ("name", "title", "statement") if isinstance(p.get(k), str)), "")
    out = {"id": e["id"], "type": e["type"], "label": label}
    if isinstance(p.get("summary"), str):
        out["summary"] = p["summary"]
    if e.get("sources"):
        out["sources"] = e["sources"]
    return out


def find(store: Store, etype, where, text, source) -> list[dict]:
    g = store.load()
    needle = text.lower() if text else None
    src = source.rstrip("/") if source else None
    hits = []
    for e in g.entities.values():
        if etype and e["type"] != etype:
            continue
        if any(e["props"].get(k) != v for k, v in where.items()):
            continue
        if needle:
            hay = [e["id"]] + [v for v in e["props"].values() if isinstance(v, str)]
            hay += [x for v in e["props"].values() if isinstance(v, list) for x in v if isinstance(x, str)]
            if not any(needle in h.lower() for h in hay):
                continue
        if src:
            paths = [source_path(s) for s in e.get("sources", [])]
            if not any(p == src or p.startswith(src + "/") or src.startswith(p.rstrip("/") + "/")
                       for p in paths):
                continue
        hits.append(brief(e))
    return sorted(hits, key=lambda h: h["id"])


def neighbors(store: Store, eid: str, rel, direction: str, depth: int) -> dict:
    g = store.load()
    if eid not in g.entities:
        raise OntologyError(f"{eid}: not found")
    seen = {eid: 0}
    edges = []
    queue = deque([eid])
    while queue:
        cur = queue.popleft()
        if seen[cur] >= depth:
            continue
        steps = []
        if direction in ("out", "both"):
            steps += [(x, x["to"]) for x in g.out_edges(cur, rel)]
        if direction in ("in", "both"):
            steps += [(x, x["from"]) for x in g.in_edges(cur, rel)]
        for edge, nxt in steps:
            if edge not in edges:
                edges.append(edge)
            if nxt not in seen:
                seen[nxt] = seen[cur] + 1
                queue.append(nxt)
    nodes = [{**brief(g.entities[n]), "depth": d} for n, d in sorted(seen.items(), key=lambda x: (x[1], x[0]))
             if n in g.entities]
    return {"root": eid, "nodes": nodes,
            "edges": [{"from": e["from"], "rel": e["rel"], "to": e["to"]} for e in edges]}


def shortest_path(store: Store, src: str, dst: str, max_depth: int) -> list[dict] | None:
    g = store.load()
    for eid in (src, dst):
        if eid not in g.entities:
            raise OntologyError(f"{eid}: not found")
    prev: dict[str, tuple[str, dict, str] | None] = {src: None}
    queue = deque([(src, 0)])
    while queue:
        cur, d = queue.popleft()
        if cur == dst:
            break
        if d >= max_depth:
            continue
        for edge, nxt, direction in ([(x, x["to"], "out") for x in g.out_edges(cur)] +
                                     [(x, x["from"], "in") for x in g.in_edges(cur)]):
            if nxt not in prev:
                prev[nxt] = (cur, edge, direction)
                queue.append((nxt, d + 1))
    if dst not in prev:
        return None
    hops, cur = [], dst
    while prev[cur] is not None:
        before, edge, direction = prev[cur]
        hops.append({"from": edge["from"], "rel": edge["rel"], "to": edge["to"], "walked": direction})
        cur = before
    return list(reversed(hops))


def summary_text(store: Store, limit: int) -> str:
    schema = store.schema()
    g = store.load()
    counts: dict[str, int] = {}
    for e in g.entities.values():
        counts[e["type"]] = counts.get(e["type"], 0) + 1
    lines = [f"# Ontology: {store.repo_root.name}", "",
             f"{len(g.entities)} entities, {len(g.edges)} relations. Store: {store.dir}", ""]
    if not g.entities:
        lines.append("The graph is empty. Run the setup wizard to seed it.")
        return "\n".join(lines)
    lines.append("## Entities by type")
    for t in sorted(counts, key=lambda t: (-counts[t], t)):
        desc = schema["types"].get(t, {}).get("description", "")
        lines.append(f"- {t}: {counts[t]}" + (f" ({desc})" if desc else ""))
    for t in schema.get("summary_types", []):
        items = sorted((e for e in g.entities.values() if e["type"] == t), key=lambda e: e["id"])
        if not items:
            continue
        lines += ["", f"## {t}s"]
        for e in items[:limit]:
            b = brief(e)
            lines.append(f"- `{b['id']}` {b['label']}" + (f": {b['summary']}" if b.get("summary") else ""))
        if len(items) > limit:
            lines.append(f"- … {len(items) - limit} more (`find --type {t}`)")
    stale = stale_report(store)
    if stale:
        lines += ["", f"## Stale: {len(stale)} entities need re-checking (`stale`)"]
    return "\n".join(lines)


# ---------------------------------------------------------------- init

def template_path(name: str) -> Path:
    for d in TEMPLATE_DIRS:
        p = d / f"schema.{name}.json"
        if p.exists():
            return p
    names = sorted({p.name[len("schema."):-len(".json")] for d in TEMPLATE_DIRS if d.exists()
                    for p in d.glob("schema.*.json")})
    raise UsageError(f"unknown template '{name}' (available: {', '.join(names) or 'none'})")


def init(store: Store, template: str, shared: bool, force: bool) -> dict:
    src = template_path(template)
    store.dir.mkdir(parents=True, exist_ok=True)
    backed_up = None
    if store.schema_path.exists():
        if not force:
            raise UsageError(f"{store.schema_path} exists; pass --force to replace it (a .bak is kept)")
        backed_up = str(store.schema_path) + ".bak"
        shutil.copy2(store.schema_path, backed_up)
    shutil.copy2(src, store.schema_path)
    ignore = store.dir / ".gitignore"
    if shared:
        ignore.write_text(".lock\n*.bak\n")
    else:
        ignore.write_text("# Local-only ontology: nothing in this directory is committed.\n*\n")
    store.graph_path.touch()
    return {"initialized": str(store.dir), "template": template, "shared": shared,
            "schema_backup": backed_up}


def status(store: Store) -> dict:
    if not store.exists():
        return {"exists": False, "dir": str(store.dir), "repo_root": str(store.repo_root)}
    g = store.load()
    ignore = store.dir / ".gitignore"
    shared = not (ignore.exists() and any(line.strip() == "*" for line in ignore.read_text().splitlines()))
    return {"exists": True, "dir": str(store.dir), "repo_root": str(store.repo_root), "shared": shared,
            "entities": len(g.entities), "relations": len(g.edges),
            "types": sorted(store.schema()["types"])}


def compact(store: Store) -> dict:
    store.require()
    with store.lock():
        g = store.load()
        backup = str(store.graph_path) + ".bak"
        shutil.copy2(store.graph_path, backup)
        ts = now()
        records = [{"op": "add", "entity": e, "ts": ts} for _, e in sorted(g.entities.items())]
        records += [{"op": "link", **e, "ts": ts} for _, e in sorted(g.edges.items())]
        tmp = store.graph_path.with_suffix(".tmp")
        with open(tmp, "w") as f:
            for r in records:
                f.write(json.dumps(r, sort_keys=True) + "\n")
        os.replace(tmp, store.graph_path)
    return {"compacted": len(records), "backup": backup}


# ---------------------------------------------------------------- cli

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="ontology.py", description=__doc__.split("\n\n")[0])
    p.add_argument("--dir", help="ontology directory (default: $ONTOLOGY_DIR or <git root>/.ontology)")
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("init", help="create the store from a schema template")
    s.add_argument("--template", default="application")
    s.add_argument("--shared", action="store_true", help="allow committing the graph (default: local-only)")
    s.add_argument("--force", action="store_true", help="replace an existing schema (keeps a .bak)")

    sub.add_parser("status", help="does a store exist, and what is in it")
    sub.add_parser("types", help="print the schema: types, properties, relations")

    s = sub.add_parser("summary", help="markdown overview for an agent starting work")
    s.add_argument("--limit", type=int, default=25)

    s = sub.add_parser("add", help="add an entity")
    s.add_argument("--type", required=True)
    s.add_argument("--props", default="{}")
    s.add_argument("--id")
    s.add_argument("--source", action="append", default=[], help="repo path or path:line (repeatable)")

    s = sub.add_parser("update", help="change an entity's properties or sources")
    s.add_argument("--id", required=True)
    s.add_argument("--set", default="{}")
    s.add_argument("--unset", default="", help="comma-separated property names")
    s.add_argument("--source", action="append", help="replace sources (repeatable)")

    s = sub.add_parser("remove", help="remove an entity and every relation touching it")
    s.add_argument("--id", required=True)

    for name in ("link", "unlink"):
        s = sub.add_parser(name, help=f"{name} two entities")
        s.add_argument("--from", dest="src", required=True)
        s.add_argument("--rel", required=True)
        s.add_argument("--to", dest="dst", required=True)
        if name == "link":
            s.add_argument("--props", default="{}")

    s = sub.add_parser("apply", help="apply a JSONL batch of ops atomically")
    s.add_argument("--file", required=True, help="path, or - for stdin")
    s.add_argument("--dry-run", action="store_true")

    s = sub.add_parser("get", help="one entity with its relations")
    s.add_argument("--id", required=True)

    s = sub.add_parser("find", help="search entities")
    s.add_argument("--type")
    s.add_argument("--where", default="{}", help="exact-match properties as JSON")
    s.add_argument("--text", help="case-insensitive substring over id and string properties")
    s.add_argument("--source", help="entities whose sources touch this repo path")

    s = sub.add_parser("neighbors", help="walk relations out from an entity")
    s.add_argument("--id", required=True)
    s.add_argument("--rel")
    s.add_argument("--dir", dest="direction", choices=["out", "in", "both"], default="both")
    s.add_argument("--depth", type=int, default=1)

    s = sub.add_parser("path", help="shortest relation path between two entities")
    s.add_argument("--from", dest="src", required=True)
    s.add_argument("--to", dest="dst", required=True)
    s.add_argument("--max-depth", type=int, default=6)

    sub.add_parser("validate", help="re-check the whole graph against the schema")

    s = sub.add_parser("stale", help="entities whose source files changed since last verified")
    s.add_argument("--id", action="append")

    s = sub.add_parser("verify", help="mark entities as re-checked at the current commit")
    g = s.add_mutually_exclusive_group(required=True)
    g.add_argument("--id", action="append")
    g.add_argument("--all", action="store_true")

    sub.add_parser("compact", help="rewrite the log as a snapshot (keeps a .bak)")
    return p


def read_ops(path: str) -> list[dict]:
    text = sys.stdin.read() if path == "-" else Path(path).read_text()
    ops = []
    for n, line in enumerate(text.splitlines(), 1):
        if line.strip():
            try:
                ops.append(json.loads(line))
            except json.JSONDecodeError as e:
                raise UsageError(f"{path}:{n}: not valid JSON ({e})") from None
    return ops


def run(argv: list[str]) -> int:
    args = build_parser().parse_args(argv)
    store = Store.locate(args.dir)
    c = args.cmd
    if c == "init":
        emit(init(store, args.template, args.shared, args.force))
    elif c == "status":
        emit(status(store))
    elif c == "types":
        schema = store.schema()
        emit({"types": schema["types"], "relations": schema["relations"]})
    elif c == "summary":
        print(summary_text(store, args.limit))
    elif c == "add":
        emit(apply_ops(store, [{"op": "add", "type": args.type, "id": args.id,
                                "props": parse_json(args.props, "--props"), "sources": args.source}]))
    elif c == "update":
        op = {"op": "update", "id": args.id, "set": parse_json(args.set, "--set"),
              "unset": [k for k in args.unset.split(",") if k]}
        if args.source is not None:
            op["sources"] = args.source
        emit(apply_ops(store, [op]))
    elif c == "remove":
        emit(apply_ops(store, [{"op": "remove", "id": args.id}]))
    elif c == "link":
        emit(apply_ops(store, [{"op": "link", "from": args.src, "rel": args.rel, "to": args.dst,
                                "props": parse_json(args.props, "--props")}]))
    elif c == "unlink":
        emit(apply_ops(store, [{"op": "unlink", "from": args.src, "rel": args.rel, "to": args.dst}]))
    elif c == "apply":
        emit(apply_ops(store, read_ops(args.file), args.dry_run))
    elif c == "get":
        store.require()
        emit(entity_view(store.load(), args.id))
    elif c == "find":
        store.require()
        emit(find(store, args.type, parse_json(args.where, "--where"), args.text, args.source))
    elif c == "neighbors":
        store.require()
        emit(neighbors(store, args.id, args.rel, args.direction, args.depth))
    elif c == "path":
        store.require()
        hops = shortest_path(store, args.src, args.dst, args.max_depth)
        if hops is None:
            raise OntologyError(f"no path from {args.src} to {args.dst} within {args.max_depth} hops")
        emit(hops)
    elif c == "validate":
        errors = validate_all(store)
        emit({"valid": not errors, "errors": errors})
        return 1 if errors else 0
    elif c == "stale":
        store.require()
        report = stale_report(store, args.id)
        emit({"stale": len(report), "entities": report})
    elif c == "verify":
        store.require()
        ids = sorted(e for e, v in store.load().entities.items() if v.get("sources")) if args.all else args.id
        emit(apply_ops(store, [{"op": "update", "id": i, "verify": True} for i in ids]))
    elif c == "compact":
        emit(compact(store))
    return 0


def main() -> int:
    try:
        return run(sys.argv[1:])
    except OntologyError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    except UsageError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
