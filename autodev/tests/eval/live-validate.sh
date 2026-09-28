#!/usr/bin/env bash
# Live eval for autodev planning (`--plan-only`'s model-driven part): given the
# auth-system fixture, does the planner produce the scenarios, quadrant
# placement, First-U choice, and test-review findings the fixture's expected
# output holds? Structural checks only (checks.tsv), never exact wording.
#
#   live-validate.sh [runs] [threshold]   # real `claude -p` calls (default 3, 0.8)
#   live-validate.sh --grade <output.md>  # grade one saved output, no model call
#
# Prints per-check results, then `soft=<passed/total>` and `hard=<0|1>`;
# hard=1 when every run's pass fraction reaches the threshold. Exit 1 when hard=0.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RULES="$HERE/../../skills/autodev/references/tdd.md"
INPUT="$HERE/fixtures/auth-system.input.json"
CHECKS="$HERE/checks.tsv"

# section <file> <name>: lines under "## <name>" up to the next "## " heading.
section() {
  awk -v want="## $2" '
    /^## / { on = ($0 == want); next }
    on { print }
  ' "$1"
}

# grade <file>: print per-check lines, then "<passed> <total>".
grade() {
  local passed=0 total=0 id sec re
  while IFS=$'\t' read -r id sec re; do
    [[ -z "$id" || "$id" == \#* ]] && continue
    total=$((total + 1))
    if section "$1" "$sec" | grep -qiE -- "$re"; then
      passed=$((passed + 1)); printf '  ok   %s\n' "$id"
    else
      printf '  FAIL %s\n' "$id"
    fi
  done < "$CHECKS"
  echo "$passed $total"
}

if [[ "${1:-}" == "--grade" ]]; then
  out="$(grade "${2:?output file required}")"
  printf '%s\n' "$out" | sed '$d'
  read -r p t <<< "$(printf '%s\n' "$out" | tail -1)"
  echo "soft=$p/$t"
  if [[ "$p" -eq "$t" ]]; then echo "hard=1"; exit 0; fi
  echo "hard=0"; exit 1
fi

RUNS="${1:-3}"
THRESHOLD="${2:-0.8}"
command -v claude >/dev/null 2>&1 || { echo "live-validate: claude CLI not found" >&2; exit 2; }

PROMPT="You are the autodev orchestrator planning one lane. Apply the TDD rules
in the system prompt to the feature below. Output markdown with exactly these
level-2 sections, in order:
## Scenarios — Given/When/Then scenarios, one per behavior, in slice order.
## Quadrant — one line per behavior, formatted '- Q<n>: <behavior>'.
## First-U — the first slice's behavior and why.
## Existing test review — findings for each existing test in the input.
Do not use tools. Feature:
$(cat "$INPUT")"

# Run outside the repo so project instructions and hooks cannot shape the output.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
all_ok=1; sum_p=0; sum_t=0
for i in $(seq 1 "$RUNS"); do
  echo "=== run $i ==="
  ( cd "$WORK" && claude -p --system-prompt "$(cat "$RULES")" "$PROMPT" ) > "$WORK/out-$i.md" 2>/dev/null
  out="$(grade "$WORK/out-$i.md")"
  printf '%s\n' "$out" | sed '$d'
  read -r p t <<< "$(printf '%s\n' "$out" | tail -1)"
  sum_p=$((sum_p + p)); sum_t=$((sum_t + t))
  if ! awk -v p="$p" -v t="$t" -v th="$THRESHOLD" 'BEGIN { exit !(t > 0 && p / t >= th) }'; then all_ok=0; fi
done
echo "soft=$sum_p/$sum_t"
echo "hard=$all_ok"
[[ "$all_ok" -eq 1 ]]
