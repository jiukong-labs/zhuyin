#!/bin/zsh

# Builds and runs the installed-input-method acceptance harness.
#
# The harness drives the *installed* bundle, so run ./scripts/install.sh first
# when the working tree has changed. It needs Accessibility and event-posting
# permission for the calling terminal, which is why it is not part of CI.
#
# Usage: run-acceptance.sh [script ...]        (default: every script)

set -euo pipefail

script_directory="${0:A:h}"
repository_root="${script_directory:h}"
derived_data_path="${JIUKONG_ACCEPTANCE_DERIVED_DATA_PATH:-${repository_root}/.build/AcceptanceHarness}"

xcodebuild \
  -quiet \
  -project "${repository_root}/Jiukong Zhuyin.xcodeproj" \
  -scheme "Jiukong Acceptance Harness" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "${derived_data_path}" \
  build

harness="${derived_data_path}/Build/Products/Release/JiukongAcceptanceHarness"
if [[ ! -x "${harness}" ]]; then
  print -u2 "Acceptance harness was not produced at ${harness}"
  exit 1
fi

"${script_directory}/check-acceptance-matrix.sh" "${harness}"

# Building anything registers another copy of the bundle identifier under
# .build, which can silently take the input source away from the installed
# bundle. Re-assert it before driving the input method.
"${script_directory}/register-input-source.sh" > /dev/null

typeset -a requested
if (( $# > 0 )); then
  requested=("$@")
else
  while IFS= read -r name; do
    requested+=("${name}")
  done < <("${harness}" --list-default)
fi

typeset -i failures=0
for name in "${requested[@]}"; do
  # Each run uses a fresh client and reselects Jiukong. Keep the registered
  # service running; repeatedly killing it races InputMethodKit reconnection.
  if output="$("${harness}" "${name}")"; then
    print -r -- "${output}"
    continue
  fi
  print -r -- "${output}"

  # An unconnected client has not executed the scenario. Retry setup once
  # with a new isolated client; never retry a behavior mismatch or lost focus.
  if [[ "${output}" == *'aborted: this client never routed keys through the input method'* ]]; then
    print "Retrying connection setup once for ${name}."
    sleep 1
    if output="$("${harness}" "${name}")"; then
      print -r -- "${output}"
      continue
    fi
    print -r -- "${output}"
  fi
  (( failures += 1 ))
done

if (( failures > 0 )); then
  print -u2 "${failures} acceptance script(s) failed."
  exit 1
fi

print "All ${#requested} acceptance scripts passed."
