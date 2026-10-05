#!/usr/bin/env bash
# Every skill that uses the CLAUDE_PLUGIN_ROOT variable must carry the omp/pi
# adapter line verbatim (docs/conventions/dual-runtime.md, rule 9). omp and pi
# never expand the variable in skill text, so without the line those runtimes
# hand the agent a broken path. Fails on a missing or edited copy.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

note='> **omp / pi:** these runtimes don'"'"'t expand the `CLAUDE_PLUGIN_ROOT` variable. Wherever it appears unexpanded — in this file or in any file it sends you to — replace it with the plugin root: the parent of this skill'"'"'s `skills/` directory. This is the one path substitution you may make yourself. It does not apply under Hermes, which installs only the skill folder.'

fail=0 checked=0
while IFS= read -r -d '' f; do
  # Plugin skills only: <plugin>/skills/<skill>/SKILL.md, where <plugin> is a
  # top-level plugin dir (repo-local .claude/skills are not shipped plugins).
  case "$f" in .*) continue ;; */*/*/*/*) continue ;; */skills/*/SKILL.md) ;; *) continue ;; esac
  [ -f "${f%%/*}/.claude-plugin/plugin.json" ] || continue
  grep -qF '${CLAUDE_PLUGIN_ROOT}' "$f" || continue
  checked=$((checked + 1))
  if ! grep -qxF "$note" "$f"; then
    echo "MISSING: $f uses \${CLAUDE_PLUGIN_ROOT} but lacks the exact omp/pi adapter line" >&2
    fail=1
  fi
done < <(git ls-files -z -- '*/SKILL.md')

[ "$fail" -eq 0 ] || { echo "See docs/conventions/dual-runtime.md, rule 9." >&2; exit 1; }
echo "OK: $checked skill(s) using CLAUDE_PLUGIN_ROOT carry the omp/pi adapter line"
