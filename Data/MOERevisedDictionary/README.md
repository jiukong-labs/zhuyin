# MOE revised dictionary four-character phrases

`four-character-phrases.tsv` holds four-character entries with canonical
Bopomofo readings, sourced from the Republic of China Ministry of
Education's official 《重編國語辭典修訂本》 (Revised Mandarin Chinese
Dictionary). Unlike `Data/JiukongCharacters` and `Data/JiukongPhrases`, this
data is **not** first-party — see `Data/MOEIdioms/README.md` for the same
distinction and license reasoning drawn for the idiom lexicon; this file
follows the identical reasoning, sourced from a different (much larger,
general-purpose rather than idiom-specific) MOE dictionary.

## Source

- **《重編國語辭典修訂本》**, Ministry of Education (National Academy for
  Educational Research). Text database `dict_revised_2015_20260625.zip`,
  downloaded from
  `https://language.moe.gov.tw/001/Upload/Files/site_content/M0001/respub/dict_reviseddict_download.html`.
  Retrieved 2026-08-23.
- Unlike 《成語典》, this dictionary is not idiom-curated — it is a general
  dictionary of 163,920 entries covering single characters through
  multi-character words and idioms of every length, with no column that
  distinguishes "idiom-like" entries from ordinary vocabulary or technical
  terminology. This file keeps every one of its 35,684 four-character
  entries (字數 = 4) that passed the validation described below; entries of
  any other length are out of scope here.
- Only two of the dictionary's 18 columns are reproduced: 字詞名 (headword)
  and 注音一式 (reading). Every other column — 釋義, 相似詞, 相反詞, 部首字,
  筆畫, etc. — is discarded and never read into this repository. 辭條別名
  (an alias column populated only for transliterated foreign proper nouns,
  e.g. 巴伐利亞 → "Bavaria") is likewise discarded.
- 7 of the 35,684 headwords repeat with two distinct readings for two senses
  (the same phenomenon as 難兄難弟 in the idiom lexicon, e.g. 一日之長 as
  "a slight edge in ability" ㄓㄤˇ vs. "a slight seniority in age" ㄔㄤˊ).
  The dictionary's own 多音排序 (poly-pronunciation ordering) column marks
  which sense is primary; only that one is kept, on the same "one canonical
  reading per entry" basis used throughout this repository's phrase data.
- 1,663 headwords that would otherwise qualify were skipped because they
  already exist, with the same text, in `Data/JiukongPhrases/phrases.tsv` or
  `Data/MOEIdioms/idioms.tsv` — this file adds no cross-source duplicates.

## What's excluded, and why

Of 34,014 remaining candidate headwords (35,684 minus the skipped
duplicates), 719 failed validation and are not in this file:

- **378 entries** are 兒化 (erhua) colloquialisms, where 兒 is pronounced
  fused into the preceding syllable rather than as its own syllable (e.g.
  巴高枝兒 "bāgāozhīr", written with only 3 space-separated syllables for 4
  characters). This repository's phrase format requires one reading per
  character; a fused erhua reading cannot be expressed as a 4-syllable
  sequence without inventing a syllable split the dictionary itself doesn't
  give, so these are left out rather than guessed at.
- **341 entries** use a neutral-tone (輕聲) colloquial reading for a
  character — mostly Beijing-colloquial vocabulary (e.g. 八大胡同 "hútòng",
  巴巴結結 "bābajiējie") — that is not among that character's registered
  readings in this dictionary's own CNS11643-backed `dictionary_entries`.
  Same principle as everywhere else in this repository: a reading is only
  accepted when it is already attested, never invented to fill a gap.

Both categories are legitimate spoken Mandarin, just not representable
without fabricating data this repository doesn't already have a source for;
neither is a defect in the source dictionary.

## Extraction

Every (headword, reading) pair here was copied verbatim from the Ministry's
own `dict_revised_2015_20260625.xlsx`, downloaded directly from the URL
above — no OCR, no LLM transcription or recollection of dictionary content.
Each per-character syllable in the kept reading was then cross-checked
against this repository's own CNS11643-backed `dictionary_entries` (the same
character dictionary `CharacterCandidateProvider` already queries): every one
of this file's 33,295 entries has all four syllables attested as a
registered (character, pronunciation) pair in that dictionary.

## License

Same CC BY-ND 3.0 TW family as `Data/MOEIdioms` — the Ministry's own usage
note for this dictionary (retained verbatim in `reviseddict_usage_note.txt`)
protects 詞目、部首、筆畫、字形、音讀及釋義 from modification but exempts
"字碼改換" and any "不涉及更改個別條目所有內容之調整行為" from that
restriction. The same reasoning applies here as in `Data/MOEIdioms/README.md`
— reproducing the headword and reading fields unmodified, repackaged into
this TSV format, is treated as format conversion; keeping only 2 of 18
fields is this repository's own judgment on that exemption, not a quoted MOE
determination.

## How this is used

`four-character-phrases.tsv` follows the exact same two-column TSV grammar
as `Data/JiukongPhrases/phrases.tsv` and `Data/MOEIdioms/idioms.tsv` and is
parsed the same way. Its entries are merged into the same `phrase_entries`
table as the other two sources at build time, with a cross-source duplicate
check; `CharacterCandidateProvider` does not distinguish a phrase's origin
at lookup time.
