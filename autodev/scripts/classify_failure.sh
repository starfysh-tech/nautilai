#!/usr/bin/env bash
# Classify a failure log: transient | environment | specification | implementation.
# Only "implementation" counts toward the lane's 3-failure cap, so environment
# patterns are kept deliberately narrow — a miss here means an uncounted retry.
set -euo pipefail
LOGFILE="${1:?log file required}"
text="$(cat "$LOGFILE" 2>/dev/null || true)"
shopt -s nocasematch
if [[ "$text" =~ (ECONNRESET|connect.*timed[[:space:]]out|ETIMEDOUT|request[[:space:]]timed[[:space:]]out|connection[[:space:]]timed[[:space:]]out|rate[[:space:]]limit|temporar|network[[:space:]]error) ]]; then
  echo transient
elif [[ "$text" =~ (No[[:space:]]verifier[[:space:]]found|missing[[:space:]]env|command[[:space:]]not[[:space:]]found|permission[[:space:]]denied|could[[:space:]]not[[:space:]]connect|database[[:space:]]is[[:space:]]not[[:space:]]running) ]]; then
  echo environment
elif [[ "$text" =~ (ambiguous|unclear|unknown[[:space:]]requirement|needs[[:space:]]decision|acceptance[[:space:]]criteria[[:space:]]unclear) ]]; then
  echo specification
else
  echo implementation
fi
