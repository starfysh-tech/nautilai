# ontology

A local-first, technology-agnostic map of how an application works, which coding agents
query before reading code. It covers areas of responsibility, actors, capabilities,
domain concepts, processes, events, rules, and decisions, described in the domain's own
words. An onboarding wizard seeds the map from the repo. Every write is checked against a schema, and every entity records the files it
came from, so the map shows where it has drifted from the code.

## Install

```text
/plugin install ontology@nautilai
```

## Usage

| Command | What it does |
|---|---|
| `/ontology setup` | Onboarding wizard: choose storage and vocabulary, survey the repo, approve the seed, optionally add a pointer to `CLAUDE.local.md` or `CLAUDE.md` |
| `/ontology refresh` | Re-check entities whose source files changed, fix or verify them, and report directories the map does not cover |
| `/ontology <question>` | Answer from the map, e.g. "what touches src/billing", "how does checkout work", "what depends on billing" |

The skill also loads on its own when a coding task starts in a repo that has a
`.ontology/` directory. It orients with `summary` and `find --source <path>`, checks
`stale` before relying on an entity, and records the facts it confirms in code.

Natural-language triggers: "set up the ontology", "map this codebase", "what depends on
X", "where is X handled", "how does X flow", "what touches this file".

## How it works

- **Store.** `<repo>/.ontology/` holds `schema.json` (the allowed types and relations)
  and `graph.jsonl` (an append-only log of changes, replayed on read). Override the
  location with `ONTOLOGY_DIR`.
- **Local first.** By default `.ontology/.gitignore` ignores the whole directory, so the
  map stays on your machine. Choose **Shared** in the wizard to commit it for teammates'
  agents.
- **Checked writes.** `scripts/ontology.py` rejects a write that names an unknown type or
  relation, misses a required property, breaks an enum, connects the wrong types, exceeds
  a relation's cardinality, closes a cycle in an acyclic relation, links to a missing
  entity, or uses a property named like a secret. `apply` runs a batch all or nothing.
- **Drift detection.** Each entity lists its sources (a directory, file, or `file:line`)
  and a content fingerprint taken when it was last verified. `stale` reports entities
  whose files were edited, added, or deleted since then. Committing or switching
  branches without changing content does not make an entity stale. Without git, the
  fingerprint hashes the files directly.
- **Behavior, not implementation.** The `application` template defines Area, Actor,
  Capability, Concept, Process, Event, Rule, and Decision, plus relations such as
  `part_of`, `uses`, `realized_by`, `triggers`, `emits`, `changes`, `constrains`, and
  `governs`. No type has a property for a language, framework, vendor, file, table, or
  endpoint, and each type rejects properties it does not define. Where a behavior lives
  in code is kept in the entity's `sources`, as evidence, not as part of the model. The
  `empty` template starts with no types. Either way, `schema.json` belongs to the repo and
  can be edited; `validate` re-checks the graph after an edit.
- **What the agent may change.** It adds entities and relations it confirmed in code and
  corrects stale entities in the area it touched, then lists those writes. It asks before
  removing an entity, changing a Decision or Rule, or editing the schema.

## Requirements

Python 3.10 or later. The engine uses only the standard library. Git is optional: with
git, the engine finds the repo root and fingerprints files through git; without it, the
engine uses the current directory and hashes files directly.

## Conventions

- **Finding dispositions:** not a review skill. Its writes follow the same split: confirmed
  additions and stale fixes are applied and reported; removals and intent records
  (Decision, Rule, schema) are ask-user.
- **Dual-runtime:** Claude Code only (plus omp/pi via the adapter line). It is not yet
  mirrored for Hermes. A port needs `scripts/` and `templates/` mirrored into the skill
  directory and a "Resource paths" section, per
  [`docs/conventions/dual-runtime.md`](../docs/conventions/dual-runtime.md).

## Tests

```bash
python3 ontology/tests/test_ontology.py
```

The suite builds throwaway git repos (and one without git) in a temp directory and drives
the CLI as a subprocess. It is offline.
