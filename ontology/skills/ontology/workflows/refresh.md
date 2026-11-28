# Refresh

Bring the ontology back in line with the code. `ontology.py` means
`python3 ${CLAUDE_PLUGIN_ROOT}/scripts/ontology.py` throughout. If `status` shows
no store, say that `/ontology setup` builds one, and stop.

## 1. Validate

Run `ontology.py validate`.

- Valid → step 2.
- `schema:` errors mean `schema.json` itself is malformed. Report them and stop. The
  schema is the user's to fix.
- Entity or relation errors usually follow a schema edit. Show them and ask the user
  whether to fix each entity to match the schema or to change the schema back. Never
  pick one yourself.

## 2. Stale entities

Run `ontology.py stale`. For each entity, read it (`get --id`), then open its sources.

| Status | Do |
|---|---|
| `changed`, still accurate | Collect for one `verify` |
| `changed`, now wrong | Collect an `update` (with new `sources` if they moved), then `verify` |
| `missing`, moved | Find the new location, collect an `update` with new `sources` |
| `missing`, gone | Ask the user before removing it |
| `unverified` | Check it against its sources, then `verify` or `update` |

Keep updates behavioral: if the code changed but the behavior did not, `verify` is
enough. Apply the updates as one batch with `apply --file -` and run `verify --id …` for all
re-checked ids. A `Decision` or `Rule` whose text needs changing is the user's
call: show the old text and the code that disagrees with it, and ask.

## 3. Gaps

List the top-level directories that hold source code. For each one, run
`find --source <dir>`. Report the directories with no entities. Offer to survey them
using steps 4 and 5 of [`setup.md`](setup.md), and wait for an answer.

## 4. Compact

If `graph.jsonl` has more than five times as many lines as `status` reports entities
plus relations, run `ontology.py compact` and give the backup path.

## 5. Report

Report what was verified, updated, and removed, and which gaps were left open. Lead
with the changes. Omit categories with nothing in them.
