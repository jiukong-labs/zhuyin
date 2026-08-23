# MOE idiom lexicon

`idioms.tsv` holds Traditional Chinese four-character idioms (成語) with
canonical Bopomofo readings, sourced from the Republic of China Ministry of
Education's official 《成語典》 (Dictionary of Chinese Idioms). Unlike
`Data/JiukongCharacters` and `Data/JiukongPhrases`, this data is **not**
first-party — see `Data/MOEStandardCharacterTables/README.md` for the same
distinction drawn for the character-tier tables.

## Source

- **《成語典》2020**, Ministry of Education (National Academy for Educational
  Research). Text database `dict_idioms_2020_20260625.zip`, downloaded from
  `https://language.moe.gov.tw/001/Upload/Files/site_content/M0001/respub/dict_idiomsdict_download.html`.
  Retrieved 2026-08-23.
- Of the dictionary's 5,489 catalogued entries, this file keeps every row
  flagged 主條成語 (a main entry, not a cross-reference variant) with a
  four-character 成語 headword — all 1,642 such entries, in the dictionary's
  own catalog order (not a frequency ranking). Non-主條 variant entries and
  idioms of any other length (3-character, 5-character, and longer, plus the
  further ~20,000-entry 重編國語辭典修訂本 appendix the dictionary separately
  indexes) are not included; extending to those is future work, not done
  here.
- Only two of the dictionary's 22 columns are reproduced: 成語 (headword) and
  注音 (reading). Every other column — 釋義, 典源, 典故說明, 書證, 用法說明,
  etc. — is discarded and never read into this repository.
- Where a row's 注音 column carries a tone-sandhi variant marked `（變）`
  (e.g. 一毛不拔's 一 changing ㄧ → ㄧˋ before a falling-tone syllable), only
  the primary reading before `（變）` is kept. One entry, 難兄難弟, instead
  marks two senses with distinct readings as `（一）.../（二）...`
  (friends-in-adversity ㄋㄢˊ vs. two-of-a-kind-in-the-pejorative-sense
  ㄋㄢˋ); only the first sense's reading, `（一）`, is kept, on the same
  "one canonical reading per entry" basis as the `（變）` case. One entry,
  九泉之下, has a source-file formatting slip (an ASCII space instead of the
  usual full-width syllable separator between its first two syllables); the
  extraction splits on any whitespace run, not literally the full-width
  separator, so this doesn't change the kept reading. `phrases.tsv`-format
  entries carry one canonical reading sequence, matching how the rest of the
  phrase lexicon already works.

## License

《成語典》 is released under 創用CC－姓名標示－禁止改作 臺灣3.0版
(CC BY-ND 3.0 TW) — a copyrighted government publication, not a public-domain
administrative promulgation like the character-tier tables. The full official
usage note is retained verbatim in `idiomsdict_usage_note.txt` per its own
retention requirement; see `THIRD_PARTY_NOTICES.md` for the required
attribution line.

The note's clause (一)(四) explicitly protects 音讀 (the reading) from
modification, but separately exempts "字碼改換" (character-code conversion)
and any "不涉及更改《成語典》個別條目所有內容之調整行為" (an adjustment that
does not alter the content of an individual entry) from that restriction.
This repository's reading, on that basis: reproducing the headword and
reading fields **unmodified**, merely repackaged into this TSV format, is
format conversion rather than 改作 (a derivative work). What the note does
**not** address in so many words is keeping only 2 of an entry's 22 fields
while discarding the rest — this repository treats that as within the same
exemption (the two fields that are kept are not altered), but that reading is
this project's own judgment, not a quoted MOE determination, and has not been
independently confirmed with the Ministry.

## Extraction

Every (headword, reading) pair here was copied verbatim from the Ministry's
own `dict_idioms_2020_20260625.xlsx`, downloaded directly from the URL above
— no OCR, no LLM transcription or recollection of dictionary content. Each
per-character syllable in the kept primary reading was then cross-checked
against this repository's own CNS11643-backed `dictionary_entries` (the same
character dictionary `CharacterCandidateProvider` already queries): every one
of this file's 1,642 entries has all four syllables attested as a registered
(character, pronunciation) pair in that dictionary. This is a correctness
sanity check on the Ministry's own published reading, not a substitute for
it — nothing here was auto-derived or guessed; an earlier attempt to
auto-select a "default" reading from usage-tier/source-order alone (skipping
the Ministry's reading entirely) produced clearly wrong readings for common
characters (e.g. 落 in 水落石出, 草 in 草木皆兵) and was abandoned.

## How this is used

`idioms.tsv` follows the exact same two-column TSV grammar as
`Data/JiukongPhrases/phrases.tsv` (phrase, tab, space-separated canonical
Bopomofo readings) and is parsed the same way. Its entries are merged into
the same `phrase_entries` table as the first-party lexicon at build time,
with a cross-source duplicate check; `CharacterCandidateProvider` does not
distinguish a phrase's origin at lookup time.
