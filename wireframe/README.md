# Wireframe

Create low-fidelity wireframes for UI planning — **ASCII** text layouts, **wiremd** interactive prototypes (HTML/React export), or **Mermaid** diagrams for tickets and PRs. Use it to sketch structure, flows, and states before writing components.

Distributed as a plugin via the [**nautilai**](../README.md) marketplace.

## Install

```text
/plugin marketplace add starfysh-tech/nautilai
/plugin install wireframe@nautilai
```

Core ASCII and Mermaid modes have no dependencies. Optional extras:

- `python3` on your PATH — for the bundled component-catalog script (stdlib-only; fails open if absent).
- The third-party [`wiremd`](https://github.com/wiremd/wiremd) CLI — only if you render wiremd prototypes to HTML/React. Not bundled.
- `node` plus [`beautiful-mermaid`](https://github.com/lukilabs/beautiful-mermaid) (`bun add -g beautiful-mermaid`) — only to validate and preview Mermaid diagrams as ASCII in the terminal. Not bundled; without it Mermaid mode still works, just unvalidated.

## Use

```text
Wireframe the item list page          # ASCII (default)
Create a wiremd for the dashboard      # interactive prototype
Flowchart for the signup flow          # Mermaid diagram
```

## Modes

1. **ASCII** (default) — text boxes, forms, and annotations for quick layout iteration. Zero dependencies.
2. **wiremd** — Markdown-ish syntax that renders to clickable HTML or exports React components via the separate `wiremd` CLI.
3. **Mermaid** — flowcharts, sequence, and state diagrams that render inline in GitHub issues/PRs, VS Code, and the Mermaid Live Editor. Each diagram is parsed before you see it, so a malformed block never reaches an issue; when the optional renderer is installed you also get an ASCII preview in the terminal.

The skill defaults to ASCII and switches modes when the request names wiremd or Mermaid. See the skill's `references/reference.md` for full syntax cheat sheets.

## Reference real components (optional)

If the project ships a React/TSX component directory, a bundled stdlib-only script lists its components so the wireframe reuses real names instead of inventing them:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/wireframe/scripts/extract_components.py [components-dir]
```

It defaults to `src/components`, takes any directory as an argument, and **fails open** — an absent directory just means "wireframe freehand," not an error (nautilai convention #8: stdlib-only, `${CLAUDE_PLUGIN_ROOT}`-rooted, fail-open).

## Convention notes

This is a **generative** skill, so two nautilai conventions are deliberately skipped:

- **Finding dispositions (#1)** — *not applicable.* The skill produces wireframes; it doesn't surface findings about the user's code, so there's nothing to classify as `auto-fix` / `report` / `ask-user`.
- **Shoals (#11)** — *deliberately skipped.* Wireframing is one-shot and stylistic; there's no recurring per-project judgment to carry between runs that an append-only hazard log would meaningfully capture. Per the convention's "poor fit" guidance, adopting it here would only add a dead empty-file read.

It does honor **stop-after-step (#9)** — it pauses for review before expanding a flow or exporting.

**Bundled scripts (#8)** is honored in part, with one deliberate exception. The convention asks for stdlib-only scripts that run on a clean machine with no install step. `extract_components.py` meets it fully. `mermaid-ascii.mjs` does not: it imports the third-party `beautiful-mermaid` package. The exception is deliberate — validating Mermaid requires a Mermaid parser, and reimplementing one in stdlib to satisfy the rule would be a worse tradeoff than an optional dependency that fails open. Both scripts are `${CLAUDE_PLUGIN_ROOT}`-rooted and both fail open, so a clean machine loses the preview and keeps everything else. Same posture the skill already takes with the un-bundled `wiremd` CLI.

## License

MIT
