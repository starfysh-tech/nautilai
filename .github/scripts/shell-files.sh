#!/usr/bin/env bash
# Print every tracked shell script, NUL-separated, for `xargs -0 shellcheck`.
#
# A shell script is a tracked file that either ends in `.sh`, or has no
# extension (no `.` in its name after a leading dot, so `.hidden` counts and
# `notes.txt` doesn't) and a shebang whose interpreter is `sh` or `bash` —
# directly (`#!/bin/bash`) or via env (`#!/usr/bin/env [-S] [NAME=val...] bash`).
# Paths are printed as `./<path>` so a name starting with `-` is never read as
# an option. Prints nothing (and succeeds) when there are no matches.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

# Interpreter basename named by a file's shebang; empty if there is none.
shebang_interpreter() {
  local line=""
  IFS= read -r line < "$1" || true
  case "$line" in '#!'*) ;; *) return 0 ;; esac
  local -a words
  read -r -a words <<<"${line#\#!}"
  [ "${#words[@]}" -gt 0 ] || return 0
  local prog="${words[0]##*/}" i=1
  if [ "$prog" = env ]; then
    while [ "$i" -lt "${#words[@]}" ]; do
      case "${words[$i]}" in
        -*|*=*) i=$((i + 1)) ;;
        *) break ;;
      esac
    done
    prog=""
    if [ "$i" -lt "${#words[@]}" ]; then prog="${words[$i]##*/}"; fi
  fi
  printf '%s' "$prog"
}

while IFS= read -r -d '' f; do
  name="${f##*/}"
  case "$name" in
    *.sh) printf './%s\0' "$f"; continue ;;
  esac
  case "${name#.}" in *.*) continue ;; esac
  [ -f "$f" ] && [ ! -L "$f" ] || continue
  case "$(shebang_interpreter "$f")" in
    sh|bash) printf './%s\0' "$f" ;;
  esac
done < <(git ls-files -z)
