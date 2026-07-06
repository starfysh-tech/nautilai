# Plugin page slots

Rules for filling `_TEMPLATE.html` to produce the remaining plugin pages. Follow
these exactly — they exist so 15 pages read as one site, not 15 improvisations.

Base every page on a plugin's own `README.md` and `.claude-plugin/plugin.json`.
Do not invent capability, and do not pull claims from the marketplace index's
one-line description alone — that copy is already compressed; go back to the
README for the full sentence.

## Slot list

| Slot | Source | Rule |
|---|---|---|
| `{{NAME}}` | `plugin.json` `name` | Lowercase, matches the plugin directory name exactly (e.g. `commitcraft`, not `CommitCraft`). Used in `<title>`, the H1, and the footer source link. |
| `{{TAGLINE}}` | README first paragraph / `plugin.json` `description` | One sentence, ≤ 160 characters. State what it does, not why it's good. No adjectives like "powerful", "seamless", "comprehensive". |
| `{{META_DESCRIPTION}}` | `plugin.json` `description` | Copy verbatim or near-verbatim — this is already the vetted, accurate one-liner. Used in `<meta name="description">` and `og:description`. |
| `{{INSTALL_CMD}}` | Fixed pattern | Always `plugin install <name>@nautilai`. Never hand-write a different form. |
| `{{WHAT_IT_DOES}}` | README body | 2–4 sentences, evidence-toned. Describe the mechanism (what actually runs), not the benefit. If the README documents a validated/unvalidated scope (see autodev), summarize the caveat in one sentence rather than omitting it — never round an unvalidated claim up to general capability. |
| Commands / skills (`skill-list` items) | README "Usage"/"Workflows"/skill directory listing | One `<li>` per command or workflow: `sk-name` (the literal invocable command, e.g. `/plugin-name` or `/plugin-name subcommand`), a one-sentence `<p>` description, and `sk-triggers` — the natural-language trigger phrases *only if the README states them explicitly* (in quotes). If the README doesn't document natural-language triggers, write "explicit slash form only" rather than guessing a phrase. |
| `{{HOW_IT_WORKS}}` | README "How it works" / "Architecture" section | Condense, don't copy wholesale. Prefer a short `<ul>` of mechanism bullets over prose paragraphs if the README itself uses a bulleted mechanism list (matches autodev's page). Cap at ~6 bullets or ~3 short paragraphs. Cite specific script/file names from the README where it aids credibility (e.g. `verify.sh`), but do not invent file paths not present in the README. |
| `{{REQUIREMENTS}}` (whole section) | README "Requirements"/"Install" prerequisites | **Omit the entire `<section id="requirements">` block** if the plugin needs nothing beyond Claude Code itself (see relay.html — no requirements section). Otherwise one paragraph: tools/binaries needed, and which are optional vs. degrade gracefully. |
| Footer source link | Fixed pattern | Always `https://github.com/starfysh-tech/nautilai/tree/main/<plugin-dir>` — `<plugin-dir>` is the top-level directory name, which may differ from the display name (e.g. relay's directory is `relay`, but double-check against the actual repo layout, not assumption). |

## Current-state-only rule

These pages describe what a plugin does now — never how it came to be that way.
Delete, don't soften, anything that reads as history:

- Past incidents or motivating events ("a transcript hijacked the extractor
  during testing", "a bug in v1 caused...").
- Eval-run or benchmark history ("across 3 eval runs it recovered 11/12,
  12/12...", scorecards, before/after numbers).
- Rejected alternatives or removed mechanisms ("a `Stop` hook was rejected",
  "an earlier iteration ran X and was removed").
- Phase/timeline language: "was built", "used to", "originally", "superseded",
  "an earlier iteration".

What stays: the current behavior stated as a present-tense fact, even if a
past incident is *why* that behavior exists. Keep the mechanism, drop the
story. Example — keep "`haiku-narrative.sh` runs Haiku with a bare
`--system-prompt` and treats transcript content as data, never commands" (what
the script does now); drop "a transcript hijacked the extractor during
testing" (why it was built that way). Keep "recovers Decisions/Dead ends/Constraints
from assistant prose" (current capability); drop "11/12, 12/12" scorecards
(how that capability was measured historically).

Net effect on the `<details class="tech">` blocks: a "Design notes" block
that is *entirely* history gets deleted outright. A block with some
current-fact bullets and some history gets its history bullets removed and
the survivors folded into "Under the hood" (or a section literally titled
"Behavior" if neither fits) — don't leave a near-empty "Design notes" block
standing. A block that turns out to be all current-state facts (a convention,
an invariant, a degrade contract) still gets folded into "Under the hood"
and the "Design notes" heading retired — that heading itself implies a
decision narrative this rule no longer wants on the page, even when the
content underneath was already compliant.

## Tone rules (apply everywhere)

- Nautical, terse, confident — matches the index page's voice ("Browse the reef", "Dive readout"). Don't force a nautical pun into every sentence; the index uses maybe one per section, not one per line.
- No marketing adjectives: banned words include "production-ready", "comprehensive", "powerful", "seamless", "robust", "cutting-edge". Repo-wide accuracy policy (see root `CLAUDE.md`) applies to these pages too.
- Every factual claim must trace to the plugin's own README or `plugin.json`. If the README hedges (validated on X, not Y), the page must hedge the same way — do not launder a hedge into a flat claim.
- Sentences over fragments. No arrow chains (`A → B`) in prose; use them only inside a mechanism bullet list, and only if the README itself uses that shorthand.
- Second person is fine for instructions ("install it"), but avoid direct address in descriptive prose ("you'll love how...").

## What to omit

- Don't include a Troubleshooting section — that stays in the README; these pages are an overview, not full documentation.
- Don't include version numbers (`plugin.json` `version`) — they go stale immediately since release-please bumps them across all plugins together.
- Don't include a Roadmap/Backlog section from the README — that's contributor-facing, not user-facing.
- Don't add badges, shields, or icons beyond what the template already provides (the copy button).

## Reusable components: flow diagram + tech detail

Both live in `_TEMPLATE.html`'s inline `<style>` (`.flow`/`.flow-lane*`/
`.flow-split`/`.flow-legend` and `details.tech`), with commented example
markup blocks in the `<section id="how">` body — copy the markup, don't
reinvent the classes.

**Flow diagram** (`.flow`, `.flow-step`, `.flow-arrow`, `.flow-split`,
`.flow-legend`, `.flow-lanes`/`.flow-lane`) — a row of numbered step boxes
joined by `→` arrows, pure HTML/CSS (small inline `<svg>` icons are fine as
markup; no external SVG files, no JS). Below 560px it collapses to a column
and the arrows become `↓` automatically. **Every plugin page must include at
least one flow diagram** in "How it works", capturing its core mechanism end
to end.

- **Numbered steps.** Every `.flow-step` carries a `<span class="fs-num">`
  badge with its position (`1`, `2`, `3`…) inside a `<span class="fs-body">`
  holding a `<span class="fs-label">` (short mechanism noun/verb — a label,
  not a sentence) and an optional `<span class="fs-sub">` naming the actual
  script/hook/skill that runs that step, in monospace. Omit `fs-sub` for a
  step the README doesn't tie to a specific script — don't invent one to fill
  the slot. Numbering restarts at 1 in each separate `.flow`/`.flow-lanes`
  group; two diagrams on one page are independently numbered.
- **Decision points.** Where the README documents an actual branch (a real
  ok/degrade or pass/fail split, never an invented one), mark the fork with a
  `.flow-split` connector — a small inline SVG branch icon — between the last
  shared step and the `.flow-lanes` below it, and add a `.flow-legend` above
  the lanes pairing each lane's color with its condition in text (e.g. "within
  TTL" / "TTL expired") so the distinction never rests on color alone.
- **Lanes.** `.flow-lane[data-lane="ok"]` renders in the tide color with a ✓
  prefix on its label; `.flow-lane[data-lane="degrade"]` renders in a warm
  `--lumen` tint with a ⚠ prefix — both the tint and the icon carry the
  distinction, never color alone. Only add lanes for a branch the README
  actually names (e.g. relay's TTL expiry, autodev's review-gate pass vs.
  3-strike escalation).
- **Cap: 7 steps total** per diagram, counting every lane. A mechanism that
  needs more than 7 steps to make sense should become two separate diagrams
  (each independently numbered, each ≤7) rather than one crowded one — see
  relay's page (write path / SessionStart pickup) and autodev's (pipeline /
  verify-and-branch) for the pattern.

**Collapsible tech detail** (`<details class="tech"><summary>…</summary><div
class="tech-body">…</div></details>`) — native disclosure, no JS, themed
marker (chamber background, tide summary text, rotating `▸`). Use it for:

- **"Under the hood"** — script/file names and what each does, data flow,
  exit codes or degrade contracts, env vars, storage paths. **Every plugin
  page must include at least one of these.** Fold any current-state design
  facts here too (see the current-state-only rule above) — a standalone
  "Design notes" heading is retired; don't add one to new pages.

Both sections apply the same no-invention rule as everywhere else: every
bullet must trace to the plugin's own README/SCHEMA/scripts — never inferred
behavior. **Cap: 25 lines per `<details>` block** (counting bullets, not
markup) — this is a technical appendix, not the full README pasted in.

## Structural checklist before calling a page done

1. `<title>` is `"<name> — nautilai"`, exactly.
2. Breadcrumb link is `../index.html#plugins` with text `← all plugins` (appears twice: top and footer).
3. Install copy-button `data-copy` value matches the visible install command exactly, including the leading `/`.
4. Every `<section>` has an `<h2>`, except the requirements section may be omitted entirely — never left as an empty shell.
5. No unresolved `{{SLOT}}` placeholders remain anywhere in the file.
6. Run a structural sanity check (balanced tags) before considering the page done — e.g. `python3 -c "import html.parser,sys; p=html.parser.HTMLParser(); p.feed(open(sys.argv[1]).read())" docs/plugins/<name>.html` should raise no exception.
7. At least one `.flow` diagram appears in "How it works" with numbered `fs-num` steps, ≤7 steps total per diagram (split into a second diagram if the mechanism needs more), sourced from the README's own mechanism description; any lane split uses `.flow-split` + `.flow-legend` and both a color and an icon per lane.
8. At least one `<details class="tech">` block is present ("Under the hood" is required), ≤25 lines, with no invented facts, and no history/incident/eval-run narrative per the current-state-only rule — no standalone "Design notes" heading.
