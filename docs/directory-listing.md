# List a plugin in Anthropic's directory

How to submit one nautilai plugin to the directory at
[claude.ai/directory](https://claude.ai/directory). commitcraft was the first
plugin listed (submitted 2026-10-04). Use these steps for the next one.

Anthropic's docs: [Submit your plugin](https://claude.com/docs/plugins/submit),
[Pre-submission checklist](https://claude.com/docs/plugins/pre-submission-checklist),
[Feature support by surface](https://claude.com/docs/plugins/platform-support).

## Before you start

- Submit from Randall's personal claude.ai account. The Starfysh claude.ai org is
  not on a paid plan and cannot submit.
- The account that submits a plugin folder first owns that listing. Moving it
  later needs an email to `directory@anthropic.com`.
- Your GitHub account must be connected on claude.ai and must have push access to
  `starfysh-tech/nautilai`.
- Each plugin folder is a separate submission. The portal allows 10 submissions
  per 24 hours.

## 1. Check the plugin locally

```bash
claude plugin validate ./<plugin> --strict
```

Also confirm these portal rules, which the command does not check:

- `README.md` in the plugin folder has 40 or more words outside code blocks.
- `plugin.json` sets `license`, `author`, `description`, and `version`.
- No symlinks, `.DS_Store`, or binary files other than images and fonts.
- Every non-image file is under 256 KiB. The plugin has 512 files or fewer.

## 2. Add the icon

The portal locks the icon the first time you save or submit. **Merge the icon to
`main` before you use the portal for this plugin.**

- Path: `<plugin>/.claude-plugin/icon.png`.
- Square PNG, 512 to 2048 px, under 2 MB. SVG and WebP are not accepted.
- commitcraft's icon uses the docs site colors: background `#0a141d`, cyan
  `#5ec8d4`, amber `#f2a541`. To render a PNG from an SVG:

  ```bash
  rsvg-convert -w 1024 -h 1024 icon.svg -o <plugin>/.claude-plugin/icon.png
  ```

  Do not commit the SVG.

## 3. Update the privacy page

[`docs/privacy.html`](privacy.html) is the privacy page for every listing.

- Check that the plugin's row in the table is still true: what it sends, what it
  saves outside the project, and what it does for the user. Read the plugin's
  `SKILL.md`, README, and scripts to confirm.
- Change the "Last updated" date if you change the page.
- Add this section at the end of the plugin's `README.md`:

  ```markdown
  ## Privacy

  <Plugin> runs on your machine and sends nothing to Starfysh. See the
  [privacy page](https://starfysh-tech.github.io/nautilai/privacy.html) for what it
  reads, stores, and sends.
  ```

Merge, then confirm the page loads at
https://starfysh-tech.github.io/nautilai/privacy.html.

## 4. Validate in the portal

1. Open [claude.ai/directory/manage](https://claude.ai/directory/manage) and select
   **Submit new**, then **Plugin bundle**.
2. Enter:
   - **Repository:** `starfysh-tech/nautilai`
   - **Plugin path:** `<plugin>`
   - **Branch or tag:** leave empty, so the directory follows `main`.
3. Select **Validate**.
4. Fix every finding marked **Blocking**, merge the fix, and select
   **Re-validate**.

Findings we saw on commitcraft:

| Finding | Result | What we did |
|---|---|---|
| `ALLOWED_TOOLS_BROAD` (`allowed-tools` has bare `Bash`) | Policy hold | Left it for the reviewer |
| `ALLOWED_TOOLS_UNSCOPED_WRITE` (bare `Write`, `Edit`) | Policy hold | Left it for the reviewer |
| `MCP_FORWARDS_CREDENTIAL_ENV` (README SSH key example, `has_gpg_keys` in a script) | Policy hold | False positive. Left it for the reviewer |
| `ICON_MISSING` | Warning | Added the icon (step 2) |
| No privacy policy URL | Warning | Added the privacy page (step 3) |
| `ASSETS_PASSED_UNREAD` (the icon) | Note | None |

A policy hold does not block the submit. A reviewer must clear it before the
version goes live.

## 5. Fill in the form

- **Listing details:** the portal reads these from `plugin.json` and the README.
  To change them, change the files, merge, and re-validate.
- **Data handling:** take the answers from the plugin's row in the privacy page.
  commitcraft's answers were:
  - Personal data: **Reads only** (it reads `git config user.email`)
  - Data sent to other services: **Yes — listed in README**
  - Retention: **Not retained**
  - Under 18: **No**
- **Compliance:** check the contact email and select all 4 acknowledgements.
- **Review and submit:** keep **GitHub push webhook** and select **Submit for
  review**. Then select **Set up push updates**. This needs admin access to the
  repository.

## 6. After the listing goes live

- Add the directory as an install path to `docs/llms.txt` and
  `docs/plugins/<plugin>.html`, and add an entry to `docs/plugin-changelog.md`.
- Each release-please release bumps the version of every plugin. The directory
  scans each new version. By default, you select **Publish** for each version and
  a reviewer publishes it.
- The portal's **Usage** tab shows installs, versions, skill runs, and error rates.

## Known issues for other plugins

- **Plugin names:** the portal holds names made only of common words, such as
  `dep-review` or `wireframe`. It may hold `cc-*` names because they look like
  "Claude Code". Run **Validate** before you decide to rename a plugin. A rename
  changes all five identity surfaces in `CLAUDE.md` and breaks current installs.
- **Hooks:** the portal holds hook scripts in a subfolder plugin that it cannot
  follow. relay's hooks call other scripts. phi-scan's hook runs `python3`.
- **relay:** sends transcript text to Claude Haiku. Its README must say this.
  A first submission that fails the security scan is rejected.
- **dep-review:** merges low-risk Dependabot PRs without asking. The privacy page
  states this.
- **Surfaces:** the portal lists a skill-only plugin for Chat and Cowork. Most of
  our skills need git, `gh`, and a local repo, so they do not work there. Test with
  **Customize > Plugins > Add > Upload plugin** before you submit.
