# Create Issue

Turn a validated change request — a spec, a plan, or decisions captured in conversation — into
GitHub issues shaped by the target repo's own `.github/ISSUE_TEMPLATE/*.yml` schemas. The skill
extracts work-content into a reviewable checklist, shapes it with INVEST and EARS, drafts against
the template fields, executes every claim the draft makes, audits completeness with a subagent,
and only then creates and links the issues.

Distributed as a plugin via the [**nautilai**](../README.md) marketplace.

## Install

```text
/plugin marketplace add starfysh-tech/nautilai
/plugin install create-issue@nautilai
```

Requires the GitHub CLI (`gh`) authenticated (`gh auth status`), or the GitHub MCP server
configured. Sub-issue and blocking relationships (`--parent`, `--blocked-by`) need `gh` ≥ 2.94.0.

## Use

This skill is **user-invoked** (`disable-model-invocation: true`) — it creates issues in your
tracker, so it never auto-fires.

```text
/create-issue                            # source = current conversation + specs found in the repo
/create-issue docs/plans/auth-rework.md  # source = a named spec (plus the conversation)
/create-issue owner/repo path/to/spec.md # target a specific repo
/create-issue --dry-run                  # stop after the audit; print drafts, flag values, and the blocking graph
```

## What it does

1. **Pulls ground truth** — reads every source artifact in full, then lists the repo's real
   labels, issue types, milestones, and issue-template fields. Drafting never uses a value that
   list did not print.
2. **Extracts** work-content into `~/.claude/plans/ticket-extraction-<slug>.md` — goal, evidence,
   decisions, the user's own words, acceptance criteria, verify commands, out-of-scope, open
   questions. One question gate asks only what the transcript did not already settle.
3. **Shapes** each prospective ticket with INVEST (split, spike, or epic as needed), slices
   vertically, sizes to one context window, and classifies acceptance criteria by EARS type.
4. **Drafts** work-content only into the template's fields — target 200 words, hard ceiling 400,
   with a Dependencies section on every non-epic ticket.
5. **Executes every claim** — greps every cited symbol, runs every verify command and requires
   it to fail, searches for the negation of every asserted absence. Anything it cannot run is
   marked UNVERIFIABLE.
6. **Audits completeness** with a subagent that compares drafts against the extraction and
   source, then blocks creation until it reports zero gaps.
7. **Creates** behind an approval gate — epic first, then sub-issues in dependency order with
   native `--parent` / `--blocked-by` edges — and **diffs back** every created issue against
   the source.

If the repo has no issue templates, or none fits the work (a required dropdown excludes it), the
skill stops and asks before using a default body outline. The chosen template's `labels:` are
passed on `--label`, since `gh issue create --body` does not apply them.

### Linear routing

Optional. Runs only when the Linear MCP is available *and* the project's shoals file carries a
`## Linear routing` entry mapping milestone patterns to Linear projects. Otherwise it says so
once and skips. The skill ships no project mapping of its own.

## Conventions

Follows the nautilai [house conventions](../docs/conventions/README.md):

- **Finding dispositions (#1):** Phase 5 audit findings are `report` or `ask-user`; the audit
  subagent changes nothing. Phase 8 diff-back: removing invented content or meta-noise from a
  created issue is `auto-fix` (reported); adding missed content or cutting length is `ask-user`.
- **Graceful degradation (#3):** GitHub MCP → `gh` CLI → stop. Linear routing degrades to
  "skipped" with a reason.
- **Ground against live sources (#4):** labels, types, milestones, and template fields come from
  the repo at runtime; nothing is hardcoded.
- **Cite evidence (#5):** tickets cite symbols, never line numbers; every symbol is grepped
  before it ships.
- **Stop-after-step (#9):** the question gate, template selection, and approval are explicit
  stops.
- **Shoals (#11):** corrections are captured to `.claude/shoals/create-issue.create-issue.md` in
  your project and read back on the next run. Append-only and committed by default —
  `.gitignore` it for per-developer shoals. The same file carries optional Linear routing.

## License

MIT
