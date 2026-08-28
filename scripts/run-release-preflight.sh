#!/bin/zsh

# Runs the repository checks and the real installed-input-method regression
# matrix required before a release. Install the exact working build and grant
# the calling terminal Accessibility permission before invoking this script.

set -euo pipefail

script_directory="${0:A:h}"
repository_root="${script_directory:h}"
temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/jiukong-release-preflight.XXXXXX")"
preferences_domain="tw.idv.jiukong.inputmethod.zhuyin"
user_data_root="${HOME}/Library/Application Support/JiukongZhuyin"
user_data_backup="${temporary_root}/JiukongZhuyin.user-data-backup"
preferences_backup="${temporary_root}/preferences.plist"
had_user_data=0
had_preferences=0

cleanup() {
  /usr/bin/pkill -x "Jiukong Zhuyin" 2>/dev/null || true

  if (( had_user_data )); then
    rm -rf "${user_data_root}"
    mv "${user_data_backup}" "${user_data_root}"
  else
    rm -rf "${user_data_root}"
  fi

  if (( had_preferences )); then
    /usr/bin/defaults import "${preferences_domain}" \
      "${preferences_backup}" > /dev/null
  else
    /usr/bin/defaults delete "${preferences_domain}" 2>/dev/null || true
  fi

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

# The installed behavior matrix must exercise the shipped ranking and
# preference defaults, not the developer's accumulated learning history. Keep
# the real data recoverable throughout the run, disable CloudKit while the
# isolated database is active, and restore everything through the EXIT trap.
/usr/bin/pkill -x "Jiukong Zhuyin" 2>/dev/null || true
sleep 1

if /usr/bin/defaults export "${preferences_domain}" \
  "${preferences_backup}" > /dev/null 2>&1; then
  had_preferences=1
fi

if [[ -L "${user_data_root}" ]]; then
  print -u2 "Refusing to isolate a symbolic-link user data directory: ${user_data_root}"
  exit 1
fi
if [[ -e "${user_data_root}" ]]; then
  [[ -d "${user_data_root}" ]] || {
    print -u2 "User data path is not a directory: ${user_data_root}"
    exit 1
  }
  mv "${user_data_root}" "${user_data_backup}"
  had_user_data=1
fi

/usr/bin/defaults write "${preferences_domain}" \
  JiukongPreferencesVersion -int 1
/usr/bin/defaults write "${preferences_domain}" \
  JiukongShiftLanguageToggle -string both
/usr/bin/defaults write "${preferences_domain}" \
  JiukongAutomaticLearningEnabled -bool true
/usr/bin/defaults write "${preferences_domain}" \
  JiukongICloudSyncEnabled -bool false
/usr/bin/defaults write "${preferences_domain}" \
  JiukongKeyboardArrangement -string standard

JIUKONG_ACCEPTANCE_DERIVED_DATA_PATH="${temporary_root}/AcceptanceHarness" \
  "${script_directory}/run-acceptance.sh"

print "Release preflight passed: unit tests and installed behavior matrix."
