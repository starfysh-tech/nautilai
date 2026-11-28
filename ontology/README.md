# ontology

A local-first, technology-agnostic map of how an application works, which coding agents
query before reading code. It covers areas of responsibility, actors, capabilities,
domain concepts, processes, events, rules, and decisions, described in the domain's own
words. An onboarding wizard seeds the map from the repo, and every write is checked
against a schema. The map holds behavior only, never code.

## Install

```text
/plugin install ontology@nautilai
```

## Usage

| Command | What it does |
|---|---|
| `/ontology setup` | Onboarding wizard: choose storage and vocabulary, survey the repo, approve the seed, optionally add a pointer to `CLAUDE.local.md` or `CLAUDE.md` |
| `/ontology refresh` | Review the map against the code: pick the areas whose behavior changed (from recent commits, or as you name them), compare, and fix the map behind an approval |
| `/ontology <question>` | Answer from the map, e.g. "how does checkout work", "who can refund an order", "what depends on billing" |

The skill also loads on its own when a coding task starts in a repo that has a
`.ontology/` directory. It orients with `summary`, `find`, and `neighbors`, then records
behavior it confirms in code.

Natural-language triggers: "set up the ontology", "map this codebase", "what depends on
X", "where is X handled", "how does X work".

## How it works

- **Store.** `<repo>/.ontology/` holds `schema.json` (the allowed types and relations)
  and `graph.jsonl` (an append-only log of changes, replayed on read). Override the
  location with `ONTOLOGY_DIR`.
- **Local first.** By default `.ontology/.gitignore` ignores the whole directory, so the
  map stays on your machine. Choose **Shared** in the wizard to commit it for teammates'
  agents.
- **Behavior only.** The `application` template defines Area, Actor, Capability, Concept,
  Process, Event, Rule, and Decision, plus relations such as `part_of`, `uses`,
  `realized_by`, `triggers`, `emits`, `changes`, `constrains`, and `governs`. Nothing in
  the graph points at code: no file paths, languages, frameworks, vendors, tables, or
  endpoints. Each type rejects properties it does not define, and the engine refuses a
  `sources` field. The `empty` template starts with no types. Either way, `schema.json`
  belongs to the repo and can be edited; `validate` re-checks the graph after an edit.
- **Checked writes.** `scripts/ontology.py` rejects a write that names an unknown type or
  relation, misses a required property, breaks an enum, connects the wrong types, exceeds
  a relation's cardinality, closes a cycle in an acyclic relation, links to a missing
  entity, or uses a property named like a secret. `apply` runs a batch all or nothing.
- **No drift detection.** Because the map has no links to code, the engine cannot tell
  when code changes. `/ontology refresh` has the agent read recent commits, decide which
  areas' behavior they touched, and review those areas against the code.
- **What the agent may change.** It adds behavior it confirmed in code and corrects
  entities the code contradicts in the area it touched, then lists those writes. It asks
  before removing an entity, changing a Decision or Rule, or editing the schema.

## Requirements

Python 3.10 or later. The engine uses only the standard library. Git is optional: with
git the engine stores the map at the repo root; without it, in the current directory.

## Conventions

- **Finding dispositions:** not a review skill. Its writes follow the same split:
  confirmed additions and corrections are applied and reported; removals and intent
  records (Decision, Rule, schema) are ask-user.
- **Dual-runtime:** Claude Code only (plus omp/pi via the adapter line). It is not yet
  mirrored for Hermes. A port needs `scripts/` and `templates/` mirrored into the skill
  directory and a "Resource paths" section, per
  [`docs/conventions/dual-runtime.md`](../docs/conventions/dual-runtime.md).

## Tests

```bash
python3 ontology/tests/test_ontology.py
```

The suite builds throwaway repos (git and plain) in a temp directory and drives the CLI
as a subprocess. It is offline.
