# Jiukong first-party phrase lexicon

`phrases.tsv` is an original, manually curated starter lexicon for Jiukong
Zhuyin. It is maintained as part of this repository and is not copied or
derived from another input method, dictionary, corpus, or frequency list.

Each non-comment line contains a phrase, one tab, then its space-separated
canonical Bopomofo readings. File order is the deterministic tie-break order;
there is deliberately no imported frequency score.

The dictionary builder validates every row, rejects duplicates, and embeds the
validated entries in the runtime SQLite database. It also counts exact
character-reading occurrences in this first-party file as a within-tier
candidate-order signal. Government-sourced phrase datasets are explicitly
excluded from that count, and the signal is not described as corpus frequency.
Additions should be reviewed for Traditional Chinese spelling, reading
accuracy, and practical usefulness.
