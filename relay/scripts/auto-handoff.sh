#!/usr/bin/env bash
# Build an automatic handoff doc for a /clear that had no /handoff before it.
# Started detached by session-end-autohandoff.sh:
#   auto-handoff.sh <transcript> <handoff-dir> <generating-marker>
# Writes a fact-pack doc and the pending marker first, then rewrites the doc
# with the Haiku narrative. The early pending means a pickup that stops
# waiting still gets the fact pack, and no pending appears later to be
# claimed by an unrelated session. The -auto.md suffix selects the pickup
# prefix.
set -uo pipefail

transcript="$1"
marker_dir="$2"
generating="$3"
trap 'rm -f "$generating"' EXIT

here=$(dirname "$0")
doc="${marker_dir}/$(date +%Y%m%d-%H%M%S)-auto.md"

facts=$(bash "$here/extract-transcript.sh" "$transcript") || exit 0

write_doc() {
  {
    echo "# Auto handoff"
    echo
    echo "Written from the transcript at /clear; no agent reviewed it, so it has no Goal or Next steps."
    echo
    echo "## Narrative (unverified)"
    echo
    if [ -n "$1" ]; then
      printf '%s\n' "$1" | sed 's/^## /### /'
    else
      echo "_not available yet_"
    fi
    echo
    printf '%s\n' "$facts"
    echo "- writer: relay auto-handoff at /clear (no in-session writer)"
  } > "${doc}.tmp.$$" && mv -f "${doc}.tmp.$$" "$doc"
}

write_doc "" || exit 0
printf '%s\n' "$doc" > "${marker_dir}/pending.tmp.$$" \
  && mv -f "${marker_dir}/pending.tmp.$$" "${marker_dir}/pending"

if narrative=$(bash "$here/haiku-narrative.sh" "$transcript"); then
  write_doc "$narrative"
fi
