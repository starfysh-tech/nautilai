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

## Structural checklist before calling a page done

1. `<title>` is `"<name> — nautilai"`, exactly.
2. Breadcrumb link is `../index.html#plugins` with text `← all plugins` (appears twice: top and footer).
3. Install copy-button `data-copy` value matches the visible install command exactly, including the leading `/`.
4. Every `<section>` has an `<h2>`, except the requirements section may be omitted entirely — never left as an empty shell.
5. No unresolved `{{SLOT}}` placeholders remain anywhere in the file.
6. Run a structural sanity check (balanced tags) before considering the page done — e.g. `python3 -c "import html.parser,sys; p=html.parser.HTMLParser(); p.feed(open(sys.argv[1]).read())" docs/plugins/<name>.html` should raise no exception.
