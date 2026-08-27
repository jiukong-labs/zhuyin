#!/bin/zsh

# Runs the repository checks and the real installed-input-method regression
# matrix required before a release. Install the exact working build and grant
# the calling terminal Accessibility permission before invoking this script.

set -euo pipefail

script_directory="${0:A:h}"
repository_root="${script_directory:h}"
temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/jiukong-release-preflight.XXXXXX")"

cleanup() {
  rm -rf "${temporary_root}"
}
trap cleanup EXIT

cd "${repository_root}"

git diff --check
"${script_directory}/check-project-sources.sh"
zsh -n "${script_directory}/package-release.sh"
zsh -n "${script_directory}/run-acceptance.sh"
zsh -n "${script_directory}/check-acceptance-matrix.sh"

xcodebuild \
  -quiet \
  -project "${repository_root}/Jiukong Zhuyin.xcodeproj" \
  -scheme "Jiukong Zhuyin" \
  -configuration Debug \
  -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath "${temporary_root}/Tests" \
  CODE_SIGN_ENTITLEMENTS= \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM= \
  test

JIUKONG_ACCEPTANCE_DERIVED_DATA_PATH="${temporary_root}/AcceptanceHarness" \
  "${script_directory}/run-acceptance.sh"

print "Release preflight passed: unit tests and installed behavior matrix."
