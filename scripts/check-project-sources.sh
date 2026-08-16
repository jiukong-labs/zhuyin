#!/bin/zsh

# Fails when a Swift file on disk is not referenced by the checked-in Xcode
# project. Regenerating the project is easy to forget, and the result is a
# target that silently stops compiling a new file, or a test that never runs.
#
# Usage: check-project-sources.sh [path-to-project.pbxproj]

set -euo pipefail
setopt null_glob

script_directory="${0:A:h}"
repository_root="${script_directory:h}"
project_file="${1:-${repository_root}/Jiukong Zhuyin.xcodeproj/project.pbxproj}"

if [[ ! -f "${project_file}" ]]; then
  print -u2 "No Xcode project file at ${project_file}"
  exit 1
fi

typeset -a swift_files
swift_files=(
  "${repository_root}"/Sources/**/*.swift
  "${repository_root}"/Tests/**/*.swift
  "${repository_root}"/Tools/**/*.swift
)

if (( ${#swift_files} == 0 )); then
  print -u2 "No Swift sources were found under ${repository_root}"
  exit 1
fi

typeset -a missing
for file in "${swift_files[@]}"; do
  if ! grep -q -F -- "${file:t}" "${project_file}"; then
    missing+=("${file#${repository_root}/}")
  fi
done

if (( ${#missing} > 0 )); then
  print -u2 "These Swift files are not referenced by the Xcode project:"
  for file in "${missing[@]}"; do
    print -u2 "  ${file}"
  done
  print -u2 ""
  print -u2 "Run 'xcodegen generate' and commit the regenerated project."
  exit 1
fi

print "All ${#swift_files} Swift files are referenced by the Xcode project."
