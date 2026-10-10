# Jiukong first-party phrase lexicon

`phrases.tsv` is an original, manually curated starter lexicon for Jiukong
Zhuyin. It is maintained as part of this repository and is not copied or
derived from another input method, dictionary, corpus, or frequency list.

Each non-comment line contains a phrase, one tab, then its space-separated
canonical Bopomofo readings. File order is the deterministic tie-break order;
there is deliberately no imported frequency score.

Phrases containing punctuation add a third tab-separated field with the
output pattern: `R` consumes a reading and `P` emits punctuation without a
reading (for example, `好嗎？` uses `RRP`).

The dictionary builder validates every row, rejects duplicates, and embeds the
validated entries in the runtime SQLite database. It also counts exact
character-reading occurrences in this first-party file as a within-tier
candidate-order signal. Government-sourced phrase datasets are explicitly
excluded from that count, and the signal is not described as corpus frequency.
Additions should be reviewed for Traditional Chinese spelling, reading
accuracy, and practical usefulness.

The 2026-09-07 maintainer-provided ChatGPT phrase-pack additions and review
record are documented in [import-20260907.md](import-20260907.md).

The 2026-10-07 owner user-phrase review, accepted additions, and withheld
spelling/reading or context-dependent entries are documented in
[import-20261007.md](import-20261007.md).

The 2026-10-10 follow-up owner user-phrase review, 21 accepted additions,
and four owner-requested built-in removals are documented in
[import-20261010.md](import-20261010.md).
