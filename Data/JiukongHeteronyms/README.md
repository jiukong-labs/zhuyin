# Jiukong first-party heteronym tier overrides

`heteronym-tiers.tsv` contains original, manually reviewed usage-tier
overrides for individual (character, reading) pairs. It is not copied or
derived from another input method, dictionary, or corpus.

## Why this exists

`Data/MOEStandardCharacterTables` classifies a whole character as common,
semi-common, or neither — it has no concept of "this character's reading."
A 破音字/heteronym can be a common character overall while one specific
reading of it is archaic, dialectal, or otherwise rare (疋 is a common
character read ㄆㄧˇ, but its ㄕㄨ reading is not; 食 and 射 are common
characters, but their ㄧˋ readings have narrowly restricted uses). When that happens, the
character-level MOE tier ties the rare reading with every other everyday
character sharing that reading. First-party phrase evidence improves many
ties, but an unattested rare reading can still fall back to an early CNS source
position, which reflects a standard code table rather than modern usage. This
file is the one place a specific reading
can be pushed below (or, if a genuine case turns up, above) its character's
default MOE tier.

## Format

Each non-comment, non-blank row is three tab-separated fields: exactly one
character, one canonical Bopomofo reading, and a usage tier (`0`, `1`, or
`2`). A row only affects that exact (character, reading) pair; every other
reading of the same character keeps using the MOE character-level tier.

## Review bar

Every row must be:

1. **Verified against the pinned dictionary snapshot** — the dictionary
   builder rejects an override whose (character, reading) pair does not
   exist in `Resources/Dictionary/JiukongZhuyin.sqlite3`'s sources, so a typo
   fails the build instead of silently doing nothing.
2. **A specific, checkable claim**, not a guess — e.g. "this reading only
   occurs in one classical/archaic compound" — and ideally checked against
   the actual candidate order it changes (`sqlite3 …
   Resources/Dictionary/JiukongZhuyin.sqlite3 "SELECT character, source_order
   FROM dictionary_entries WHERE pronunciation = '…' ORDER BY
   source_order"`) before and after adding the row.
3. **Additive, not comprehensive** — this file is expected to grow one
   verified case at a time as they're found (starting with the ㄕㄨ/疋 case
   that motivated it and adding individually verified cases), the same way
   `Data/JiukongCharacters` grows. It is
   deliberately not an attempt to hand-classify every multi-reading
   character in the dictionary; most heteronyms already rank fine and don't
   need a row here.
