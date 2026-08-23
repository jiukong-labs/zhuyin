# MOE standard character tables

`common-4808.txt` and `semi-common-6343.txt` are the Republic of China
Ministry of Education's two officially promulgated standard character
tables, used here as a coarse, three-tier candidate usage score (0 = common,
1 = semi-common, 2 = default for any character in neither table). Unlike
`Data/JiukongCharacters` and `Data/JiukongPhrases`, this data is **not**
first-party — it is copied verbatim from government publications. It is also
**not** a corpus or another input method's frequency table: it classifies
whether a character belongs to a national standard list, not how often it
occurs in any text.

## Source

- **常用國字標準字體表** (Standard Form of Common National Characters),
  4,808 characters, promulgated by the Ministry of Education on 1982-09-01.
  Downloaded from the Ministry's own Language Portal:
  `https://language.moe.gov.tw/uploads/files/17694982751710.ods`
  (linked from `https://language.moe.gov.tw/material/info?m=9fe3ff5a-5a8c-4817-9e60-6337dd55a509`).
  Extracted deterministically from the ODS `content.xml` table (no OCR, no
  LLM transcription); the extracted count matches the promulgated 4,808
  exactly, with zero duplicates.
- **次常用國字標準字體表** (Standard Form of Semi-Common National
  Characters), 6,343 characters, promulgated by the Ministry of Education in
  1993 (the *國字標準字體楷書母稿* count; a 2017 異體字字典 appendix
  reclassifies 9 of these as unit-symbol characters and 5 to a
  yet-to-be-determined table, yielding 6,329 — this repository intentionally
  keeps the original, larger 1993 promulgation rather than that later
  reclassification). No direct machine-readable file is published by the
  Ministry, so this table was retrieved from Wikisource's full-text
  transcription (`https://zh.wikisource.org/wiki/次常用國字標準字體表`, itself
  citing the Ministry of Education as author) via `Special:Export`, which
  returns the page's raw wikitext rather than an LLM's summary of it. Each
  character was derived from the table's `Unicode` column
  (`chr(int(code, 16))`), then cross-checked against the table's own displayed
  glyph; the extraction produced zero mismatches across all 6,343 rows. The
  extracted count matches the promulgated 6,343 exactly, with zero
  duplicates and zero overlap with the common-character table.

Retrieved 2026-08-23.

## License

Both tables are promulgations of the Ministry of Education — an
administrative order/公文 of a central government agency — and are treated
as public domain under Republic of China Copyright Act Article 9, the same
basis on which Wikisource hosts their full text. This is the same standing
as the CNS11643 national standard already pinned under `Data/CNS11643`: a
government-published national standard, not a private party's compiled
corpus or another input method's proprietary lexicon.

## Format

One Han character per line, UTF-8, no header row. Lines starting with `#`
are a provenance comment and are ignored by the parser, as are blank lines.

## How this is used

`Tools/DictionaryBuilder` loads both files into a character → tier map
(0 or 1; a character in neither file has no entry and defaults to tier 2)
and stores the result per dictionary row as `usage_tier`. Because both
tables classify a character as a whole, they cannot express that one of a
character's several readings is common while another is rare — see
`Data/JiukongHeteronyms/README.md` for the first-party override that handles
that case.
