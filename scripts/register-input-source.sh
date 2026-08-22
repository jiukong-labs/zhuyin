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
repository_root="${script_directory:h}"
installed_application="$HOME/Library/Input Methods/Jiukong Zhuyin.app"
launch_services="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
bundle_identifier="tw.idv.jiukong.inputmethod.zhuyin"

if [[ ! -d "$installed_application" ]]; then
    print -u2 "Jiukong Zhuyin is not installed at $installed_application"
    print -u2 "Run ./scripts/install.sh first."
    exit 1
fi

if [[ -x "$launch_services" ]]; then
    # Xcode registers app products when it builds or tests them. Every product
    # has the release bundle identifier, so LaunchServices can resolve the
    # input method to a temporary or .build copy instead of the installed app.
    # Unregister only verified Jiukong build products; keep every file intact.
    typeset -A visited_applications
    for search_root in \
        "$repository_root/.build" \
        /private/tmp \
        "${TMPDIR:-/tmp}"; do
        [[ -d "$search_root" ]] || continue
        while IFS= read -r candidate_application; do
            candidate_application="${candidate_application:A}"
            [[ "$candidate_application" == "$installed_application" ]] && continue
            [[ -z "${visited_applications[$candidate_application]-}" ]] || continue
            visited_applications[$candidate_application]=1

            candidate_identifier="$(
                /usr/libexec/PlistBuddy \
                    -c 'Print :CFBundleIdentifier' \
                    "$candidate_application/Contents/Info.plist" \
                    2>/dev/null || true
            )"
            [[ "$candidate_identifier" == "$bundle_identifier" ]] || continue

            "$launch_services" -u "$candidate_application" 2>/dev/null || true
        done < <(
            /usr/bin/find "$search_root" \
                -type d \
                -name 'Jiukong Zhuyin.app' \
                -prune \
                -print 2>/dev/null
        )
    done

    "$launch_services" -gc
    "$launch_services" -f -R -trusted "$installed_application"
    sleep 1
fi

"$installed_application/Contents/MacOS/Jiukong Zhuyin" --register
