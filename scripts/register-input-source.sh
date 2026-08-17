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

if [[ ! -d "$installed_application" ]]; then
    print -u2 "Jiukong Zhuyin is not installed at $installed_application"
    print -u2 "Run ./scripts/install.sh first."
    exit 1
fi

if [[ -x "$launch_services" ]]; then
    "$launch_services" -f -R -trusted "$installed_application"
    sleep 1
fi

"$installed_application/Contents/MacOS/Jiukong Zhuyin" --register
