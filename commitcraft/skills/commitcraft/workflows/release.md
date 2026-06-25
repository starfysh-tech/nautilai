# Release Workflow

## Phase 1: Release-Please Gate (defer only when it actually works)

A *functional* release-please is **the** release path — never cut a manual tag
alongside it, or the version and CHANGELOG diverge. But a present
`release-please.yml` is too weak a signal: it can be scaffolded then neutered
(skip flags, no write permission, never advanced past `0.0.0`), and deferring to a
disabled release-please **dead-ends** — the release PR never arrives and the user
can't release at all. Detect the real state instead of just the file:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/commitcraft-release-detect-rp.sh
```

Parse the block between `RP_DETECT_START` and `RP_DETECT_END`:
- `RP_STATUS` — `FUNCTIONAL` | `DISABLED` | `ABSENT`
- `RP_REASON` — one line explaining the decision

- **`RP_STATUS: FUNCTIONAL`** → defer to release-please and **stop here** (do not run Phases 2-5):

  ```bash
  gh pr list --label "autorelease: pending" --json number,title,url --limit 5
  ```

  - PRs found → display via `AskUserQuestion` with options to review/merge the release PR. Merging it cuts the release.
  - No PRs → tell the user: "release-please manages releases here and nothing is pending. Push conventional commits to `main` and it will open a release PR." Stop.
  - **Only** proceed to Phase 2 if the user *explicitly* asks for a manual release despite a functional release-please (warn about divergence first).

- **`RP_STATUS: DISABLED`** → release-please is installed but neutered. **Fall back to the manual path** (continue to Phase 2). First tell the user one line citing the reason, so the fallback is transparent rather than silent:

  > release-please is present but disabled (`<RP_REASON>`) — using commitcraft's manual tag/release path. To restore automated releases, fix the workflow (or run `commitcraft setup --section release`).

- **`RP_STATUS: ABSENT`** → no automated path exists. Tell the user: "release-please not installed — using the manual tag/release path. Run `commitcraft setup --section release` to automate this." Continue to Phase 2.

## Phase 2: Run Analysis (manual path only)

> Phases 2-5 are the **manual release path** — reached only when release-please is
> absent (or the user explicitly overrode it in Phase 1).

Run the release analyzer:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/commitcraft-release-analyze.sh
```

Parse output between `RELEASE_ANALYZE_START` and `RELEASE_ANALYZE_END`.

Extract these key-value pairs:
- `CURRENT_VERSION` — latest prod tag
- `NEW_VERSION` — proposed next version
- `BUMP_TYPE` — major/minor/patch/none/initial
- `COMMIT_COUNT` — number of unreleased commits

Parse commits between `COMMITS_START` and `COMMITS_END`:
- Each line: `<short-hash><unit-separator><subject>`
- The unit separator is ASCII `\x1f` (invisible character between hash and subject)
- Parse conventional commit type from subject: `type(scope): description (#PR)`
- Extract: type, scope (optional), description, PR number (optional)

### If BUMP_TYPE is "none"

Inform the user:
```
Stage and prod are in sync at <CURRENT_VERSION>.
No unreleased commits found.
```
Stop here.

### If script exits with error

Display the error output to the user (not on main, dirty tree) and stop. Note: missing/unauthenticated `gh` is now a **warning**, not an error — the script reports `GH_AVAILABLE: false` and still computes the version. If `GH_AVAILABLE` is false, warn that publishing the GitHub release (Phase 5) will require `gh auth login` even though analysis succeeded.

## Phase 3: Generate Release Notes

Group parsed commits into sections by commit type.

**Prefer the repo's own section config.** If `release-please-config.json` exists, use
its `changelog-sections` as the type→section mapping — so the manual notes match what
release-please would produce. The repo declares its categories once and commitcraft
honors them whether or not release-please ever runs (no automation required):

```bash
test -f release-please-config.json && \
  jq -r '.packages["."]["changelog-sections"] // [] | .[]
         | "\(.type)\t\(.section)\t\(.hidden // false)"' release-please-config.json
```

- Each row is `type<TAB>section<TAB>hidden`. Use them in the config's order; a row
  with `hidden=true` means **omit** that type from the notes (release-please's
  convention).
- If there is no `release-please-config.json` (or it has no `changelog-sections`),
  fall back to the built-in defaults below.

**Built-in defaults (fallback only):**

| Commit Type | Section Name | Show by Default |
|-------------|-------------|-----------------|
| `feat` | Features | yes |
| `fix` | Bug Fixes | yes |
| `perf` | Performance | yes |
| `revert` | Reverts | yes |
| `docs` | Documentation | yes |
| `chore` | Other Changes | no |
| `refactor` | Other Changes | no |
| `test` | Other Changes | no |
| `build` | Other Changes | no |
| `ci` | Other Changes | no |
| `style` | Other Changes | no |

**Rules:**
- Omit empty sections entirely.
- Hidden types are left out. With the **built-in fallback**, all hidden types collapse
  into one optional **Other Changes** section, shown only if there are no visible
  sections at all. With **config `changelog-sections`**, follow the config literally:
  `hidden=true` types are simply omitted (no synthetic "Other Changes" bucket).
- If a commit type has `!` (e.g. `feat!:`), it's still categorized by its base type
  but noted as breaking.

**Format each entry as:**
```
- <scope>: <description> (#<PR>) (<hash>)
```
- If no scope: `- <description> (#<PR>) (<hash>)`
- If no PR number: `- <scope>: <description> (<hash>)`
- If neither: `- <description> (<hash>)`

## Phase 4: Present to User

Use `AskUserQuestion` to present the release summary:

```
## Release Summary

**<CURRENT_VERSION>** → **<NEW_VERSION>** (<BUMP_TYPE> bump)
**Commits:** <COMMIT_COUNT> on stage, not yet in prod

### Release Notes

<generated notes from Phase 3>
```

Options:
1. **Create release** — tag and create GitHub release with these notes
2. **Change version** — override the suggested version
3. **Edit notes** — modify release notes before creating
4. **Cancel** — abort release

### If user chooses "Change version"
Ask for the desired version. Validate it matches `vMAJOR.MINOR.PATCH` format.
Return to Phase 4 with the updated version.

### If user chooses "Edit notes"
Ask the user what changes they want to the release notes.
Apply changes and return to Phase 4 with updated notes.

## Phase 5: Create Release

After user approves, run pre-flight checks:

```bash
git fetch --tags
```

```bash
git tag -l <NEW_VERSION>
```

If the tag already exists, inform the user and ask how to proceed (abort or choose different version).

Create and push the tag:

```bash
git tag <NEW_VERSION>
git push origin <NEW_VERSION>
```

Create the GitHub release:

```bash
gh release create <NEW_VERSION> --title "<NEW_VERSION>" --notes "<release_notes>"
```

**If `gh release create` fails** after the tag was already pushed:
- Inform the user the tag `<NEW_VERSION>` exists on the remote
- Provide the manual retry command: `gh release create <NEW_VERSION> --notes "..."`
- Do NOT attempt to delete the pushed tag

**On success**, display:
```
Release <NEW_VERSION> created.
GitHub release: <URL from gh output>

To deploy to prod: trigger the deploy workflow from this tag.
```
