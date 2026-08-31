#!/bin/zsh

set -euo pipefail

script_directory="${0:A:h}"
repository_root="${script_directory:h}"
project_path="$repository_root/Jiukong Zhuyin.xcodeproj"
scheme_name="Jiukong Zhuyin"
build_configuration="${CONFIGURATION:-Release}"
build_architecture="$(uname -m)"
signing_identity="${SIGNING_IDENTITY:--}"
bundle_identifier="tw.idv.jiukong.inputmethod.zhuyin"
temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/jiukong-zhuyin-install.XXXXXX")"
# A cloud-synced repository can attach Finder metadata to products under its
# .build directory before Xcode signs them. Keep installation products in the
# local temporary volume so the app reaches codesign without those attributes.
derived_data_path="${DERIVED_DATA_PATH:-$temporary_root/DerivedData}"
built_application="$derived_data_path/Build/Products/$build_configuration/Jiukong Zhuyin.app"
installation_directory="$HOME/Library/Input Methods"
installed_application="$installation_directory/Jiukong Zhuyin.app"
system_application="/Library/Input Methods/Jiukong Zhuyin.app"
staged_application="$temporary_root/Jiukong Zhuyin.app"

cleanup() {
    rm -rf "$temporary_root"
}
trap cleanup EXIT

# A public package installs the production bundle for every user, while this
# development helper installs an ad-hoc copy for only the current user. macOS
# cannot reliably resolve two apps with the same input-method bundle ID: the
# user copy can shadow the signed system copy and leave a visible but
# unlaunchable input source after a test run. Refuse before building or
# changing LaunchServices so a maintainer's everyday installation stays intact.
if [[ -d "$system_application" ]]; then
    system_identifier="$(
        /usr/libexec/PlistBuddy \
            -c 'Print :CFBundleIdentifier' \
            "$system_application/Contents/Info.plist" \
            2>/dev/null || true
    )"
    if [[ "$system_identifier" == "$bundle_identifier" ]]; then
        print -u2 "error: A public Jiukong installation already exists at:"
        print -u2 "  $system_application"
        print -u2 "Refusing to install a second copy with the same bundle identifier."
        print -u2 "Use a dedicated test account/Mac, or remove the public installation first."
        exit 1
    fi
fi

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
if ! "$script_directory/register-input-source.sh"; then
    print ""
    print "The bundle is installed, but macOS did not register the input source."
    print "Identifier: $bundle_identifier"
    print ""
    print "Two causes make this fail silently:"
    print "  1. The identifier must contain an 'inputmethod' component that is"
    print "     not the last one, or Text Input Sources ignores the bundle."
    print "  2. Another bundle with the same identifier — a build product under"
    print "     .build, or a deleted bundle whose LaunchServices record"
    print "     survives — has taken the identifier over. Re-register this one:"
    print "       lsregister -f -R -trusted \"$installed_application\""
    exit 1
fi

print "macOS accepted the enable request but may require your approval."
print "Open System Settings > Keyboard > Text Input > Edit… and confirm 久空輸入法."
print "The installer did not select or switch your current input source."
