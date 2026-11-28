# Setup wizard

Build this repo's ontology in one guided pass. `ontology.py` means
`python3 ${CLAUDE_PLUGIN_ROOT}/scripts/ontology.py` throughout.

Stop after any step where the user wants to discuss. Nothing is written to the graph
before step 5's approval.

## 1. Preflight

1. Run `python3 --version`. Below 3.10, stop: say the engine needs Python 3.10+ and
   nothing else can stand in for it.
2. Run `ontology.py status`.
   - `exists: false` → go to step 2.
   - `exists: true` → ask with `AskUserQuestion`:
     - **Add to it (Recommended)**: skip to step 4 and survey only areas with no entities
       (check with `find --source <dir>`).
     - **Change sharing**: rewrite `.ontology/.gitignore` (see step 3 for both contents),
       report, and stop.
     - **Start over**: rename `graph.jsonl` to `graph.jsonl.bak`, run `init --force`
       with the step 2 answers, then continue. Say where the backup is.
     - **Cancel**.

## 2. Ask

Ask all three in one `AskUserQuestion` call:

1. **Storage**: Where should the ontology live?
   - **Local only (Recommended)**: `.ontology/` is git-ignored. Only your agents see it.
   - **Shared**: `.ontology/` can be committed so teammates' agents use the same map.
2. **Vocabulary**: Which types should the schema start with?
   - **Application (Recommended)**: how the application works, technology-agnostic: Area,
     Actor, Capability, Concept, Process, Event, Rule, Decision.
   - **Empty**: no types; you define them in `.ontology/schema.json`.
3. **Seed depth**: How much should I map now?
   - **Skeleton (Recommended)**: areas of responsibility, actors, capabilities, and the
     core domain concepts.
   - **Deep**: the skeleton, plus processes, events, rules, and recorded decisions.
   - **None**: create an empty graph.

With **Empty**, seeding has no types to use, so treat it as **None** and say so.

## 3. Initialize

Run `ontology.py init --template <application|empty>` and add `--shared` for Shared.
The engine writes `.ontology/.gitignore`:

- Local: `*` (the whole directory is ignored, including the `.gitignore` itself)
- Shared: only `.lock` and `*.bak`

With seed depth **None**, go to step 6.

## 4. Survey (read-only)

Read the code to learn how the application behaves, then describe that behavior in the
domain's own words. Every candidate needs at least one source path you actually opened.
Skip vendored, generated, and build-output directories (`node_modules`, `vendor`,
`dist`, `build`, `.venv`, lockfiles, minified bundles).

**Model behavior, not implementation.** Properties, names, and summaries never mention a
language, framework, library, vendor, file, class, function, table, endpoint, or queue.
Name outside systems by role ("Email sender", not a product). Code is evidence: it goes
in `sources` only. Ask of every candidate: would this still be true if the code were
rewritten on a different stack? If not, rewrite it or drop it.

| Type | What to look for | Where the evidence usually is |
|---|---|---|
| Area | Groups of behavior that share one responsibility | README, top-level structure, how code is split by domain |
| Actor | Who triggers behavior or is acted on: roles, outside systems, schedules | Auth roles and permissions, inbound handlers, outbound clients, scheduled jobs |
| Capability | What an actor can do or get, as an outcome | Entry points (routes, commands, UI screens), README feature lists |
| Concept | The things the domain talks about, what they mean, the states they pass through | Models and schemas, status fields, glossaries, recurring names |
| Process (Deep) | The steps from trigger to outcome for the two or three most important capabilities | Trace an entry point through to its effects |
| Event (Deep) | Things that happen that other behavior reacts to | Emitted messages, hooks, notifications, audit records |
| Rule (Deep) | What must always or never be true | Validations, guards, permission checks, constraints, tests named for a rule |
| Decision (Deep) | Why the system behaves as it does | `docs/adr/`, design docs, commit and PR rationale |

Prefer fewer, broader entries over a list of every screen or route: a capability is an
outcome an actor cares about, and several entry points can serve one capability.

For a repo with more than three areas, give each area to its own read-only `Explore`
subagent in parallel. Hand each one this section, the schema (run `ontology.py types`),
and the batch format from `SKILL.md`. Ask each for candidate ops as JSONL plus a list of
anything it was unsure of. Without subagents, survey the areas one at a time.

Use the ids the engine would generate (`<prefix>:<slug of name>`, prefixes in
`ontology.py types`) so links in the batch line up. Relate what you found: `part_of`,
`uses`, `realized_by`, `triggers`, `emits`, `reads`/`changes`, `relates_to`,
`depends_on`, `constrains`.

## 5. Review gate

1. Write the candidate batch to `.ontology/seed.jsonl`.
2. Run `ontology.py apply --file .ontology/seed.jsonl --dry-run`. Fix mechanical
   failures yourself: a wrong id in a link, a missing required property you can read
   from the source, a relation pointed the wrong way, an implementation detail that
   belongs in `sources`. If a fix needs a guess about the
   code, take the candidate out and list it as uncertain.
3. Show the user a compact table per type: id, label, first source. After the tables,
   list the uncertain candidates, each with its reason.
4. Ask with `AskUserQuestion`:
   - **Apply all (Recommended)**
   - **Let me remove some first**: wait for their list, edit `seed.jsonl`, dry-run
     again, and ask again.
   - **Cancel**: leave `seed.jsonl` in place and stop.
5. On approval, run `ontology.py apply --file .ontology/seed.jsonl`, then delete
   `seed.jsonl`.

## 6. Point agents at it

Coding agents load the skill when its description matches. A short pointer in the
agent memory file makes that dependable. Ask with `AskUserQuestion`:

- Local storage: offer **Add to `CLAUDE.local.md` (Recommended)** or **Skip**.
  `CLAUDE.local.md` should stay out of git. If `git check-ignore -q CLAUDE.local.md`
  fails, say so and offer to add it to `.git/info/exclude`.
- Shared storage: offer **Add to `CLAUDE.md` (Recommended)**, **Add to `AGENTS.md`**
  (only if that file exists), or **Skip**.

Append this block unchanged. If it is already present, leave the file alone.

```markdown
## Ontology

This repo has a typed, technology-agnostic map of how the application works in
`.ontology/`. Before reading code for
a task, run `/ontology` (or the `ontology` skill's `summary` and `find --source <path>`)
to orient, check `stale` before relying on an entity, and record durable facts you
confirm in code.
```

## 7. Report

Run `ontology.py summary` and `ontology.py validate`. Tell the user:

- entity counts by type, and the relation count
- where the store is, and whether it is local or shared
- the uncertain candidates left out in step 5
- that `/ontology refresh` re-checks entities after the code changes

Then stop.
