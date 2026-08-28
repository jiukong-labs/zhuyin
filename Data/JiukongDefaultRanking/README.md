# Jiukong default selection ranking

This directory contains a first-party baseline derived from Jiukong Zhuyin's
own selection history. The snapshot was taken on 2026-08-28 at 07:26
Asia/Taipei after the project owner explicitly chose to ship the current
selection data as the product default.

`character-selection-counts.tsv` contains 804 validated character-reading
identities and 7,066 selections. `phrase-selection-counts.tsv` contains 385
phrase-reading identities and 2,277 selections. Each row has the selected text,
its canonical Bopomofo reading (space-separated for phrases), and a positive
selection count.

The source user database is not included. Export processing deliberately
discarded timestamps, pins, record IDs, creation dates, CloudKit state, and all
phrases that did not already exist with the same reading in the project's
built-in dictionary. This keeps private or unreviewed phrases out of the
shipped lexicon. These files can rank an existing entry but cannot create one.

The dictionary builder validates every identity against the dictionary being
built and rejects malformed, duplicate, non-positive, or unknown rows. At
runtime these counts are a timeless base-ranking prior. Mutable per-user
learning, recency, and pins remain separate and retain higher precedence.

This is original project data, not an imported corpus, frequency list,
dictionary, or another input method's output.
