# Third-Party Notices

## CNS11643 character data

Jiukong Zhuyin contains data derived from:

- Provider: 數位發展部 (Ministry of Digital Affairs, Taiwan)
- Dataset: CNS11643中文標準交換碼全字庫
- Snapshot version: 20260805
- Source: https://www.cns11643.gov.tw
- Dataset record: https://data.gov.tw/dataset/5961/
- License: 政府資料開放授權條款－第1版 (Open Government Data License, version 1.0), https://data.gov.tw/license

The repository retains the pinned phonetic and CNS/Unicode mapping source snapshot with individual SHA-256 hashes. `JiukongDictionaryBuilder` joins those mappings, excludes Unicode private-use scalars, deduplicates pronunciation/character pairs, and preserves source order in a read-only SQLite dictionary.

The CNS11643 source snapshot and the character data derived from it in the generated dictionary are not covered by Jiukong Zhuyin's MIT License; their use and redistribution are governed by the Open Government Data License above. The separate phrase table is original Jiukong data covered by this repository's MIT License. CNS11643 fonts, glyph files, and audio are not included.

## MOE standard character tables

Jiukong Zhuyin's candidate ranking contains data derived from:

- Provider: 教育部 (Ministry of Education, Taiwan)
- Datasets: 常用國字標準字體表 (Standard Form of Common National Characters,
  4,808 characters, promulgated 1982-09-01) and 次常用國字標準字體表
  (Standard Form of Semi-Common National Characters, 6,343 characters,
  promulgated 1993)
- Sources: https://language.moe.gov.tw/uploads/files/17694982751710.ods
  (common characters); https://zh.wikisource.org/wiki/次常用國字標準字體表
  (semi-common characters, no direct machine-readable file published by the
  Ministry)
- Retrieved: 2026-08-23
- License: promulgations of a central government agency, public domain under
  Republic of China Copyright Act Article 9 — the same basis as the CNS11643
  data above; see `Data/MOEStandardCharacterTables/README.md` for the full
  provenance and extraction method.

`JiukongDictionaryBuilder` uses these two disjoint character lists as a
coarse three-tier (common / semi-common / other) usage score per dictionary
entry; a separate, first-party, manually reviewed override table in
`Data/JiukongHeteronyms` (MIT-licensed, covered by this repository's normal
license, not this notice) can override that tier for one specific
(character, reading) pair. Like the CNS11643 data above, the MOE tables
themselves are not covered by Jiukong Zhuyin's MIT License.

## MOE idiom lexicon

Jiukong Zhuyin's phrase candidates contain data derived from:

- Provider: 教育部 (Ministry of Education, Taiwan) / 國家教育研究院
- Dataset: 《成語典》2020 (Dictionary of Chinese Idioms)
- Source file: `dict_idioms_2020_20260625.xlsx`, downloaded from
  https://language.moe.gov.tw/001/Upload/Files/site_content/M0001/respub/dict_idiomsdict_download.html
- Retrieved: 2026-08-23
- License: 創用CC－姓名標示－禁止改作 臺灣3.0版 (CC BY-ND 3.0 TW) — a
  copyrighted government publication, **not** the Article 9 public-domain
  basis the CNS11643 and MOE character-table data above rely on. See
  `Data/MOEIdioms/README.md` for the full provenance, extraction method, and
  the license reasoning for reproducing only the headword and reading
  fields.

Attribution, as required by the license:

> 中華民國教育部（Ministry of Education, R.O.C.）。《成語典》（版本編
> 號：dict_idioms_2020_20260625）網址：http://dict.idioms.moe.edu.tw/

The license's full usage note is retained verbatim in
`Data/MOEIdioms/idiomsdict_usage_note.txt` per its own retention requirement.
`JiukongDictionaryBuilder` merges these entries into the same phrase table as
the first-party lexicon; like the CNS11643 and MOE character-table data
above, this idiom data itself is not covered by Jiukong Zhuyin's MIT License.

## MOE revised dictionary phrases

Jiukong Zhuyin's phrase candidates also contain data derived from:

- Provider: 教育部 (Ministry of Education, Taiwan) / 國家教育研究院
- Dataset: 《重編國語辭典修訂本》 (Revised Mandarin Chinese Dictionary)
- Source file: `dict_revised_2015_20260625.xlsx`, downloaded from
  https://language.moe.gov.tw/001/Upload/Files/site_content/M0001/respub/dict_reviseddict_download.html
- Retrieved: 2026-08-23
- License: 創用CC－姓名標示－禁止改作 臺灣3.0版 (CC BY-ND 3.0 TW), the same
  license family as the 《成語典》 data above, not the Article 9
  public-domain basis the CNS11643 and MOE character-table data rely on. See
  `Data/MOERevisedDictionary/README.md` for the full provenance, scope
  (four-character entries only, out of a 163,920-entry general dictionary),
  and what was excluded and why.

Attribution, as required by the license:

> 中華民國教育部（Ministry of Education, R.O.C.）。《重編國語辭典修訂
> 本》（版本編號：dict_revised_2015_20260625）網址：http://dict.revised.moe.edu.tw/

The license's full usage note is retained verbatim in
`Data/MOERevisedDictionary/reviseddict_usage_note.txt` per its own retention
requirement. Like the 《成語典》 data above, this data itself is not covered
by Jiukong Zhuyin's MIT License.

## Development-only tooling

The checked-in Xcode project was generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen), copyright Yonatan Karp-Rudin and contributors, licensed under the MIT License. XcodeGen is a development tool and is not copied into or distributed with Jiukong Zhuyin.

Apple AppKit, InputMethodKit, Carbon/HIToolbox, CryptoKit, and SQLite are system frameworks or libraries supplied by macOS and are not redistributed by this repository.
