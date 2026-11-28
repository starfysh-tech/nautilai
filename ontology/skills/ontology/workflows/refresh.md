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

## 2. Choose what to review

The map holds no links to code, so you decide what to re-check by reading the code.

- If the user named an area or capability, review that.
- Otherwise find the last write: the newest `"ts"` in `.ontology/graph.jsonl`. Read the
  commits since then (`git log --since=<ts> --stat`), work out which areas' behavior
  they touched, and propose that list. Without git, ask the user what changed.

Confirm the list with the user before reviewing.

## 3. Review each area

For each area, run `ontology.py neighbors --id <area> --depth 2`, then read the code that
serves it and compare what the code does with what the map says.

| Finding | Do |
|---|---|
| Map matches the code | Nothing |
| Entity wrong in a detail | Collect an `update` |
| Behavior in code with no entity | Collect an `add` and its links, in domain terms |
| Entity whose behavior is gone | Ask the user before removing it |
| `Decision` or `Rule` the code contradicts | Show the text and the contradicting code; ask whether the code or the record is wrong |

A code change that leaves behavior alone needs no write. Never add code details while
updating. Apply the collected writes as one batch with `apply --file -`, after showing
them to the user.

## 4. Compact

If `graph.jsonl` has more than five times as many lines as `status` reports entities
plus relations, run `ontology.py compact` and give the backup path.

## 5. Report

Report what was added, updated, and removed, and which areas were left unreviewed. Lead
with the changes. Omit categories with nothing in them.
