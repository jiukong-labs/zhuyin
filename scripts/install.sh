#!/bin/zsh

set -euo pipefail

script_directory="${0:A:h}"
repository_root="${script_directory:h}"
project_path="$repository_root/Jiukong Zhuyin.xcodeproj"
scheme_name="Jiukong Zhuyin"
build_configuration="${CONFIGURATION:-Release}"
build_architecture="$(uname -m)"
derived_data_path="${DERIVED_DATA_PATH:-$repository_root/.build/DerivedData}"
signing_identity="${SIGNING_IDENTITY:--}"
bundle_identifier="tw.idv.jiukong.zhuyin"
built_application="$derived_data_path/Build/Products/$build_configuration/Jiukong Zhuyin.app"
installation_directory="$HOME/Library/Input Methods"
installed_application="$installation_directory/Jiukong Zhuyin.app"
temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/jiukong-zhuyin-install.XXXXXX")"
staged_application="$temporary_root/Jiukong Zhuyin.app"

cleanup() {
    rm -rf "$temporary_root"
}
trap cleanup EXIT

xcodebuild \
    -quiet \
    -project "$project_path" \
    -scheme "$scheme_name" \
    -configuration "$build_configuration" \
    -destination "platform=macOS,arch=$build_architecture" \
    -derivedDataPath "$derived_data_path" \
    CODE_SIGN_IDENTITY="$signing_identity" \
    build

if [[ ! -d "$built_application" ]]; then
    print -u2 "error: Built application was not found at $built_application"
    exit 1
fi

built_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$built_application/Contents/Info.plist" 2>/dev/null || true)"
if [[ "$built_identifier" != "$bundle_identifier" ]]; then
    print -u2 "error: Refusing to install a build with bundle identifier '$built_identifier'."
    exit 1
fi

/usr/bin/codesign --verify --deep --strict "$built_application"
/usr/bin/ditto "$built_application" "$staged_application"
/bin/mkdir -p "$installation_directory"

if [[ -e "$installed_application" ]]; then
    existing_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$installed_application/Contents/Info.plist" 2>/dev/null || true)"
    if [[ "$existing_identifier" != "$bundle_identifier" ]]; then
        print -u2 "error: Refusing to replace $installed_application because its bundle identifier is '$existing_identifier'."
        exit 1
    fi
    /usr/bin/pkill -x "Jiukong Zhuyin" 2>/dev/null || true
    rm -rf "$installed_application"
fi

/bin/mv "$staged_application" "$installed_application"
/usr/bin/touch "$installation_directory"

print "Installed Jiukong Zhuyin at:"
print "  $installed_application"

# macOS keeps its input-source database per login session. A bundle identifier
# this session has never seen stays invisible to Text Input Sources until the
# next login, no matter how often it is registered, so the bundle is left in
# place and the user is told what the remaining step is.
if ! "$installed_application/Contents/MacOS/Jiukong Zhuyin" --register; then
    print ""
    print "The bundle is installed, but macOS did not register the input source."
    print "This is expected the first time a new bundle identifier is installed:"
    print "  $bundle_identifier"
    print "Log out and back in once, then run this installer again."
    exit 1
fi

print "macOS accepted the enable request but may require your approval."
print "Open System Settings > Keyboard > Text Input > Edit… and confirm 久空輸入法."
print "The installer did not select or switch your current input source."
