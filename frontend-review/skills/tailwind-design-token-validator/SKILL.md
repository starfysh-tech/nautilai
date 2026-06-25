---
name: tailwind-design-token-validator
description: Audit a React/TypeScript + Tailwind frontend for design-token violations — arbitrary values like bg-[#3b82f6], dynamic class concatenation that breaks purging, @apply overuse, inline styles, and missing accessibility attributes. Auto-detects the frontend source root and the Tailwind config; every finding cites file:line. Use when the user asks to validate Tailwind token usage, find arbitrary color/spacing values, check design-system compliance, or spot class-concatenation anti-patterns. User-invoked — does not auto-fire.
argument-hint: "[path]"
disable-model-invocation: true
context: fork
allowed-tools: [Read, Glob, Grep, Edit, Bash(python3:*)]
---

# Tailwind Design Token Validator

Audit a React/TypeScript + Tailwind codebase for design-token violations and
class-usage anti-patterns, validating against the project's own Tailwind config. Most
findings are propose-only; a narrow class of exact, reversible token swaps may be
auto-fixed under the safety contract below — and only after the user opts in.

This skill ships a bundled Python analysis engine under
`${CLAUDE_PLUGIN_ROOT}/skills/tailwind-design-token-validator/scripts/`. Run it (step 2)
to produce the findings rather than reimplementing the checks by hand; use
`Glob`/`Grep`/`Read` to confirm or contextualize a finding. The project's Tailwind config
is the source of truth for what a "token" is — the engine extracts it via Tailwind's
`resolveConfig` (Node) and falls back to regex parsing if Node/Tailwind isn't available.

## Shoals (project corrections)

At the start of a run, read `.claude/shoals/frontend-review.tailwind-design-token-validator.md`
from the project root if it exists, and honor every entry as a constraint.

When the user corrects your behavior — an arbitrary value they intend to keep, a
token mapping they reject, a pattern they don't want flagged — append a shoal to that
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

### 1. Resolve the frontend root and Tailwind config

Do **not** assume `client/` or any fixed path. Detect both:

- If `$ARGUMENTS` names a path, scan that; otherwise auto-detect the React source root
  (`Glob` for `**/package.json` with `"tailwindcss"`/`"react"`, take its source dir —
  nearest of `src/`, `app/`, `client/src/`, etc.). Skip `node_modules`, `dist`,
  `build`, `.next`, `coverage`, dot-dirs.
- `Glob` for the Tailwind config: `**/tailwind.config.{js,ts,cjs,mjs}`, or a `@theme`
  block / `@import "tailwindcss"` in a CSS file (Tailwind v4 CSS-first config). Read it
  and extract the defined semantic tokens (colors, spacing, radii, etc.).
- If no config is found, say so and proceed with stock-Tailwind assumptions, flagging
  that token *mappings* are best-effort without the project's palette.
- If candidates are ambiguous (monorepo), list them and ask which to audit.
- State the resolved root + config path in one line before reporting findings.

### 2. Run the checks

Run the bundled engine against the resolved root + config. It pulls semantic tokens
from the config, scans every `.tsx`/`.jsx` (and `.css` for `@apply`), runs the
token/anti-pattern checks plus the accessibility checks, enriches arbitrary-value
findings with token suggestions, and prints a severity-grouped report with `file:line`:

```bash
ROOT="<resolved source root>"          # from step 1
CONFIG="<resolved tailwind.config.*>"  # from step 1
PYTHONPATH="${CLAUDE_PLUGIN_ROOT}/skills/tailwind-design-token-validator/scripts" \
  python3 -c '
import sys
from analyze_tailwind_config import TailwindConfigAnalyzer
from scan_components import ComponentScanner
from validate_class_usage import TailwindClassValidator
from check_accessibility import AccessibilityChecker
from suggest_tokens import TokenSuggester
from generate_report import ReportGenerator

root, config = sys.argv[1], sys.argv[2]
tokens = TailwindConfigAnalyzer(config).extract_tokens()
scanner = ComponentScanner(root)
validator, a11y = TailwindClassValidator(tokens), AccessibilityChecker()
violations = []
for f in scanner.scan():
    lines = scanner.read_file_lines(f)
    violations += validator.validate_file(f, lines)
    violations += a11y.check_file(f, lines)
for c in scanner.scan_css_files():
    violations += validator.check_apply_overuse(c, scanner.read_file_lines(c))
violations = TokenSuggester(tokens).generate_suggestions(violations)
print(ReportGenerator(violations).generate_text_report())
' "$ROOT" "$CONFIG"
```

`ReportGenerator` also offers `.generate_json_report()` (CI/CD) and
`.generate_markdown_report()`. If no config is found, skip the `TailwindConfigAnalyzer`
step and pass `tokens={}` — checks still run; token *mappings* become best-effort.
Each finding below maps to a module; cite `file:line` for every finding.

| Check | How to detect | Severity |
|---|---|---|
| **Arbitrary values** | `bg-[#...]`, `text-[14px]`, `p-[13px]`, etc. that a defined token covers | high |
| **Dynamic class concatenation** | `` `border-[${color}]` `` / template-literal class names that break purging | high |
| **Inline styles** | `style={{ ... }}` where a utility class exists | medium |
| **@apply overuse** | many `@apply` directives in CSS (should be minimal) | medium |
| **Responsive misuse** | non-mobile-first usage / desktop-down overrides | low |
| **Accessibility gaps** | interactive elements missing `aria-*`, focus states, or semantic HTML | medium |

Notes:
- An arbitrary value is only a violation if a token *actually covers it*. `w-[473px]`
  with no matching token is a `report`, not an auto-fixable swap.
- Dynamic concatenation is never auto-fixable — it needs a safelist or variant map, a
  judgment call. Report it.

### 3. Report (findings-first)

Lead with findings, grouped by check, highest-severity first. **Omit any check that
came back clean.** For each: `file:line`, the offending class/attribute, and the
suggested token or fix. End with a recommended-action list only if there are findings.

## Finding dispositions

Per the nautilai finding-dispositions convention:

- **auto-fix** — *only* an arbitrary value that maps **1:1 to a defined token with an
  identical computed value** (e.g. `bg-[#3b82f6]` → `bg-primary` when the config
  defines `primary: #3b82f6`). This is mechanical, reversible, and intent-preserving.
  It is gated: propose the full swap list, get the user's go-ahead (it's still their
  call), then apply via `Edit` honoring the **safety contract** — the edit is
  VCS-visible, and you report each change as `file:line  old → new`. Never widen the
  swap to a value whose token equivalent isn't exact.
- **report** — arbitrary values with no exact token, dynamic class concatenation,
  inline styles, @apply overuse, responsive issues, accessibility gaps. Surface with
  `file:line` and a suggestion; the fix is the user's.
- **ask-user** — any swap that requires choosing *which* token (close-but-not-exact
  color, a spacing value between two tokens) or any structural change. Surface the
  options and wait. **Never** self-resolve — picking a token on the user's behalf is a
  judgment call, not an auto-fix.

> When unsure whether a swap is exact, treat it as `ask-user`. Under-acting is
> recoverable; a wrong silent class swap changes the rendered UI.

## What to flag

### Arbitrary values
```tsx
className="bg-[#3b82f6]"   // → bg-primary  (only if config defines primary: #3b82f6)
className="p-[13px]"       // report: no exact token; suggest nearest or a new token
```

### Dynamic class concatenation
```tsx
className={`border-[${color}]`}   // breaks purge; report → safelist or variant map
```

### Inline styles
```tsx
style={{ padding: '16px' }}       // → p-4
```

### @apply overuse / accessibility
- Many `@apply` lines in a CSS file → prefer utilities or a component class; report.
- Interactive element without `aria-*`/focus state/semantic tag → report with the
  specific gap.

## Gotchas

- **No fixed source path.** Always resolve the root + config (step 1); never hardcode
  `client/`. A monorepo has several configs — ask, don't merge them.
- **The config defines tokens, not your memory.** Map arbitrary values only against the
  project's actual palette/spacing. Without a config, mappings are best-effort — say so.
- **Only exact swaps auto-fix, and only after opt-in.** Anything approximate or
  structural is `ask-user`. A silent wrong swap changes the UI.
- **Dynamic class names are runtime.** A template-literal class can't be verified
  statically — report the purge risk, don't try to resolve it.
- **Accessibility here is shallow.** Basic ARIA/focus/semantic checks, not a full WCAG
  audit; don't present it as one.
