# Dual-runtime: Claude Code + Hermes Agent from one upstream

## Goal

nautilai skills are installable and functional in Hermes Agent, while every existing Claude Code
plugin keeps its current behavior byte-for-byte.

## What we learned (empirically, on Hermes v0.18.2)

> **The original plan was built on three doc claims that turned out to be false.** All of the
> following are *observed*, not doc-derived.
>
> - **skills.sh indexes by skill NAME, at any depth — no repo-root `skills/` needed.**
>   `hermes skills inspect starfysh-tech/nautilai/autodev` resolves to
>   `skills-sh/starfysh-tech/nautilai/autodev`, having found `autodev/skills/autodev/SKILL.md` at
>   depth 3. All 19 nautilai skills resolve this way **today, with zero repo changes**.
> - **`hermes skills tap add` is functionally dead in v0.18.2.** It registers a row, prints no fetch
>   or index step, persists no `taps.json`, and the `github` source is permanently skipped as "slow"
>   (`⚡ Slow sources skipped: github`). Taps never surfaced a single skill. skills.sh — not the tap —
>   is the real distribution channel, and it requires no opt-in from us.
> - **Frontmatter `version`/`author`/`license` are NOT enforced.** autodev installed cleanly without
>   them. `argument-hint` survives intact. Docs claimed otherwise.
> - **Install copies the skill directory ONLY.** autodev installed as exactly
>   `SKILL.md, references/worktree-gotchas.md`. Its `autodev/scripts/` (plugin root, one level up)
>   **did not ship** — so all 21 of its script references dangle.
> - **`${CLAUDE_PLUGIN_ROOT}` is passed through to the Hermes runtime as a LITERAL token.** Confirmed
>   in a live session. Hermes does not substitute it.
> - **`${HERMES_SKILL_DIR}` substitutes EVERYWHERE — prose, inline backticks, and fenced code blocks.**
>   Verified with `probe-core`: `FENCE_BASH=/Users/…/skills/probe-core/scripts/exec-bit.sh`. The
>   runtime-adapter design is viable.
> - **All bundled resource dirs survive install** — `scripts/`, `templates/`, `workflows/`,
>   `references/` all landed. The Step 1 file-move fix is therefore correct.
> - **The security scanner passes git-hook-writing skills.** `probe-hooks` (writes `.git/hooks/`,
>   mutates git config, runs `npm install`, makes a network call) → `Verdict: SAFE`,
>   `Decision: ALLOWED`, with only a MEDIUM `supply_chain` note. CommitCraft's `setup` will pass.
> - **The EXECUTABLE BIT IS STRIPPED ON INSTALL.** `exec-bit.sh` shipped `100755` in git and landed
>   `644`; its `644` control landed `644` too. Direct invocation fails:
>   `/bin/bash: …/exec-bit.sh: Permission denied`. **Every bundled script must be invoked as
>   `bash <path>`.**
> - **Install is interactive** (`Install 'probe-core'? Confirm [y/N]:`) — relevant for any CI smoke test.

**Net effect: the entire generated-bundle architecture is deleted.** No repo-root `skills/`, no
generator, no CI drift gate, no release-please fan-out, no tap. nautilai is *already* discoverable
and installable. The only real defect is that bundled resources don't ship and paths don't resolve.

## The actual problem, precisely scoped

Two things, and nothing else:

1. **Resources live outside the skill dir.** `<plugin>/scripts/` and `<plugin>/templates/` are
   siblings of `<plugin>/skills/`, so Hermes never copies them. Affects `commitcraft` (19 path refs)
   and `autodev` (21). The other four in-scope plugins are pure markdown with **zero** path refs.
2. **The path token doesn't resolve in Hermes.** `${CLAUDE_PLUGIN_ROOT}` arrives literal.

## Fix

> ## Prime directive: ZERO impact to Claude Code
>
> Claude Code's marketplace, plugin manifests, path resolution, scripts, templates, tests, and
> workflows are **not modified**. `commitcraft/scripts/` and `commitcraft/templates/` stay exactly
> where they are. All 19 `${CLAUDE_PLUGIN_ROOT}` references stay exactly as they are. Both bash test
> suites stay as they are.
>
> **The total Claude-visible diff is one additive section appended to one `SKILL.md`.** Everything
> else is either a new file Claude never reads, or a change outside the plugin dirs.
>
> Any Claude regression is a release blocker.

### Step 1 — Mirror commitcraft's resources into the skill dir (Hermes-only, generated)

Hermes ships the **skill directory only**, so it needs `scripts/` and `templates/` to exist *inside*
it. Rather than relocating Claude's copies, we **generate a mirror**:

```
commitcraft/scripts/    →  commitcraft/skills/commitcraft/scripts/     (generated)
commitcraft/templates/  →  commitcraft/skills/commitcraft/templates/   (generated)
```

- `commitcraft/scripts/` and `commitcraft/templates/` remain the **source of truth**, untouched, and
  are what Claude Code continues to use.
- The mirrored copies are **inert to Claude** — nothing in `plugin.json` or any Claude-loaded file
  references them. Claude neither reads nor validates them.
- `hermes/sync-resources.sh` copies them; `hermes/sync-resources.sh --check` regenerates to a temp dir
  and diffs, so the mirror **cannot drift**. This is the price of zero Claude impact, and it is paid
  by CI rather than by a human.

Keep `tests/` at the plugin root and out of the mirror — it isn't a runtime resource.

### Step 2 — Runtime adapter section (the ONLY Claude-visible change)

**A1 is answered: `${HERMES_SKILL_DIR}` substitutes in prose, inline backticks, AND fenced code
blocks** (verified with `probe-core`). Each runtime substitutes its own token and ignores the other's,
so one additive section serves both — and Claude's existing invocation lines are left alone:

```markdown
## Resource paths

- **Claude Code:** `${CLAUDE_PLUGIN_ROOT}/scripts/commitcraft-setup.sh --check`
- **Hermes:** `bash ${HERMES_SKILL_DIR}/scripts/commitcraft-setup.sh --check`
```

Two things this buys us:

- **Claude's paths are unchanged** — it keeps calling the plugin-root scripts exactly as today.
- **The `bash` prefix is confined to the Hermes line.** Hermes **strips the executable bit on install**
  (verified: `exec-bit.sh` shipped `100755`, landed `644`, direct call → `Permission denied`). Claude
  keeps its direct invocation; only Hermes needs the interpreter prefix. No shared-file compromise.

Only `commitcraft` needs this section. The other four in-scope plugins have zero path references and
require **no changes at all** — they already work in Hermes today.

> **Documented limitation — token substitution can be switched off.** Hermes honors
> `skills.template_vars: false` in `~/.hermes/config.yaml`, which disables `${HERMES_SKILL_DIR}`
> substitution globally. With that set, bundled-script paths arrive literal and commitcraft's Hermes
> invocations break. It is a user-side setting a skill cannot detect or override — so it is a
> **documented limitation**, not a code fix. Note it in commitcraft's README. It has no effect on
> Claude Code.

> **Documented limitation — token substitution can be switched off.** Hermes honors
> `skills.template_vars: false` in `~/.hermes/config.yaml`, which disables `${HERMES_SKILL_DIR}`
> substitution globally. With that set, every bundled-script path arrives literal and commitcraft's
> script invocations break. This is a user-side setting we cannot detect or override from a skill —
> so it is a **documented limitation**, not a code fix. State it in the Hermes section of
> commitcraft's README.

### Step 3b — `skills.sh.json` at the repo root

Documented, schema-backed, and cheap. It defines Skills Hub groupings **and** is the only place we can
state which nautilai skills are Hermes-supported:

```json
{
  "$schema": "https://skills.sh/schemas/skills.sh.schema.json",
  "groupings": [
    { "title": "Git workflow",       "skills": ["commitcraft"] },
    { "title": "Planning & review",  "skills": ["review-plan", "pr-review-deep", "pr-comment-review", "dep-review"] }
  ]
}
```

It groups; it does **not** hide. Unlisted skills remain installable (see Step 3).

### Step 3 — Scope control

`github-issue-auditor` is **already publicly resolvable in Hermes**
(`skills-sh/starfysh-tech/nautilai/github-issue-auditor`) despite being explicitly out of scope. This
is not something we opted into; skills.sh indexed the whole repo. Decide deliberately: leave it (and
document it as unsupported in Hermes), or make it non-functional there. There is no mechanism to
*hide* it from skills.sh short of removing it from the repo.

Same applies to every non-prioritized skill — `phi-scan`, `rbac-*`, `wireframe`, `frontend-review`,
`relay`, `cc-*`. They are all live in Hermes right now, unsupported and untested.

### Step 4 — Docs

Each in-scope plugin's README + `docs/plugins/<name>.html` gains the five required headings: shared
behavior · Claude Code invocation · Hermes invocation · runtime-specific limitations · update behavior.

Document the **real** Hermes lifecycle — not the one from the brief:

```bash
hermes skills install skills-sh/starfysh-tech/nautilai/commitcraft
hermes skills check
hermes skills update
```

Do **not** document `hermes skills tap add` — it does not work. Do not document
`hermes skills search`/`browse` as a discovery path either; the `github` source is skipped and
nautilai does not appear.

State plainly: **autodev is Claude-only** (its value is subagent fan-out + worktree isolation, which
Hermes has no equivalent for), and **Hermes has no subagents**, so review skills run the inline
fallback they already document (`review-plan/skills/review-plan/SKILL.md:59`).

### Step 5 — CommitCraft `issue_tracker: none`

Already built: `commitcraft/scripts/commitcraft-issues.sh:27` reads `ticket_tool` with
`github|linear|jira|none`. Verify `none` is a true short-circuit — skips lookup (`:86-106`), blocking
labels (`:115-122`), acceptance criteria (`:124-141`) — and that `workflows/pr.md:133-149` emits no
issue section rather than a `NO_ISSUE` failure state. Confirm `setup.md` offers it, and that
`gh`-absent degradation (`:72-84`) stays graceful (Hermes users may have no `gh`).

---

## Validation

Everything below was verified against a live Hermes v0.18.2 and a live Claude Code, using a
throwaway probe repo shaped like commitcraft (`starfysh-tech/hermes-probe`) rather than by
reasoning from documentation — which proved unreliable (see "What we learned").

**Verified — Hermes runtime**

- `${HERMES_SKILL_DIR}` substitutes in prose, inline backticks, **and fenced code blocks**.
- `scripts/`, `templates/`, `workflows/`, `references/` all survive install.
- The **executable bit is stripped** (`100755` → `644`; direct call → `Permission denied`) —
  hence `bash <path>` on the Hermes line.
- The security scanner returns **SAFE / ALLOWED** for a skill that writes git hooks, mutates git
  config, runs a package install, and makes a network call.

**Verified — the adapter, in both runtimes, directly and through a workflow file**

| | direct | via workflow file |
| --- | --- | --- |
| Claude Code | runs the **plugin-root** copy | runs the **plugin-root** copy |
| Hermes | runs the **mirrored** copy | runs the **mirrored** copy |

Neither runtime ever followed the other's line or touched the other's copy.

**Verified — zero Claude impact.** No change to `commitcraft/scripts/**`, `templates/**`,
`tests/**`, or any `.claude-plugin/**`. `claude plugin validate --strict`, both bash suites, and
the marketplace-sync check all pass.

**Verified — `ticket_tool: none` is a true short-circuit.** `commitcraft-issues.sh:31-36` returns
`STATUS: NO_ISSUE` and exits 0 *before* any `gh` call; `workflows/pr.md` maps `NO_ISSUE` to "no
issue link". No lookup, no linking, no comment, no `gh` dependency. Already built — no code change.

**Not yet verified**

- [ ] `commitcraft-setup.sh` itself passing the Hermes scanner. `probe-hooks` is a close analogue
      (git hooks + config + npm + network → SAFE), but it is not the real script. A *dangerous*
      verdict cannot be bypassed even with `--force`.
- [ ] `hermes skills update` round-tripping a content change **without** a `version:` bump. If the
      hash turns out to be version-based rather than content-based, every release must bump
      `version:` in SKILL.md.

**Worth remembering:** `${CLAUDE_PLUGIN_ROOT}` inside `workflows/*.md` is **not** a shell variable
and is **not** substituted by the harness — running it verbatim yields `/scripts/foo.sh` and exit
127. Claude resolves it *from context*. CommitCraft has always depended on that, so the Hermes
adapter's translation rule leans on the same mechanism rather than introducing a new one.

## Explicitly not doing

- **No repo-root `skills/` directory** — skills.sh indexes by name at any depth. Proven unnecessary.
- **No generator, no bundle, no CI drift gate, no release-please fan-out.** All of it existed to
  satisfy a flat-discovery requirement that does not exist.
- **No `tap add` support.** Dead in v0.18.2. Do not document it; do not design for it.
- **No Hermes port of autodev** — no subagent primitive in Hermes.
- **No GitHub Issue functionality** in the Hermes path.
