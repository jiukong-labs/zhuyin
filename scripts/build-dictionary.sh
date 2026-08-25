#!/bin/zsh

set -euo pipefail

script_directory="${0:A:h}"
repository_root="${script_directory:h}"
derived_data_path="${JIUKONG_DICTIONARY_DERIVED_DATA_PATH:-${repository_root}/.build/DictionaryBuilder}"
source_directory="${repository_root}/Data/CNS11643/20260805"
character_source="${repository_root}/Data/JiukongCharacters/characters.tsv"
phrase_source="${repository_root}/Data/JiukongPhrases/phrases.tsv"
heteronym_tier_source="${repository_root}/Data/JiukongHeteronyms/heteronym-tiers.tsv"
output_path="${repository_root}/Resources/Dictionary/JiukongZhuyin.sqlite3"

xcodebuild \
  -project "${repository_root}/Jiukong Zhuyin.xcodeproj" \
  -scheme "Jiukong Dictionary Builder" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "${derived_data_path}" \
  build

builder_path="${derived_data_path}/Build/Products/Release/JiukongDictionaryBuilder"
if [[ ! -x "${builder_path}" ]]; then
  print -u2 "Dictionary builder was not produced at ${builder_path}"
  exit 1
fi

"${builder_path}" \
  --source "${source_directory}" \
  --characters "${character_source}" \
  --phrases "${phrase_source}" \
  --heteronym-tiers "${heteronym_tier_source}" \
  --output "${output_path}"
