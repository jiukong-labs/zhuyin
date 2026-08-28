#!/bin/zsh

# Verifies that the installed-acceptance harness still carries every
# release-blocking keyboard behavior. This check can run in CI without
# Accessibility permission because it only reads the harness manifest.

set -euo pipefail

if (( $# != 1 )); then
  print -u2 "usage: check-acceptance-matrix.sh <acceptance-harness>"
  exit 2
fi

harness="$1"
if [[ ! -x "${harness}" ]]; then
  print -u2 "Acceptance harness is not executable: ${harness}"
  exit 1
fi

typeset -a required=(
  single
  number-one
  continuous
  option-ascii
  option-after-composition
  shift-round-trip
  builtin-phrase
  sentence
  revision-arrows
  revision-backspace
  revision-forward-delete
  escape
  punctuation
  punctuation-caret
  brackets
  phrase
  phrase-right
)

typeset -A available
while IFS= read -r name; do
  [[ -n "${name}" ]] && available[$name]=1
done < <("${harness}" --list-default)

typeset -i failures=0
for name in "${required[@]}"; do
  if [[ -z "${available[$name]-}" ]]; then
    print -u2 "Missing release-blocking acceptance script: ${name}"
    (( failures += 1 ))
  fi
done

if (( failures > 0 )); then
  exit 1
fi

print "Acceptance matrix contains all ${#required} release-blocking scripts."
