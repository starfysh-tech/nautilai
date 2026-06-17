# Changelog

All notable changes to CommitCraft are documented here. This project follows
[Semantic Versioning](https://semver.org) and [Keep a Changelog](https://keepachangelog.com).

## [2.0.0] - 2026-06-17

### Changed
- **Repackaged as a Claude Code plugin** distributed via the `nautilai` marketplace.
  Install with `/plugin marketplace add starfysh-tech/nautilai` and
  `/plugin install commitcraft@nautilai` instead of the previous `commitcraft-install.sh`
  global installer.
- All bundled script and workflow references now use `${CLAUDE_PLUGIN_ROOT}` rather than a
  hardcoded `~/.claude/skills/commitcraft/` path, so they resolve correctly from the plugin
  cache.
- `commitcraft-setup.sh` resolves its `templates/` directory relative to the script
  location.

### Removed
- `commitcraft-install.sh` — superseded by Claude Code's native `/plugin install`.

> Earlier history (v4.x → v5.x as a standalone skill) lived in the AppletScriptorium
> repository prior to the move.
