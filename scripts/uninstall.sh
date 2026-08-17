#!/bin/zsh

set -euo pipefail

bundle_identifier="tw.idv.jiukong.inputmethod.zhuyin"
installation_directory="$HOME/Library/Input Methods"
installed_application="$installation_directory/Jiukong Zhuyin.app"

if [[ ! -e "$installed_application" ]]; then
    print "Jiukong Zhuyin is not installed at $installed_application"
    exit 0
fi

existing_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$installed_application/Contents/Info.plist" 2>/dev/null || true)"
if [[ "$existing_identifier" != "$bundle_identifier" ]]; then
    print -u2 "error: Refusing to remove $installed_application because its bundle identifier is '$existing_identifier'."
    exit 1
fi

"$installed_application/Contents/MacOS/Jiukong Zhuyin" --disable
/usr/bin/pkill -x "Jiukong Zhuyin" 2>/dev/null || true
rm -rf "$installed_application"
/usr/bin/touch "$installation_directory"

print "Removed $installed_application"
print "If it remains visible in System Settings, sign out and back in to refresh the macOS input-source cache."
