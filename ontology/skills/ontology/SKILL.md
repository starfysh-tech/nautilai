---
name: ontology
description: 'Local-first, technology-agnostic map of how an application works (areas of responsibility, actors, capabilities, domain concepts, processes, events, rules, decisions) that coding agents query before reading code and keep current as they work. Use when the user runs /ontology, says "set up the ontology", "map this codebase", "what depends on X", "where is X handled", "how does X work", or when starting a coding task in a repo that has a .ontology/ directory. Subcommands: setup | refresh | (default) query.'
argument-hint: "[setup | refresh | <question>]"
---

# Ontology

> **omp / pi:** these runtimes don't expand the `CLAUDE_PLUGIN_ROOT` variable. Wherever it appears unexpanded — in this file or in any file it sends you to — replace it with the plugin root: the parent of this skill's `skills/` directory. This is the one path substitution you may make yourself. It does not apply under Hermes, which installs only the skill folder.

A typed graph of how this repo's application works, stored in `<repo>/.ontology/`.
`schema.json` says which types and relations exist; `graph.jsonl` is an append-only log
of changes. The engine rejects any write that breaks the schema.

## What belongs in it

Behavior only. Describe what the system does, for whom, with which domain things, under
which rules, and why, in the domain's own words. Code does not belong anywhere in the
graph: no file paths, line numbers, languages, frameworks, libraries, vendors, classes,
functions, tables, endpoints, or queues, in any property, name, or summary. Name an
outside system by its role ("Payment provider"), not its product. A good test: the entry
should stay true if the code were rewritten on a different stack.

The engine enforces the structural part. Each type accepts only its defined properties,
so a property such as `framework` or `path` is rejected, and a `sources` field is
refused. Free text it cannot police; keeping code out of names and summaries is on you.

## Engine

Run every command as:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/ontology.py <command> [args]
```

Below, `ontology.py` means that full invocation. Never fall back to a relative
`scripts/ontology.py`; the plugin cache path changes on every update. The engine needs
Python 3.10+ and nothing else. It finds the store at `$ONTOLOGY_DIR`, else
`<git root>/.ontology`.

## Route on the argument

| Argument | Do |
|---|---|
| `setup` | Run the onboarding wizard: [`workflows/setup.md`](workflows/setup.md) |
| `refresh` | Review the map against current behavior: [`workflows/refresh.md`](workflows/refresh.md) |
| anything else, or invoked automatically | Follow "Using the ontology while coding" below |

## Using the ontology while coding

1. **Check for a store.** Run `ontology.py status`. If `exists` is false, say once that
   `/ontology setup` builds one, then carry on without it. Never start the wizard unasked.
2. **Orient before reading code.** Run `ontology.py summary` at the start of a task.
   Then narrow down:
   - `find --text <word>` or `find --type <Type>` to locate something by name.
   - `get --id <id>` for one entity and its relations.
   - `neighbors --id <id> --depth 2` for what surrounds it (`--rel`, `--dir in|out`).
   - `path --from <id> --to <id>` for how two parts connect.
3. **Treat it as a map, not as proof.** The graph says what the system should do; the
   code says what it does. The map cannot tell you where behavior lives, so find the
   code yourself, and cite it as `file:line` from the code, never from the graph.
4. **Write back what the task taught you.** Apply these and list them in your final
   message:
   - a new entity or relation for behavior you confirmed in code, described in domain
     terms
   - a correction to an entity in the area you touched that the code contradicts

   Ask the user first, and never decide alone, for:
   - removing an entity
   - adding or changing a `Decision` or `Rule` (these record intent, not code)
   - editing `schema.json`
5. **Never record a secret.** The engine rejects properties named like secrets
   (`password`, `token`, `api_key`, …) but cannot see values.

The log is append-only, so every applied write is recoverable from `graph.jsonl`;
`compact` keeps a `.bak`.

## Command reference

| Command | Purpose |
|---|---|
| `status` | Whether a store exists, where, shared or local, counts |
| `summary [--limit N]` | Markdown overview: counts by type, then the main areas, actors, capabilities |
| `types` | The schema: every type, property, and relation with its description |
| `find [--type T] [--where JSON] [--text S]` | Search entities |
| `get --id ID` | One entity with incoming and outgoing relations |
| `neighbors --id ID [--rel R] [--dir in\|out\|both] [--depth N]` | Walk the graph |
| `path --from ID --to ID [--max-depth N]` | Shortest connection, either direction |
| `add --type T --props JSON [--id ID]` | Add an entity; id defaults to `<prefix>:<slug of name>` |
| `update --id ID [--set JSON] [--unset a,b]` | Change properties |
| `remove --id ID` | Remove an entity and every relation touching it |
| `link` / `unlink --from ID --rel R --to ID [--props JSON]` | Add or remove a relation; a repeated link is a no-op |
| `apply --file F\|- [--dry-run]` | Apply a JSONL batch; all or nothing |
| `validate` | Re-check the whole graph, e.g. after editing the schema |
| `compact` | Rewrite the log as a snapshot |
| `init --template application\|empty [--shared] [--force]` | Create the store (the wizard runs this) |

Exit codes: 0 success, 1 validation failure or not found, 2 bad usage or no store.
Errors print to stderr and name the failing op.

### Batch format

One JSON object per line. `apply` checks the whole batch against the graph as it would
be after each earlier line, and writes nothing if any line fails.

```jsonl
{"op":"add","type":"Area","props":{"name":"Billing","responsibility":"Charges customers and records what they owe"}}
{"op":"add","type":"Capability","props":{"name":"Refund an order","summary":"Return a customer's money for an order"}}
{"op":"link","from":"cap:refund-an-order","rel":"part_of","to":"area:billing"}
{"op":"update","id":"area:billing","set":{"summary":"Owns every movement of money"}}
{"op":"remove","id":"cap:legacy-credit"}
{"op":"unlink","from":"area:billing","rel":"depends_on","to":"actor:old-payment-provider"}
```
