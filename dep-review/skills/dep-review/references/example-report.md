# Worked examples

Illustrative only — paths and PR numbers are made up. They show the *shape* of a
grounded verdict (evidence cited, action gated), not real data.

## Example: single-PR MERGE (gated)

```markdown
### PR #614: lodash 4.17.20 -> 4.17.21

**Verdict: MERGE** (High confidence)

- Change type: patch
- CI: passing
- Security: fixes CVE-2021-23337 (command injection in `_.template`)
- Usage: `Grep "_.template"` -> not found; lodash used only for `_.groupBy`,
  `_.debounce` (src/utils/format.ts:8, src/hooks/useSearch.ts:21)
- Impact: NONE on the vulnerable path; patch elsewhere

**Why safe:** patch bump, CI green, the CVE's `_.template` path is unused here, and
the functions we do use are unchanged between .20 and .21.

**Disposition:** AUTO-MERGE — patch bump, CI green, no breaking changes (the unused
CVE path doesn't force a gate), so it merges without a prompt; reported here for the
record (PR #, package, from→to, merge commit).
```

## Example: single-PR SKIP (gated close)

```markdown
### PR #618: moment 2.29.4 -> 2.30.1

**Verdict: SKIP** (High confidence)

- Change type: minor
- Usage: `Grep "from ['\"]moment"` / `Grep "require\\(['\"]moment"` -> not found in src/
- moment is in package.json but unreferenced; the codebase uses date-fns
  (src/utils/date.ts:3)

**Why skip:** dead dependency — no import sites. Recommend closing this PR and
opening a removal issue for `moment`.

**Disposition:** ask-user — I will not close it on my own. Approve the close (and the
removal issue) via the gate.
```

## Example: batch run

```markdown
## Dependabot PR batch review (5 open)

| PR | Package(s) | Change | Verdict | Disposition |
|----|------------|--------|---------|-------------|
| #614 | lodash 4.17.20->4.17.21 | patch (CVE) | MERGE | gated |
| #615 | the npm group (6 dev deps) | patch/minor | MERGE | gated |
| #616 | react 18.2->18.3 / react-dom 18.2->18.3 | minor (paired) | MERGE | gated, together |
| #617 | webpack 5->6 | major | INVESTIGATE | report only |
| #618 | moment 2.29.4->2.30.1 | minor (unused) | SKIP | gated close |

**Summary:** 3 gated MERGEs (one paired), 1 INVESTIGATE, 1 gated SKIP.

I'll present the gated actions for approval in one prompt. #616's react/react-dom
merge together (version parity). Nothing lands without your go-ahead.
```
