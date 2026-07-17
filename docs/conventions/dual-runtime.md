# Dual-runtime plugins (Claude Code + Hermes Agent)

Five nautilai skills run in **both** Claude Code and Hermes Agent from this one repo.
This is the rule set for keeping that true, and the lessons that produced it.

**Claude Code is the primary runtime. Hermes support is additive and must stay that way.**
A Claude regression is never an acceptable price for Hermes support — and it is never
necessary, because every constraint below has a Hermes-only solution.

> The design record and per-assumption validation live in
> [`docs/plans/hermes-dual-runtime.md`](../plans/hermes-dual-runtime.md). This file is the
> rule set. The **step-by-step porting how-to** (docs-site page) is
> [`docs/hermes-porting.html`](../hermes-porting.html). The agent-facing summary is
> [`docs/llms.txt`](../llms.txt).

---

## The rules

### 1. Never change a Claude-facing file to support Hermes

Prove it, don't assert it. The PR diff must show **no changes** under `<plugin>/scripts/**`,
`<plugin>/templates/**`, `<plugin>/tests/**`, or any `.claude-plugin/**`. The only permitted
edit to a Claude-loaded file is an **additive** "Resource paths" section in `SKILL.md`.

### 2. Bundled resources are mirrored into the skill dir, not moved

Hermes installs the **skill directory and nothing else**. A plugin's root-level `scripts/`
and `templates/` never reach it.

`hermes/sync-resources.sh` copies them into `<plugin>/skills/<skill>/`. The plugin-root copies
stay the source of truth and are what Claude uses; the mirror is **generated**, inert to Claude,
and gated by `hermes/sync-resources.sh --check` in CI. Never hand-edit the mirror.

Duplication is the deliberate price of rule 1. Relocating the originals would have rewritten
19 path references across six workflow files plus two test suites — real regression surface on
the runtime that already has users.

### 3. One SKILL.md, one adapter section

```markdown
## Resource paths

- **Claude Code:** `${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh`
- **Hermes:** `bash ${HERMES_SKILL_DIR}/scripts/<name>.sh`
```

Each runtime substitutes **only its own** token and leaves the other as literal text, so the
line that resolved to an absolute path is the one to follow. This is self-disambiguating —
there is nothing for the model to guess.

Instruct the agent to **never substitute a token itself and never fall back to a relative
path**. A model that "helpfully" repairs a path converts a real failure into a silent wrong
answer.

### 4. Invoke bundled scripts via `bash` on the Hermes line

**Hermes strips the executable bit on install** — a file committed `100755` lands `644`, and a
direct call returns `Permission denied`. Keep Claude's direct invocation; add `bash` only on
the Hermes line.

### 5. Workflow files stay Claude-native; the adapter states the translation

Workflow files under `skills/<skill>/workflows/` are never edited (rule 1), so they name only
the Claude path. The adapter section carries the rule that rescues them under Hermes:

> everywhere a workflow says `${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh`,
> run `bash ${HERMES_SKILL_DIR}/scripts/<name>.sh`

This is safe because it is **the same mechanism Claude already relies on** — see lesson 3.

### 6. A script that provisions tooling cannot ship to Hermes

Hermes **security-scans every installed skill**, and for a community source *any* CAUTION
verdict is `BLOCKED`. A script that runs `npm install` / `pip install`, or reads `~/.ssh/`,
scores MEDIUM `supply_chain` and HIGH `exfiltration` — and blocks the **whole bundle**, not
just itself.

commitcraft hit exactly this: 12 findings, all from `commitcraft-setup.sh` and the templates
it installs. So `sync-resources.sh` carries an `EXCLUDE` list, and `setup` + `check` are
**Claude-only**. Hermes users configure a repo by following documented steps instead.

- *Rule:* keep provisioning logic in **one** script, so it can be excluded cleanly without
  taking working functionality with it. A `setup` script that also holds read-only `check`
  logic drags `check` down with it — as ours does.
- *Rule:* **never tell users to `--force` past the scanner.** The findings are usually correct.
  Ship a bundle that passes; document the rest.
- *Rule:* when a workflow is excluded, the `SKILL.md` adapter must say so explicitly and tell
  the agent **not to improvise an equivalent** — an agent asked to "set up commitlint" with no
  script will happily start installing packages itself.
- *Rule:* **`SKILL.md` carries instructions, not rationale.** It is shipped *and scanned*, so
  prose explaining why a script was excluded can re-trigger the very findings that excluded it —
  a static scanner matches patterns, not intent. State what the agent should do; put the why in
  the README and here. (We shipped exactly this bug: the sentence describing the blocked script
  quoted the package-install commands and key path verbatim.)
- *Rule:* **Never quote an attack string in a shipped file — describe it.** A static scanner cannot
  tell a defense from an exploit. `pr-comment-review` was hard-blocked (`Verdict: DANGEROUS`,
  `CRITICAL injection`) because its **prompt-injection defense** quoted the canonical
  override-instruction phrase as an example. A `DANGEROUS` verdict **cannot be bypassed even with
  `--force`**, so this is fatal, not cosmetic. Name the *category* of directive to refuse; never
  spell the payload. The same applies to security-audit checklists that enumerate what to look for.

### 7. A plugin that needs subagents is Claude-only

Hermes has no subagent primitive. `autodev` is not ported: its value *is* subagent fan-out plus
git-worktree isolation, so a port would be a hollow shell. Skills that fan out for review
(`review-plan`, `dep-review`, `pr-comment-review`) already document an inline fallback — that
documented path *is* their Hermes behavior. Say so in the README rather than inventing new prose.

### 8. Document the five headings, and the limits

Every dual-runtime plugin's README states: shared behavior · Claude Code invocation · Hermes
invocation · runtime-specific limitations · update behavior. Add the plugin to
[`docs/llms.txt`](../llms.txt) with the runtimes it supports.

---

## Lessons

### 1. The published Hermes docs are not reliable. Verify against the binary.

Multiple documented claims did not hold on Hermes v0.18.2:

| Doc claim | Reality |
| --- | --- |
| `hermes skills tap add <repo>` indexes a GitHub repo | Registers a row and indexes **nothing**; the `github` source is permanently skipped as "slow" |
| Taps persist in `~/.hermes/.hub/taps.json` | That file does not exist |
| `version`, `author`, `license` are **required** frontmatter | Not enforced — a skill without them installs fine |
| Skills are discovered flatly under a `skills/` root | **skills.sh indexes by skill name at any depth** — no `skills/` dir needed, no tap needed |

The last one mattered most: it deleted an entire planned architecture (a generated repo-root
bundle, a CI drift gate, and a release-please fan-out) that existed only to satisfy a
requirement that was never real.

**Treat vendor docs as a hypothesis, not a specification.**

### 2. Probe with a throwaway repo, never with the real one

Every surprise above surfaced in a scratch repo shaped like commitcraft, not in nautilai. Two
properties made the probes trustworthy, and both are worth copying:

- **Controls.** A non-executable file sitting beside the executable one is what turned "the exec
  bit was stripped" from a shrug into a finding. Without the control it reads as coincidence.
- **Observable identity.** The probe script printed *which copy of itself ran*. A script that
  "worked" from the wrong copy would otherwise look exactly like a pass.

Design probes so **PASS and FAIL produce different observable output**, and so a *false* pass is
impossible. If an agent can rescue a broken path by being resourceful, the probe measures the
agent's resourcefulness, not the thing under test.

### 3. `${CLAUDE_PLUGIN_ROOT}` was never a shell variable

It is **not** exported to Bash, and it is **not** substituted inside workflow files — the Read
tool returns the literal token. Running it verbatim yields `/scripts/foo.sh` and exit 127.

Claude resolves it **from context**, using the plugin root it learns in the SKILL.md header.
CommitCraft has always depended on this. That is why rule 5 is safe: the Hermes adapter leans on
an existing mechanism rather than introducing a new class of fragility.

### 4. A rate-limited or truncated result is not a finding

An unauthenticated GitHub API limit (60/hr) blew out mid-run and produced "not found" errors
that read exactly like real negatives — nearly costing us a correct architecture. Separately, a
`browse` command paginated across 2,559 pages was read as "not listed" after page one.

**Authenticate first; confirm the limit reads 5000.** Prefer `UNCLEAR` to a confident wrong
answer, and re-run anything that failed while the environment was degraded.

### 5. A probe that is *smaller* than the real thing will pass when the real thing fails

The security-scanner probe (`probe-hooks`) wrote git hooks, mutated git config, ran an
`npm install`, and made a network call. It returned **SAFE**. On that basis the scanner was
recorded as a cleared risk.

The real `commitcraft-setup.sh` returned **CAUTION → BLOCKED**: 12 findings, including two HIGH
`exfiltration` hits the probe had no analogue for (`~/.ssh/*.pub` reads for commit signing).
A ~30-line probe and a ~1,500-line provisioning script are not the same test subject, and
"close analogue" was doing far too much work.

**A probe proves a mechanism, not a payload.** Where the payload itself is what gets judged —
a scanner, a linter, a size limit — probe with the *real artifact* or accept that the risk is
still open. Saying "verified" here would have shipped docs that told users to run a command
that fails.

### 6. Publishing a public repo is publishing

skills.sh **auto-indexes any public GitHub repo containing a `SKILL.md`** — no tap, no opt-in,
no way to hide. Every skill in this marketplace is Hermes-resolvable, not just the five
supported ones, and `docs/llms.txt` says so plainly. The throwaway probe repo was also, briefly,
a publicly installable Hermes skill.

There is no opt-out mechanism. The only levers are: support it, document it as unsupported, or
remove it from the repo.
