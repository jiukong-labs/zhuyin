#!/bin/zsh

set -euo pipefail

script_directory="${0:A:h}"
repository_root="${script_directory:h}"
derived_data_path="${JIUKONG_DICTIONARY_DERIVED_DATA_PATH:-${repository_root}/.build/DictionaryBuilder}"
source_directory="${repository_root}/Data/CNS11643/20260805"
character_source="${repository_root}/Data/JiukongCharacters/characters.tsv"
phrase_source="${repository_root}/Data/JiukongPhrases/phrases.tsv"
idiom_source="${repository_root}/Data/MOEIdioms/idioms.tsv"
revised_dictionary_source="${repository_root}/Data/MOERevisedDictionary/four-character-phrases.tsv"
frequency_common_source="${repository_root}/Data/MOEStandardCharacterTables/common-4808.txt"
frequency_semi_common_source="${repository_root}/Data/MOEStandardCharacterTables/semi-common-6343.txt"
heteronym_tier_source="${repository_root}/Data/JiukongHeteronyms/heteronym-tiers.tsv"
default_character_ranking_source="${repository_root}/Data/JiukongDefaultRanking/character-selection-counts.tsv"
default_phrase_ranking_source="${repository_root}/Data/JiukongDefaultRanking/phrase-selection-counts.tsv"
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
  --idioms "${idiom_source}" \
  --revised-dictionary "${revised_dictionary_source}" \
  --frequency-common "${frequency_common_source}" \
  --frequency-semi-common "${frequency_semi_common_source}" \
  --heteronym-tiers "${heteronym_tier_source}" \
  --default-character-ranking "${default_character_ranking_source}" \
  --default-phrase-ranking "${default_phrase_ranking_source}" \
  --output "${output_path}"
