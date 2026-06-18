# Setup Workflow

Drive setup conversationally — gather choices with `AskUserQuestion`, then apply them
by calling the script **non-interactively** (no shell drop-out, no TTY needed). The
script is the single source of truth; these flags just let it run unattended.

## Phase 1: Show current state

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/commitcraft-setup.sh --check
```

Parse the report so you can skip components already `CONFIGURED`.

## Phase 2: Ask what to set up (one prompt)

Use `AskUserQuestion` to collect:
1. **Components** (multi-select): commitlint, gitleaks, pre-commit hooks, release-please, commitlint CI. (Leave **signing** out of the default set — it configures machine-specific SSH/GPG keys; offer it only if the user asks.)
2. **Issue tracker**: github | linear | jira | none.
3. **Branch protection**: apply via the GitHub API now? (yes/no — this changes the live repo and needs admin.)

## Phase 3: Apply non-interactively

Run one section per chosen component — each is idempotent and needs no TTY:

```bash
# For each selected component <name> ∈ {commitlint, gitleaks, precommit, release, ci}:
${CLAUDE_PLUGIN_ROOT}/scripts/commitcraft-setup.sh --section <name> --yes

# Issue tracker (always — records the choice for commit/PR footers):
${CLAUDE_PLUGIN_ROOT}/scripts/commitcraft-setup.sh --section ticket --ticket <github|linear|jira|none>

# Signing, only if the user explicitly opted in:
${CLAUDE_PLUGIN_ROOT}/scripts/commitcraft-setup.sh --section signing --yes
```

`--yes` accepts each prompt's default; `--ticket` sets the tracker without prompting.

To set up the full standard stack in one shot instead of per-component:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/commitcraft-setup.sh --yes --ticket <tool>
```

## Phase 4: Branch protection (explicit confirm)

Only if the user said yes in Phase 2. This is the one irreversible, outward-facing
step — confirm once more before running, then:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/commitcraft-setup.sh --section branch-protection --apply-branch-protection
```

It derives the required status checks from the workflows that got installed
(`commitlint`, `gitleaks`) and applies them to the default branch. Defaults to
`reviews: 1` + `enforce_admins`. For a **solo or marketplace repo** with no second
approver, ask whether to relax those and pass:

```bash
... --apply-branch-protection --pr-reviews 0 --no-enforce-admins
```

`--pr-reviews 0` drops the review requirement (so the maintainer can self-merge);
the required CI checks still gate. An explicit `--apply-branch-protection` also
re-applies over an existing *hollow* protection (one with no required checks).

## Phase 5: Verify

Re-run the check and report the before/after to the user:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/commitcraft-setup.sh --check
```

A component that exists but isn't a *required* check shows as
`NOT REQUIRED (runs but doesn't gate)` — flag that, since it means merges aren't
actually blocked yet.

---

**Manual / single-section use (humans):** the script is still fully interactive when
run without flags — `${CLAUDE_PLUGIN_ROOT}/scripts/commitcraft-setup.sh` walks all
sections, or `--section <name>` runs one.
