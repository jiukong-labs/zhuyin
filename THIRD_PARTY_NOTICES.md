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

## Development-only tooling

The checked-in Xcode project was generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen), copyright Yonatan Karp-Rudin and contributors, licensed under the MIT License. XcodeGen is a development tool and is not copied into or distributed with Jiukong Zhuyin.

Apple AppKit, InputMethodKit, Carbon/HIToolbox, CryptoKit, and SQLite are system frameworks or libraries supplied by macOS and are not redistributed by this repository.
