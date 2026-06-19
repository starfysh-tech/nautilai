#!/usr/bin/env bash

# Hooks validator for Claude Code.
# Checks .claude/settings.json (project) and ~/.claude/settings.json (user)
# for hook schema/structure errors.
#
# NOTE: intentionally NO `set -e`. This script does explicit error handling and
# accumulates an exit code from the core validator; `set -e` would abort early
# on the first `((ERRORS++))` that evaluates to 0 (returns 1) or on `return 1`.
set -uo pipefail

FIX_MODE=False
if [[ "${1:-}" == "--fix" ]]; then
  FIX_MODE=True
fi

ERRORS=0
WARNINGS=0
FOUND_ANY=False

# Resolve the script directory. Prefer the plugin root when invoked as a plugin.
if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
  SCRIPT_DIR="${CLAUDE_PLUGIN_ROOT}/scripts"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# Locate a Python interpreter.
PYTHON="$(command -v python3 || command -v python || true)"
[[ -z "$PYTHON" ]] && { echo "ERROR: python3 (or python) not found in PATH"; exit 2; }

validate_json() {
  local file="$1"
  local label="$2"

  if [[ ! -f "$file" ]]; then
    return 0
  fi

  FOUND_ANY=True
  echo "Validating $label: $file"

  # Check JSON syntax first.
  if ! "$PYTHON" -c "import json,sys; json.load(open(sys.argv[1]))" "$file" 2>/dev/null; then
    echo "ERROR: Invalid JSON syntax in $file"
    ERRORS=$((ERRORS + 1))
    return 0
  fi

  # Validate hook structure via the core script.
  local output exit_code
  output=$("$PYTHON" "$SCRIPT_DIR/validate-hooks-core.py" "$file" "$FIX_MODE")
  exit_code=$?

  # Extract the warning count from the sentinel line.
  local warn_count
  warn_count=$(echo "$output" | grep "^__WARNINGS__:" | cut -d: -f2 || echo "0")

  # Display everything except the sentinel line.
  echo "$output" | grep -v "^__WARNINGS__:" || true

  if [[ -n "$warn_count" ]] && [[ "$warn_count" != "0" ]]; then
    WARNINGS=$((WARNINGS + warn_count))
  fi

  if [[ "$exit_code" -ne 0 ]]; then
    ERRORS=$((ERRORS + exit_code))
  fi

  echo ""
}

# Validate project then user settings.
validate_json ".claude/settings.json" "Project settings"
validate_json "$HOME/.claude/settings.json" "User settings"

# Summary.
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ "$FOUND_ANY" == "False" ]]; then
  echo "No settings.json found (project or user) — nothing to validate."
  exit 0
elif [[ $ERRORS -eq 0 ]] && [[ $WARNINGS -eq 0 ]]; then
  echo "All hooks are valid!"
  exit 0
elif [[ $ERRORS -eq 0 ]]; then
  echo "Validation completed with $WARNINGS warning(s)"
  exit 0
else
  echo "Validation failed with $ERRORS error(s)"
  if [[ "$FIX_MODE" == "False" ]]; then
    echo ""
    echo "Run '/cc-validate-hooks --fix' to attempt automatic fixes"
  fi
  exit 1
fi
