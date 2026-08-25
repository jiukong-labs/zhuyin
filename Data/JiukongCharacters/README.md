# Jiukong first-party character readings

`characters.tsv` contains original, manually reviewed character readings that
Jiukong intentionally supports in addition to the pinned CNS11643 snapshot.
It is not copied or derived from another input method or lexicon.

Each non-comment row contains exactly one character, one tab, then one
canonical Bopomofo reading. A supplemental character must already exist in the
pinned CNS11643 character set; the dictionary builder reuses that character's
CNS code and source position so repertoire filtering and deterministic ranking
continue to work normally.
