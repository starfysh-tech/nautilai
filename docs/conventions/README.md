# nautilai conventions

House conventions for authoring nautilai plugins — the patterns we want to hold
**across** plugins that aren't already covered by:

- **Anthropic's skill-authoring guidance** (the `cc-skill-audit` ground truth), or
- the repo's [`CLAUDE.md`](../../CLAUDE.md) (layout, versioning, commits).

This is the place for nautilai-specific decisions: how our skills behave, degrade,
report, and stay safe. Each convention is a rule we can audit against. When a new
plugin lands, it should either follow these or make a deliberate, noted exception.

> Treat this as living. Add a convention here once it's true of 2+ plugins and
> worth holding for the next one — not before.

---

## 1. Finding dispositions — `auto-fix` / `report` / `ask-user`

Every review/audit/validation skill classifies each finding by what it may *do*
about it, and **never self-resolves an `ask-user` finding**.

→ Full spec: [`finding-dispositions.md`](./finding-dispositions.md)

## 2. Findings-first reporting

Lead with what's wrong and what to do; omit clean categories; don't narrate the
process. The absence of a finding is the absence of output.

- *Exemplified by:* `cc-skill-audit` ("What not to do"), `phi-scan` (findings-first
  report), `cc-adoption-audit` (concise + prioritized).
- *Rule:* no "I checked X and it was fine" padding; no principle restatement; no
  per-step narration in the result.

## 3. Graceful degradation, fail-open

Pick the best-available tool at each step; never hard-fail because a *preferred*
one is missing. A safety/automation layer that can't run should warn and let work
proceed, not wedge the session.

- *Exemplified by:* `pr-comment-review` (MCP → `gh` → stop), `review-plan`
  (specialist subagent → built-in → inline Grep), `phi-scan` write guard
  ("fails open" on malformed payload or missing scanner).
- *Rule:* state the fallback chain; degrade loudly (say what you fell back to);
  only hard-stop when the *baseline* requirement is genuinely absent.

## 4. Ground against live sources; mark `[unverified]`

A skill whose findings depend on external facts (docs, versions, feature
surface) verifies against a fetched source before asserting, and labels anything
it couldn't confirm. Embedded guidance is a dated **snapshot**, not ground truth.

- *Exemplified by:* `cc-skill-audit` ("Ground the audit against current docs
  first" → `llms.txt`), `cc-adoption-audit` ("Anti-hallucination rule").
- *Rule:* never invent features/versions/dates; if the fetch fails, proceed on the
  snapshot but say so; if live docs contradict an embedded rule, trust live docs.

## 5. Cite evidence with `file:line`

Claims about the user's code carry a `file:line` (or a quoted source). "Unverifiable"
is an allowed answer; a confident guess is not.

- *Exemplified by:* `review-plan` (every claim grounded in `file:line`).
- *Rule:* mirrors the maintainer's own standard — validate assumptions against the
  code, don't assume behavior that can be inspected.

## 6. Anything that can block is opt-in

A hook or guard that can cancel an edit, block a commit, or stop a push ships
**off by default** behind an explicit env var, so installing a plugin never
silently changes the user's workflow.

- *Exemplified by:* `phi-scan` — `PHI_SCAN_GUARD` (write guard),
  `PHI_SCAN_BLOCK_DEFAULT_BRANCH` (branch protection), both default-off.
- *Rule:* default-off; document the env var and that it's read at launch; pair with
  the fail-open rule (#3).

## 7. Back up before mutating

Any in-place edit a skill makes on the user's files is recoverable — a `.bak`, a
diff, or a VCS-visible change — and the skill reports what it changed. (This is the
auto-fix safety contract of #1, generalized to all writes.)

- *Exemplified by:* `cc-validate-hooks --fix` (writes `.bak`, prints its path).

## 8. Bundled scripts: stdlib-only, `${CLAUDE_PLUGIN_ROOT}`-rooted

Scripts a plugin ships are invoked via `${CLAUDE_PLUGIN_ROOT}/...` (never a
hardcoded path) and depend only on a language's standard library, so they run on a
clean machine with no install step.

- *Exemplified by:* `phi-scan` (`python3 ${CLAUDE_PLUGIN_ROOT}/scripts/phi_check.py`,
  "stdlib only; Python 3.10+").
- *Rule:* no third-party runtime deps in bundled scripts; resolve the interpreter;
  fail open if it's absent.

## 9. Stop-after-step for multi-phase skills

A skill that runs an ordered workflow pauses after a step when the user may want to
review before continuing — it doesn't barrel through to a mutation.

- *Exemplified by:* `phi-scan`, `cc-skill-audit` ("Stop after any step where the
  user wants to discuss findings").

## 10. Declare invocation intent

User-only skills say so in frontmatter rather than relying on description
phrasing, so the model doesn't auto-fire a workflow meant to be explicit.

- *Exemplified by:* `pr-comment-review` & `cc-adoption-audit`
  (`disable-model-invocation: true`); read-heavy skills use `context: fork`
  (`phi-scan`, `cc-validate-hooks`).

## 11. Shoals — auto-captured corrections

A skill that runs repeatedly in a project captures user corrections to a
project-local, append-only file and reads them back on the next run, so it
doesn't repeat a mistake the user already flagged.

- *Write target:* `<project>/.claude/shoals/<plugin>.<skill>.md` — never the
  installed plugin dir (wiped on update; leaks across repos).
- *Rule:* committed by default (team-shared, VCS-visible); append-only with
  dedup on trigger; capture explicit behavioral corrections only — no command,
  no gate, but never a write outside `.claude/shoals/`.

→ Full spec: [`shoals.md`](./shoals.md)

---

## Auditing against these

When reviewing a plugin (or adding one), check it against the list above the way
`cc-skill-audit` checks against Anthropic guidance. A deliberate exception is fine
— note it in the plugin's README so it reads as a choice, not a miss.
