---
name: react-component-architecture
description: Audit a React + TypeScript frontend for component architecture — oversized components, prop drilling, duplicated UI patterns that should be extracted to primitives, loose-string variant props, and folder organization. Auto-detects the frontend source root; every finding cites file:line. Use when the user asks to review React component architecture, find prop drilling, spot duplicate components to extract, check composition patterns, or audit a component folder before a PR. User-invoked — does not auto-fire.
argument-hint: "[path]"
disable-model-invocation: true
context: fork
allowed-tools: [Read, Glob, Grep, Bash]
---

# React Component Architecture Audit

Review a React + TypeScript codebase for composition, reuse, prop drilling, variant
typing, and folder organization. This is a **read-only, propose-only** audit — it
reports findings and lets the user decide what to change. It never edits code.

This skill ships a bundled Python analysis engine under
`${CLAUDE_PLUGIN_ROOT}/skills/react-component-architecture/scripts/`. Run it (step 2)
to produce the findings rather than reimplementing the checks by hand; use
`Glob`/`Grep`/`Read` to confirm, contextualize, or extend a finding (e.g. show the prop
chain). Treat the thresholds below as defaults, not law — a project's own conventions
(or its shoals file) override them.

## Shoals (project corrections)

At the start of a run, read `.claude/shoals/frontend-review.react-component-architecture.md`
from the project root if it exists, and honor every entry as a constraint.

When the user corrects your behavior — a threshold they reject, a folder layout that
differs from the default, a pattern they don't want flagged — append a shoal to that
file (creating `.claude/shoals/` if needed):

```markdown
## <short title>
- **Trigger:** when this comes up
- **Wrong:** what you did that the user rejected
- **Correct:** what to do instead
- **Why:** the reason
```

Append-only — never edit or delete an entry; retire one with `- **Obsolete:** <date>
— <reason>`. Dedup on **Trigger**. Capture only explicit behavioral corrections, not
passing preferences. Mention the capture in one line; don't narrate it. Never write
outside `.claude/shoals/`.

## Workflow

Run in order. Stop after any step if the user wants to review before continuing.

### 1. Resolve the frontend source root

Do **not** assume `client/`, `src/`, or any fixed path. Detect it:

- If `$ARGUMENTS` names a path, scan that.
- Otherwise auto-detect: `Glob` for `**/package.json` containing `"react"`, then take
  that package's source dir — typically the nearest of `src/`, `app/`, `client/src/`,
  or the dir holding the most `.tsx` files. Skip `node_modules`, `dist`, `build`,
  `.next`, `coverage`, and dot-dirs.
- If several candidates exist (monorepo), list them and ask which to audit — don't
  guess across packages.
- State the resolved root in one line before reporting findings.

### 2. Run the checks

Run the bundled engine against the resolved root. It analyzes every `.tsx`/`.jsx`
component (skipping `node_modules`, `dist`, `.next`, `__tests__`, `*.test`/`*.spec`),
runs all checks below, and prints a findings report with `file:line`:

```bash
ROOT="<resolved source root>"   # from step 1
PYTHONPATH="${CLAUDE_PLUGIN_ROOT}/skills/react-component-architecture/scripts" \
  python3 -c "import sys; from architecture_reporter import ArchitectureReporter; print(ArchitectureReporter(sys.argv[1]).generate_full_report())" "$ROOT"
```

For a machine-readable summary (health score + violation counts) — e.g. a CI gate —
call `ArchitectureReporter(root).export_json(path)` or `.check_ci_gates(min_health_score=70)`
on the same module. Thresholds are configurable via the constructor's `config` dict
(`component_size_limit`, `prop_drilling_depth`, `min_duplicate_count`, `folder_structure`,
`type_coverage_threshold`, `complexity_threshold`) — see `references/sample_input.json`.

The engine's individual modules (`component_analyzer`, `prop_drilling_detector`,
`duplicate_pattern_finder`, `folder_structure_validator`) can also be run directly for a
single check. Each finding below maps to one of them; cite `file:line` for every finding.

| Check | How to detect | Default threshold |
|---|---|---|
| **Component size** | line count per component file | > 200 lines |
| **Prop drilling** | the same prop name threaded through 3+ nested components without use at the intermediate levels | depth > 3 |
| **Duplicate patterns** | near-identical JSX blocks (form buttons, error text, spinners, card headers) repeated across files | count ≥ 3 |
| **Folder organization** | primitives, feature components, and layouts mixed in one dir, or a primitive living under a feature | project layout vs. its own convention |
| **Variant typing** | a `variant`/`size`/`status`-style prop typed as `string` rather than a union | any |
| **Prop-interface coverage** | a component whose props are untyped or `any` | any |

Notes:
- Prop drilling needs the *chain* — show the component path (`A → B → C → D`) with the
  `file:line` of each hop, not just the leaf.
- "Duplicate pattern" means structurally repeated UI, not coincidental identical lines.
  Name the files and propose the primitive to extract.
- Folder organization is the softest check — infer the project's own convention from
  where the bulk of primitives/features/layouts already live before flagging an
  outlier. A project with a flat or colocated layout is not "wrong."

### 3. Report (findings-first)

Lead with findings, grouped by check, highest-impact first. **Omit any check that
came back clean** — no "✓ all good" sections, no per-step narration. For each finding:
`file:line`, what's wrong, and a concrete suggestion (the primitive to extract, the
composition to use, the union to write). End with a short recommended-action list only
if there are findings.

## Finding dispositions

Per the nautilai finding-dispositions convention, every finding is one of:

- **auto-fix** — *none.* This audit is propose-only; it never edits code. Component
  splits, prop-drilling refactors, extractions, and variant retyping all require
  judgment about intent and are out of scope for a silent edit.
- **report** — every finding above: surface it with `file:line` and a suggestion, then
  stop. The remediation is the user's to perform.
- **ask-user** — before acting on any proposed restructuring ("want me to extract
  this primitive / split this component?"). Never self-resolve: surface it and wait
  for the user to opt in. Do not start editing because a finding "looks obvious."

## What to flag

### Component size
Files over ~200 lines are split candidates. Suggest concrete extractions (e.g.
`<FormInput>`, `<FormButton>`, `<FormError>` out of a 245-line `LoginForm`), citing the
ranges to pull out.

### Prop drilling (composition over threading)
A prop passed through 3+ levels that the intermediate components don't use is a
composition smell. Suggest `children`/render props or a context provider. Show the
chain with `file:line` per hop.

### Duplicate patterns → primitives
2–3 copies of the same UI block is the extract threshold. Common ones: submit buttons,
error messages, spinners, card headers. Name every file and propose one reusable
primitive with a typed prop surface.

### Variant typing
```tsx
// flag
type ButtonProps = { variant: string; size: string };
// suggest
type ButtonProps = {
  variant: 'primary' | 'secondary' | 'ghost' | 'danger';
  size: 'sm' | 'md' | 'lg';
};
```

### Prop-interface coverage
Every component should have an explicit, non-`any` prop type. Flag untyped/`any` props
and suggest the interface.

## Gotchas

- **No fixed source path.** Always resolve the root (step 1); never hardcode `client/`
  or `src/`. A monorepo has several — ask, don't merge them.
- **Thresholds are defaults.** A team may intentionally allow larger components or a
  colocated folder layout; honor a shoal that says so over the table above.
- **Duplicates require structure, not string match.** Don't flag coincidentally
  identical lines (imports, a common className) as a reusable pattern.
- **Static analysis only.** Dynamically imported or runtime-generated components and
  props are invisible here — say so rather than guessing.
- **Propose, don't edit.** Even an "obvious" split is `ask-user`. Report and wait.
