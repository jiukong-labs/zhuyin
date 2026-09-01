#!/bin/zsh

# Re-asserts the installed bundle as the owner of its identifier.
#
# Every build registers another copy of the same bundle identifier under
# .build, and LaunchServices then resolves the identifier to that copy instead
# of the installed one. Text Input Sources silently drops the input source when
# that happens, so building the project can remove the installed input method
# from the system without any error being reported anywhere.
#
# This script is idempotent and safe to run at any time.

set -euo pipefail

script_directory="${0:A:h}"
user_application="$HOME/Library/Input Methods/Jiukong Zhuyin.app"
system_application="/Library/Input Methods/Jiukong Zhuyin.app"
launch_services="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
bundle_identifier="tw.idv.jiukong.inputmethod.zhuyin"

if [[ -d "$user_application" && -d "$system_application" ]]; then
    print -u2 "Two Jiukong installations claim the same bundle identifier:"
    print -u2 "  $user_application"
    print -u2 "  $system_application"
    print -u2 "Remove the development copy with ./scripts/uninstall.sh before registering."
    exit 1
fi
if [[ -d "$user_application" ]]; then
    installed_application="$user_application"
elif [[ -d "$system_application" ]]; then
    installed_application="$system_application"
else
    print -u2 "Jiukong Zhuyin is not installed in either supported location:"
    print -u2 "  $user_application"
    print -u2 "  $system_application"
    exit 1
fi

if [[ -x "$launch_services" ]]; then
    # Xcode registers every build product, and LaunchServices can retain a
    # record even after its bundle was renamed, moved to Trash, or deleted.
    # Enumerating LaunchServices itself therefore catches stale records that a
    # filesystem search cannot. Unregister only records with Jiukong's exact
    # bundle identifier and keep every bundle intact.
    while IFS= read -r candidate_application; do
        [[ "$candidate_application" == "$installed_application" ]] && continue
        "$launch_services" -u "$candidate_application" 2>/dev/null || true
    done < <(
        "$launch_services" -dump 2>/dev/null | /usr/bin/awk \
            -v target="$bundle_identifier" '
            function emit() {
                if (identifier == target && path != "") print path
                path = ""
                identifier = ""
            }
            /^--------------------------------------------------------------------------------$/ {
                emit()
                next
            }
            /^path:/ {
                path = $0
                sub(/^path:[[:space:]]*/, "", path)
                sub(/[[:space:]]+\(0x[[:xdigit:]]+\)$/, "", path)
                next
            }
            /^identifier:/ {
                identifier = $0
                sub(/^identifier:[[:space:]]*/, "", identifier)
                next
            }
            END { emit() }
            '
    )

    "$launch_services" -gc
    "$launch_services" -f -R -trusted "$installed_application"
    sleep 1
fi

"$installed_application/Contents/MacOS/Jiukong Zhuyin" --register
