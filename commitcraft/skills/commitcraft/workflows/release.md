# Release Workflow

## Phase 1: Release-Please Gate (the single path when installed)

When release-please is installed, it is **the** release path — never cut a manual
tag alongside it, or the version and CHANGELOG diverge. Detect it first:

```bash
test -f .github/workflows/release-please.yml && echo "RP_INSTALLED" || echo "RP_ABSENT"
```

- **`RP_INSTALLED`** → defer to release-please and **stop here** (do not run Phases 2-5):

  ```bash
  gh pr list --label "autorelease: pending" --json number,title,url --limit 5
  ```

  - PRs found → display via `AskUserQuestion` with options to review/merge the release PR. Merging it cuts the release.
  - No PRs → tell the user: "release-please manages releases here and nothing is pending. Push conventional commits to `main` and it will open a release PR." Stop.
  - **Only** proceed to Phase 2 if the user *explicitly* asks for a manual release despite release-please being installed (warn about divergence first).

- **`RP_ABSENT`** → no automated path exists. Tell the user: "release-please not installed — using the manual tag/release path. Run `commitcraft setup --section release` to automate this." Continue to Phase 2.

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

Group parsed commits by type into sections. Order matters:

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
- Only show "Other Changes" section if there are NO visible sections (all commits are hidden types)
- Omit empty sections entirely
- If a commit type has `!` (e.g., `feat!:`), it's still categorized by its base type but noted as breaking

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
