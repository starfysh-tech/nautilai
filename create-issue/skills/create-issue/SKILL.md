---
name: create-issue
description: Create GitHub issue(s) from a validated change request — a spec, plan, or conversation-captured decisions. Extracts work-content, shapes it with INVEST/EARS, maps it into the repo's own `.github/ISSUE_TEMPLATE/*.yml` schemas, executes every claim, audits completeness, then creates and links the issues. Invoked via `/create-issue`.
argument-hint: "[owner/repo] [path/to/spec.md ...] [--dry-run]"
disable-model-invocation: true
allowed-tools: Read, Write, Grep, Glob, AskUserQuestion, Agent, Bash, mcp__github__get_me, mcp__github__list_issue_types, mcp__github__get_label, mcp__github__issue_read, mcp__github__issue_write, mcp__github__sub_issue_write, mcp__github__search_issues, mcp__linear-server__list_issues, mcp__linear-server__save_issue, mcp__linear-server__list_projects, mcp__claude_ai_Linear__list_issues, mcp__claude_ai_Linear__save_issue, mcp__claude_ai_Linear__list_projects
---

# Create GitHub issue(s) from a change request

Body schemas live in the target repo's `.github/ISSUE_TEMPLATE/*.yml`. This skill extracts
work-content from a validated source, maps it into the matching schema, and runs creation and
linking.

**Ticket = work-content only.** No process notes, no "extracted from X" metadata, no template
rationale, no log of how the ticket was created.

**Required before running:** a written spec or plan, or conversation-captured decisions with clear
scope.

## Shoals (project corrections)

At the start of a run, read `.claude/shoals/create-issue.create-issue.md` from the project root if
it exists, and honor every entry as a constraint. A shoal overrides a rule in this file wherever
the two conflict; say which rule it overrode. Shoals also carry project routing the skill does not
ship — for example a milestone-pattern → Linear-project mapping (see Phase 7). A routing entry
carries a `## <name> routing` heading and one `- <pattern> → <target>` line per mapping, not the
correction fields below.

When the user corrects your behavior — what counts as settled, how to slice, which label family
means what — append a shoal to that file (creating `.claude/shoals/` if needed):

```markdown
## <short title>
- **Trigger:** when this comes up
- **Wrong:** what you did that the user rejected
- **Correct:** what to do instead
- **Why:** the reason
```

Append-only. Never edit or delete an entry; retire one with `- **Obsolete:** <date> — <reason>`.
Dedup on **Trigger**. Capture explicit behavioral corrections only. Mention the capture in one
line. Never write outside `.claude/shoals/`.

## Tooling — graceful degradation

1. **GitHub MCP** (`mcp__github__*`) — preferred for reads and writes.
2. **`gh` CLI** — the baseline. Sub-issue and blocking flags (`--parent`, `--blocked-by`,
   `--add-blocked-by`) need `gh` ≥ 2.94.0; check `gh --version` before Phase 7.
3. **Stop** — if neither MCP nor an authenticated `gh` is available, stop and tell the user to
   run `gh auth status`. Never fabricate tracker data.

State which path you took. Say "falling back to gh CLI" once, then proceed.

## Determine the target repo

- Arguments: a token starting with `--` is a flag; a token matching `<owner>/<repo>` with no `.`
  or path separator beyond the one slash is the repo; anything else is a source path.
- An `owner/repo` argument wins. Otherwise use the current directory's repo
  (`gh repo view --json nameWithOwner`).
- If neither resolves, ask the user. Never guess.
- `--dry-run`: run Phase 0 through Phase 5, then print the extraction file path, each draft body,
  the exact `--label` / `--type` / `--milestone` values Phase 7 would pass, the blocking graph by
  title (`--parent` and `--blocked-by` take numbers that do not exist yet, so print the edges as
  "<sub-issue> blocked by <sub-issue>"), the Phase 7 Linear routing line (target project, or skip
  reason), and the Phase 5 audit findings. A blocking audit does not stop a dry run — there is no
  creation to block; print what it found. Phase 1 still writes its extraction file. Every other interactive stop still fires
  (the Phase 0 no-fit ask, the Phase 1 question gate, the Phase 3 selection); only the Phase 6
  approval is skipped, since there is nothing to approve. Never run Phase 6, 7, 8, or 9. Never call
  `gh issue create`, `gh issue edit`, a Linear write, or milestone creation.

---

## Phase 0: Pull the ground truth (gate)

List candidate source artifacts. `find` does not abort on an empty glob the way `ls` does under
zsh.

```bash
find specs docs/specs docs/plans docs/adr -maxdepth 2 -name '*.md' 2>/dev/null || true
find ~/.claude/plans -maxdepth 1 -name '*.md' ! -name 'ticket-extraction-*' -mtime -14 2>/dev/null || true
```

Keep only artifacts that name the change request's subject — match on the slug, a symbol, or a
phrase from the conversation. Read each kept artifact in full before Phase 1. Do not read the rest;
list them in one line as skipped.

Add any path the user passed as an argument, the current conversation (every relevant message, not
only the latest turn), and any spec or runbook the user linked.

Run these and draft against the output. Never draft against memory — a value absent from the
output does not exist, and an unknown label fails the whole create call.

```bash
gh --version
gh label list --repo <owner/repo> --limit 200 --json name -q '.[].name' | sort
gh api orgs/<owner>/issue-types -q '.[].name' 2>/dev/null   # org repos only; empty = no --type
gh api repos/<owner/repo>/milestones --paginate -q '.[].title'
find .github/ISSUE_TEMPLATE -maxdepth 1 -name '*.yml' -exec sh -c 'echo "=== $1"; cat "$1"' _ {} \; 2>/dev/null || true
```

Read each template's `body` array. Record in the extraction file (`## Template fields`) every
template's filename, its top-level `labels:`, every field `id`, and which fields carry
`validations.required: true`. Skip `config.yml`; it has no `body`. `blank_issues_enabled: false`
there gates only the web form, never `gh issue create`.

A template fits only when every required field can be answered from the extraction, or filled
after creation. A required sub-issues field is the second kind: the numbers do not exist until the
sub-issues are created, so it never rules an epic template out — create the epic with the decision
titles in that field, then `gh issue edit` it with the numbers once they exist. A required
dropdown fits when one option describes the work; pick the closest option and record the choice.
A dropdown with no such option, or a required free-text field the work cannot fill (a repro for
work that is not a defect), rules that template out. Record fit or rule-out, with the deciding
field, per template in `## Template fields`.

**No templates in the repo, or none fits:** stop and ask whether to proceed with the default body
outline below. Say which templates were ruled out and by which required field. Do not invent a
schema silently.

```markdown
## Goal
## Acceptance Criteria
## Verify Success
## Dependencies
## Out of scope
## Open Questions
```

Epic outline, when the work is an epic and no epic template exists:

```markdown
## Goal
## Scope
## Sub-issues
## Out of scope
## Open Questions
```

---

## Phase 1: Extraction (written, reviewable)

Write a flat checklist to `~/.claude/plans/ticket-extraction-<slug>.md`. This file is the source of
truth for completeness. It does NOT go into ticket bodies.

```markdown
# Extraction: <slug>

## Goal

[one observable outcome]

## Evidence

- [concrete symptom: error rate, log, screenshot, repro]

## Decisions

- [chosen + rejected + why]

## Decided by the user, in their words

- [question asked] → "[their answer, verbatim]"

## Behavioral durables

- Models: [Model — inherits/tenant/nullable/constraints/behaviors]
- API behaviors: [endpoint/webhook quirks, logging requirements]
- Status/event mappings: [event → transition]
- Ordering/vendor quirks: [non-obvious]

## Template fields

- [template.yml — labels: […] — required: […] — optional: […]]

## Acceptance Criteria (Given/When/Then)

- Given … When … Then …

## Verify Success

- [runnable assertion that fails now]
- [invariant guard: passes now and must still pass after — label it `invariant`]

## Out of scope

- [item]

## Find via (search patterns)

- [pattern, not file:line]

## Open questions

- [unresolved]

## Reviewer domain (epics)

- [an area-family label from the Phase 0 output; if none fits, name the domain in prose and say
  no label matched — never stretch a label to fit]

## Scheduling

- [when the user said this should happen, in their words]

## Work type

- [Epic | Feature | Bug | Maintenance] — [template filename or `default outline`]

## Title

- [≤ 72 chars, imperative, names the subject; for a sub-issue, the decision it ships]
```

A section the work does not touch reads `- Not applicable — <reason>`. Never delete the heading.

### The question gate

Rule: **never ship a question the user has already answered.** Phases 4, 4.5 and 5 enforce it.

1. **Drop settled entries.** Search the transcript for each `## Open questions` entry. Move any
   the user answered to `## Decided by the user, in their words`, verbatim.
2. **Ask the rest, plus the completeness confirmation, in one `AskUserQuestion`.** Cap is four
   questions per call; completeness takes one, so three entries fit. Loop for more.
3. **Move an entry to Decisions only on an answer that settles it.** "Not sure" or "ask me later"
   is a deferral. Keep the question. Record its owner and what unblocks it.
4. **If the user adds items, restart this phase.**

A question survives into a ticket only when answering it needs a production check, a code change,
a third party, or an explicit deferral. Anything settleable in a sentence is settled here.

`## Decided by the user, in their words` is what subagents inherit. Record their words, not your
synthesis.

---

## Phase 2: Shape check (INVEST + EARS)

Apply INVEST to each prospective ticket. If any fails, restructure before drafting:

| Lens            | Failure mode → action                                            |
| --------------- | ---------------------------------------------------------------- |
| **Independent** | Blocks/blocked-by sub-issue → split or add blocking relationship |
| **Negotiable**  | Spec locks `how` → strip pseudocode from extraction              |
| **Valuable**    | No user/system benefit articulated → demand evidence or drop     |
| **Estimable**   | Unknown surface unbounded → spike sub-issue first                |
| **Small**       | Spans 2+ decisions or 2+ reviewer domains → epic with sub-issues |
| **Testable**    | No verify command possible → write one or split                  |

**Small yields to an explicit user scope.** When the user scoped the work to one ticket, keep one
ticket and record the decision count in the extraction file. A repo with no epic template does not
forbid an epic — template availability decides the body shape, never the scope; use the epic
outline below.

**Slice vertically.** Each ticket cuts a narrow but complete path through every layer it touches
(model, API, UI, tests) and is demoable or verifiable on its own. Never slice horizontally.

**Size to one context window.** Split any ticket an agent could not hold in a single fresh
session.

**Wide refactors are the exception.** A mechanical change fanning across the codebase sequences
expand → migrate → contract: add the new form beside the old, move call sites in batches (one
ticket each, all blocked by the expand), then delete the old form in a ticket blocked by every
batch.

Classify each AC behaviorally (EARS type):

- ubiquitous → THE system SHALL …
- event-driven → WHEN trigger
- state-driven → WHILE state
- unwanted → IF condition THEN …
- optional → WHERE feature SUPPORTED …

Record `ears: <type>` per acceptance criterion. A ticket's label is the type its ACs share; a
ticket whose ACs mix types gets no EARS label. Apply it as a label only if the repo's label list
from Phase 0 has one; otherwise it stays in the extraction file.

---

## Phase 3: Template selection

Two questions, in one `AskUserQuestion`.

**Body shape.** Offer one option per template that fits (Phase 0), named by its filename, plus the
default outline when the user approved it. Skip this one when only one option remains and say which
you took.

**Work type.** Always ask, unless Phase 2 already settled it (an epic split, a single decision on a
bug template). Ruling a template out never answers it.

> **Work type?**
>
> 1. **Epic** — multiple decisions, each ships as own PR (epic template, or the epic outline, +
>    N × sub-issues)
> 2. **Feature** — single decision, new behavior
> 3. **Bug** — defect, optionally with decided fix
> 4. **Maintenance** — refactor, cleanup, tech debt

The native `--type` follows the work type on every path: Bug → `Bug`; Feature → `Feature`; Epic or
Maintenance → `Task`. Use only a value the org publishes. On the default outline the type label
follows it too: Bug → the repo's bug label; Epic, Feature, or Maintenance → its enhancement label;
none present → no type label. On a template path the type label comes from the template's
`labels:`.

Hard rules:

- One sub-issue = one decision = one PR
- Epic ≤ 2 reviewer domains
- Multi-root-cause = epic with one sub-issue per root cause

---

## Phase 4: Draft (work-content only)

Map extraction items to the template fields Phase 0 printed. Render the body as one `### <field
label>` heading per template field, in template order. Fill an optional field only when the
extraction has content for it; omit it otherwise and say which. Extraction sections with no
template field (`Dependencies`, `Verify Success`, `Out of scope`, `Open Questions`) follow the
template fields as `### ` sections of their own. The title comes from `## Title` in the extraction.

Do NOT include:

- Meta-narration ("extracted from conversation")
- Template rationale
- Process logs
- Anything that doesn't help an implementer do the work

### Length budget

**Target 200 words. Hard ceiling 400.** Over 400, split the ticket or cut prose.

Lead with **what to build** — the end-to-end behaviour this ticket makes work, from the user's
perspective. Not a layer-by-layer implementation list. Not the reasoning; that lives in the spec
the ticket links to.

Cut on sight:

- A paragraph on why an alternative was rejected. One clause, or leave it in the extraction file.
- An acceptance criterion restated as prose above the acceptance criteria.
- Background an implementer of this codebase already has.
- Anything that would read identically on a different ticket.
- Metadata already carried by a label or issue type.

Parallel drafting for 3+ sub-issues: each agent gets shared epic context + assigned decision +
the target template filename, or the literal heading list when the default outline is in use +
extraction file path. Returns body text only.

### Mandatory cross-ticket discipline

A rule does not apply where the targeted field is absent from the template.

1. **Every non-epic ticket carries a Dependencies section.** Epics use `Sub-issues` + `Scope` +
   epic-level `Open Questions` instead. Before writing `none`, confirm the ticket passed INVEST
   `Independent` in Phase 2 and cross-check the extraction file for any ticket, issue, PR,
   migration or deploy step the work waits on. Search open issues and PRs for the subject
   (`gh issue list --search`, `gh pr list --search`); a hit is a dependency, or a duplicate that
   stops the run. Never default to `none` to satisfy the form.
2. **An Open Question naming `#N` is duplicated into `#N`.** Applies to epics with sub-issues.
3. **Every `Find via` pattern appears in `Verify Success` as a residual check**, with its expected
   post-change count — zero for a rename or removal, `≥ 1` for an insertion. A pattern
   that only locates where the change goes is an anchor, not a residual check: it stays in the
   extraction file's `## Find via` and never enters `Verify Success`.
4. **Every Open Question is one the user has not already answered.** Check each against
   `## Decided by the user, in their words`. Survivors name an owner and a Phase 1 survival reason.

---

## Phase 4.5: Execute every claim (hard gate, before the audit)

A ticket is a set of claims. Run them; do not read them and judge.

For each draft, before it goes to Phase 5:

1. **Resolve every cited symbol by searching for it** — `grep -rn '<symbol>' <path>` — and
   confirm the match says what the draft says. Cite symbols, never line numbers. A symbol with no
   match means the ticket is about something that does not exist — unless the ticket is what
   creates it. A symbol the work introduces is cited as new and must NOT resolve; a symbol the work
   changes or depends on must. Say which kind each is. Never cite a path you have not opened this
   session, except one the ticket creates.

2. **Run every command in `Verify Success`, and require it to FAIL.** A
   command that passes now means the work is already done or the command is wrong. Resolve which
   before proceeding. Exception: a positive/negative control pair — a check the ticket introduces,
   shown passing on a good input and failing on a broken one. Label the pair as controls in the
   body. An `invariant` guard passes now and must still pass after; label it in the body. A
   premise only the user can attest ("this happened twice") is cited as theirs, marked
   user-attested, never as verified. Check for:
   - **Package name vs import name** — the manifest holds one, the code imports the other; a grep
     for either alone can miss the pin.
   - **Unanchored patterns** — a pattern that also matches the prescribed fix can never reach
     zero. Anchor with `\b`.
   - **Multi-line calls** — grepping a function name shows the call but not its arguments.
   - **Substring test selectors** — a selector that also matches a file or module name picks up
     existing tests. Select the new test by its exact name.
   - **Whole-suite gates on a one-line change** — passes identically before and after.

3. **Verify every version claim against the package's declared dependency metadata**, not
   classifiers or release notes, and confirm with the project's resolver.

4. **Test every prose premise that asserts an absence** — "no test does X", "the only use is Y",
   "all Z do W". Search for the negation.

5. **Re-read the transcript before shipping any Open Question.** Two ways a settled answer
   regresses into one:
   - **A subagent regenerates it.** Reconcile every returned draft against `## Decided by the
     user, in their words`.
   - **An audit calls your evidence weak and you downgrade the answer.** Check whether the user
     *is* the evidence; if so, cite them.

   A user premise the files disprove is neither: do not silently rewrite the ticket around it, and
   do not ship it. Show the user the premise, the command, and its output, and ask.

Mark anything you could not execute UNVERIFIABLE and say why. Never present it as verified.

**Edit bodies by rewriting them, never by appending.**

---

## Phase 5: Completeness audit (subagent gate, before creation)

Dispatch a subagent with:

- Path to `~/.claude/plans/ticket-extraction-<slug>.md`
- All source artifact paths from Phase 0
- All draft ticket bodies

Subagent's job:

1. List every item from source/extraction that is missing from any draft ticket. An item that
   the body carries in an appended `### ` section counts as present.
2. Flag any meta-noise (process notes, extraction logs, template rationale) for stripping.
3. Enforce the four Phase 4 rules, scoped by ticket shape:
   - **Dependencies (non-epic only):** every non-epic draft has a `Dependencies` section. Where
     one declares `none`, scan the extraction and the other drafts for issue numbers, migration
     filenames, deploy steps, or "after X lands" phrasing. Surface each suspect.
   - **Open Questions propagation (epics with sub-issues only):** every epic-level Open Question
     naming `#N` also appears in `#N`'s Open Questions.
   - **Find via residual check (tickets with Find via):** every pattern appears as a residual
     check in `Verify Success`.
   - **Open Questions are genuinely open (all tickets):** check each against `## Decided by the
     user, in their words`. Survivors name an owner and a reason; "unclear" does not qualify.

Every audit finding is `report` or `ask-user`. The subagent changes nothing. Block creation until
it reports zero gaps, zero noise, and all applicable rules satisfied.

**The audit subagent has not seen the conversation.** On any finding turning on a user-supplied
fact, work out which side is stale first. Never let an audit overturn the user's own answer.

If the extraction is the stale side: correct it, regenerate the drafts written from it, and rerun
Phase 4.5 and this audit. A draft is exempt only for a stateable reason — written after the
correction, or never touched that fact. Run this loop at most twice; if the audit still reports
gaps, stop and take the remaining findings to the user as `ask-user`.

---

## Phase 6: Approval

Present drafts + audit result. `AskUserQuestion`:

> 1. Approve and create
> 2. Revise

---

## Phase 7: Creation

### Labels and type

Every value below must appear in the Phase 0 output. Do not invent one.

- The chosen template's `labels:` — `gh issue create --body` does not apply them; pass them on
  `--label`
- Area / EARS labels — add from the printed list; skip any family the repo lacks. The type label
  comes from the template's `labels:`; on the default outline, from the Phase 3 rule.
- Issue type via native `--type` only when the org publishes issue types
- Milestone — pick from the printed list. If none fits, ask before creating one; a repo with zero
  milestones stays that way unless the user says otherwise.

Never set a priority as body text. If the repo has no priority label or field, it has no priority.
`## Scheduling` from the extraction lands on the issue only as a milestone the user approved;
otherwise it stays in the extraction file.

### Single issue

```bash
gh issue create --repo <owner/repo> \
  --title "[title]" \
  --body "$(cat <<'EOF'
[body]
EOF
)" \
  --label "[labels]" \
  --type "[Task|Bug|Feature]" \
  --milestone "[milestone]"
```

Omit `--type` when the org publishes no issue types. Omit `--milestone` when none was chosen; never
pass an empty string.

### Epic + sub-issues

```bash
gh issue create --repo <owner/repo> --title "[sub]" --body-file - --parent [EPIC] --blocked-by [N,M]
gh issue edit [N] --repo <owner/repo> --add-blocked-by [M]     # for an edge discovered after creation
```

The epic is created by the single-issue block above, with the epic outline as its body; the
sub-issue block uses `--body-file -` so a drafted body can be piped in (`--body` and a heredoc work
equally). Both take `--label` and `--type` exactly as the single-issue block does.

1. Create the epic, then each sub-issue with `--parent [EPIC]`. If the epic body has a sub-issues
   field, `gh issue edit` the epic with the real numbers after the sub-issues exist
2. Create in dependency order, blockers first, so `--blocked-by` can name a real number
3. Assign the chosen milestone to all; skip this step when none was chosen

Record blocking edges in the relationship graph, never in a comment.

### Linear routing (optional)

Runs only when both hold:

- a Linear MCP is reachable this session under any server name (`mcp__linear-server__*`,
  `mcp__claude_ai_Linear__*`, or another prefix) and exposes `list_projects` / `save_issue`. A
  server exposing only `authenticate` is configured but unauthenticated: skip, and say so — never
  start an auth flow mid-run
- the shoals file carries a `## Linear routing` entry mapping milestone patterns to Linear
  projects
- a milestone was chosen. With no milestone there is nothing to match; skip and say so

If either is missing, say "Linear routing skipped: <reason>" once and continue. Never invent a
project mapping.

---

## Phase 8: Diff-back validation (after creation)

Re-read source artifacts + extraction file + every created issue. Produce a report:

- **In source, missing from issues:** [list — must be empty]
- **In issues, not in source:** [list — must be empty; indicates invented content]
- **Meta-noise in body:** [list — must be empty]
- **Over the 400-word ceiling:** [list — must be empty]

If any list is non-empty, patch the ticket(s) via `gh issue edit`:

- Removing invented content or meta-noise is `auto-fix` — apply, then report what changed.
- Adding a missed source item or cutting an over-ceiling body is `ask-user` — show the proposed
  body and wait.

Do not report success until every list is empty.

```bash
gh issue view [N] --repo <owner/repo> --json title,body,labels,milestone,projectItems
gh issue view [N] --repo <owner/repo> --json body -q '.body' | wc -w
```

---

## Phase 9: Report

```
✓ Epic #[N]: [title] — [url]
  Sub-issues:
  ✓ #[N] — [decision] — [url]
```
