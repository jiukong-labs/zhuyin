# Milestone 7: uncommitted composition and user phrases

## Goal

Keep converted characters inside the input method until the user really commits them, so a phrase can be selected and learned from the text the user just typed. Phrase creation must never read text that already belongs to the client application, and a failure of the user database must never prevent ordinary CNS conversion.

This milestone does not add a settings window, pin management, import/export, punctuation mapping, prefix prediction, or automatic phrase completion.

## Composition buffer

`CompositionBuffer` owns every converted unit that has not yet been inserted into the client. One `CompositionUnit` carries a `UUID`, its text, and the exact reading that produced it, so a unit is always paired with the pronunciation it will be learned under.

Selection is a contiguous range of the buffer. It originally started as an
end-anchored suffix and now also supports a revision focus as its origin:

```text
units              ㄨㄛˇ 我   ㄇㄣ˙ 們   ㄉㄜ˙ 的
selectedUnitRange  nil, or one contiguous Range<Int>
```

`markedSelectionRange` converts that unit range into UTF-16 code units for AppKit, so multi-scalar text cannot desynchronize the highlight. `selectedPhrase` returns a phrase only at two or more units.

Accepting a candidate does not commit it. A character candidate appends one unit; a phrase candidate replaces the exact reading suffix it matched. Both record a `PendingCandidateSelection` holding the candidate, its commit reason, and the identifiers of the units it covers. Any replacement or deletion prunes pending selections whose covered units no longer exist, so an event cannot survive the text it described.

`takeCommitSnapshot()` detaches the units and pending selections and resets the buffer before returning, so a reentrant client callback cannot consume the same pending learning twice.

## Marked text and gestures

`CompositionPresentation.make(buffer:activeSuffix:)` is the single pure source of `setMarkedText` content. An active raw syllable or candidate reading always owns the caret at the end; the buffer's phrase highlight is exposed only when no active suffix exists.

`CompositionSelectionCommandRouter` recognizes exactly two gestures — Shift+← extends the left range edge and Shift+→ extends the right edge. Carbon's inherent `.function` and `.numericPad` arrow flags are tolerated, while Command, Control, and Option are rejected so real client shortcuts still work. A raw syllable or expanded chooser still owns its arrows. In compact revision locating mode, a Shift arrow closes the candidate panel and starts phrase selection from the focused unit in the requested direction.

With a buffer and no active syllable or candidate:

- Return/Keypad Enter adds the selected phrase to the user dictionary when at least two units are selected, then commits the whole composition once;
- Escape clears the selection, or discards the buffer when nothing is selected;
- Backspace or forward Delete removes the selected range or explicitly focused
  revision unit. With neither target, Backspace deletes the last unit while
  forward Delete remains available to the client application.

## Phrase lookup and ranking

`CompositionBuffer.phraseLookupQueries(appending:)` emits every exact suffix lookup ending in the active reading, longest first, from 64 units down to 2. `CharacterCandidateProvider` runs those queries against the user dictionary, deduplicates by reading sequence and candidate identity, revalidates every stored record, and merges the results ahead of the CNS character candidates before ranking.

`CandidateRanker` keeps the Milestone 6 policy and adds one type term:

```text
base score    = -baseRank
user bonus    = 8 × log2(selectionCount + 1)
recency bonus = 4 × 0.5 ^ (age / 7 days)
phrase bonus  = 1024 for a user phrase, otherwise 0
score         = base score + user bonus + recency bonus + phrase bonus
```

Pinned entries remain a separate tier above everything unpinned, so an unpinned phrase never outranks a pinned character. Lookup is exact equality on the full reading sequence: there is no prefix association and no unconfirmed auto-completion.

## Deferred learning

Learning happens only when the marked composition actually reaches the client. `flushComposition` accepts any preferred candidate, appends a raw Bopomofo fallback if one is active, takes the commit snapshot, inserts the text, and only then replays each pending selection into `recordCommittedSelection`. Characters are recorded per reading; phrases are revalidated against `UserPhraseValidator` before their selection count advances.

Content dropped by Escape, removed by Backspace, or replaced by a phrase candidate leaves no counts behind, because its pending selections were pruned before the snapshot existed.

## Schema v2

The database path and hardening rules are unchanged from Milestone 6. Schema version 2 keeps `character_learning` in place and adds:

```sql
CREATE TABLE user_phrases (
    phrase_id INTEGER PRIMARY KEY,
    phrase TEXT NOT NULL CHECK(length(phrase) > 0),
    pronunciation_key TEXT NOT NULL CHECK(length(pronunciation_key) > 0),
    created_at INTEGER NOT NULL,
    last_used_at INTEGER,
    selection_count INTEGER NOT NULL DEFAULT 0 CHECK(selection_count >= 0),
    pinned INTEGER NOT NULL DEFAULT 0 CHECK(pinned IN (0, 1)),
    UNIQUE (pronunciation_key, phrase)
);

CREATE TABLE user_phrase_readings (
    phrase_id INTEGER NOT NULL,
    reading_index INTEGER NOT NULL CHECK(reading_index >= 0),
    pronunciation TEXT NOT NULL CHECK(length(pronunciation) > 0),
    PRIMARY KEY (phrase_id, reading_index),
    FOREIGN KEY (phrase_id) REFERENCES user_phrases(phrase_id) ON DELETE CASCADE
) WITHOUT ROWID;
```

`pronunciation_key` is a versioned, UTF-8 length-prefixed encoding (`v1|6:ㄨㄛˇ…`). Length prefixes keep `["ab", "c"]` and `["a", "bc"]` distinct without reserving a separator character that could appear in a reading. `UserPhraseValidator` normalizes to precomposed form, requires 2 through 64 readings, requires one text unit per reading, and rejects any reading that is not canonical initial/medial/final/tone Bopomofo. The ordered readings table remains the authority for display and revalidation; the key exists only for exact SQL lookup.

Migration from version 1 creates the phrase tables and index inside one immediate transaction and bumps `user_version`; Milestone 6 character rows are untouched. A version-0 file owned by this application is upgraded in place, an unknown application ID, a future version, or an unexpected table set is reported without replacement, and `UserLearningService` continues to serialize every client through one store and log only generic messages.

## Automated verification

The suite covers all earlier milestones plus:

- buffer append, candidate acceptance, phrase-suffix replacement, pending-selection pruning, and snapshot detachment;
- UTF-16 marked-selection ranges, directional range expansion at both limits, and presentation precedence for an active range;
- Shift-arrow recognition, rejection of Command/Control/Option chords, and inherent arrow flags;
- longest-first phrase query generation, exact-suffix matching, and query bounds;
- phrase candidate merging, deduplication, record revalidation, and the phrase and pin ranking tiers;
- phrase validation, canonical reading checks, and pronunciation-key round trips including ambiguous sequences;
- schema v2 creation, version-1 migration with preserved character rows, foreign keys, ordered readings, exact lookup, count saturation, and pin preservation;
- deferred learning across Return, Escape, Backspace, pass-through, and lifecycle commits.

Run:

```sh
xcodegen generate
xcodebuild -project "Jiukong Zhuyin.xcodeproj" -scheme "Jiukong Zhuyin" -configuration Debug -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData test
xcodebuild -project "Jiukong Zhuyin.xcodeproj" -scheme "Jiukong Zhuyin" -configuration Release -destination "generic/platform=macOS" -derivedDataPath .build/DerivedData build
```

On 2026-08-15, Xcode 26.6 with the macOS 26.5 SDK completed all 194 Debug tests with no failures, and the generic Release build produced a strict-code-signature-valid universal `arm64`/`x86_64` application with no warnings.

The Milestone 7 sources were added without regenerating the checked-in Xcode project, so the first Debug test run failed to build until `xcodegen generate` was run again. Maintainers who add a file must regenerate the project in the same change.

## Installed acceptance results

On 2026-08-16 the ad-hoc-signed Release bundle was installed and driven through real `CGEvent` delivery to isolated, UUID-named TextEdit documents. The installed executable matched the Release build byte for byte (SHA-256 `35b202c5939fb3671e0f8851cdc9b5a61392fb80d76025d438aa0d168b555be5`), strict signature verification passed, and the input source reported itself enabled and selectable.

Each run first proved that the client was actually talking to Jiukong: a probe syllable had to raise Jiukong's own candidate panel, identified by window owner. Without that proof a run aborts, because the system's own Zhuyin input method composes the same Bopomofo from the same keys and would otherwise be mistaken for this one. The runs are repeatable through `./scripts/run-acceptance.sh`.

```text
j i 3, Return, Return                  → 我 committed exactly once, no stray newline
j i 3, Escape, Escape                  → empty document; nothing committed
r u . 3, Space, d j / Space, Space,
  Left, Shift+Left, Return             → 九空 committed, and stored as one user phrase
```

The created phrase appeared in `user.sqlite` as `九空` with ordered readings `ㄐㄧㄡˇ ㄎㄨㄥ` at schema version 2, and the character counts for 九 and 空 advanced to 1 each, confirming that learning happens only on the real client commit.

## Intentional limitations

Phrase lookup is exact and longest-suffix only. Phrase pinning exists in the schema, service, and ranker but has no UI. Selection is limited to a contiguous range of the input method's own buffer, so text already committed to the client cannot be turned into a phrase. Milestone 8 adds the settings window, Shift-side persistence, pin and dictionary management, import/export, and data clearing.
