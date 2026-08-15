# Milestone 8: preferences and settings

Milestone 8 was built in two phases. Phase A added persistent preferences, the
settings window, the automatic-learning switch, and user-data clearing. Phase B
added the user-dictionary management lists and import/export. Both are described
here.

## Goal

Let the user change how the input method behaves, see and edit what it has learned, and move that data between Macs — without ever letting a settings failure interfere with typing. A malformed or unreadable preference must degrade to the shipped default rather than block input, clearing must never leave the database half-emptied, and an import must never be able to corrupt existing data.

Milestone 8 does not add punctuation mapping, cloud sync, or any network access.

## Preference model

`Preferences` is a plain value with two fields:

```text
shiftKeyPreference       both | left | right | disabled   (default both)
automaticLearningEnabled true | false                     (default true)
```

Decoding is pure, total, and tested without `UserDefaults`. Each field falls back independently to its default when the stored value is missing, of the wrong type, or unknown, so one bad key cannot reset the other setting. Booleans accept the property-list and `defaults write` spellings (`1`, `0`, `"yes"`, `"NO"`). A stored version newer than `Preferences.currentVersion` is not guessed at: the defaults are used until the user changes a setting, which rewrites the file at the current version.

`UserDefaultsPreferencesStore` reads and writes only the three namespaced keys this build owns:

```text
JiukongPreferencesVersion
JiukongShiftLanguageToggle
JiukongAutomaticLearningEnabled
```

An unrelated key in the same domain can therefore never be mistaken for a setting, and a save never destroys anything else in the domain.

`PreferencesController` is the process-wide owner, mirroring `LanguageModeController`. It caches the decoded value behind a lock so a keystroke never touches `UserDefaults`, saves and posts `didChangeNotification` only when the value actually changes, and posts outside the lock so an observer can read `current` while handling the notification. `reload()` picks up an external edit.

## Shift side and automatic learning

`ShiftToggleController` already modeled all four side policies; Milestone 8 supplies the persisted one instead of the fixed `both`. `disabled` makes a standalone Shift tap inert while leaving Shift chords, letters, and shortcuts untouched.

The learning switch gates implicit recording only:

- off: no new character or phrase usage counts are written, for every commit reason;
- off: existing counts, recency, and pins still rank candidates, and existing user phrases still appear;
- off: Shift phrase creation still works, because the user asked for that phrase explicitly;
- on again: the next commit resumes counting without any restart.

## Clearing user data

`UserLearningStore` gains three operations, each running inside one immediate transaction that revalidates the schema before committing:

```text
clearCharacterLearning   DELETE character_learning
clearUserPhrases         DELETE user_phrase_readings, user_phrases
clearAllUserData         both, atomically
```

Phrase readings are deleted explicitly rather than relying on the cascade, so the result is identical whether or not foreign keys are enforced. Clearing keeps the application ID, schema version, tables, and file permissions in place: the same connection keeps working, and the next selection writes a fresh row. `UserLearningService` reports success or failure so the settings window can say that a clear did not take effect instead of appearing to succeed.

## Managing individual entries

Both data sets can be listed, searched, pinned, and deleted one entry at a time.

`UserLearningStore.allCharacterRecords()` and `allPhraseRecords()` return the same order the ranker prefers: pinned first, then most used, then most recently used, then a deterministic tie-break. The phrase query is the existing exact-lookup join with its reading key omitted, so a listed phrase carries its ordered readings and is validated exactly like one produced by a lookup.

Deletion is keyed by the full identity — reading plus text — so removing 行/ㄒㄧㄥˊ leaves 行/ㄏㄤˊ untouched. Deleting a phrase removes its ordered readings in the same transaction. A missing row is not an error, so two windows deleting the same entry cannot produce a failure alert.

`UserDataListController` renders one data set. Its rows are a snapshot re-read after every edit, so the list can never act on an entry another window already removed, and its filter is applied in memory over text and readings.

## Import and export

`UserDataArchive` is the portable representation:

```json
{
  "format": "jiukong-zhuyin-user-data",
  "version": 1,
  "exportedAt": 1755235200000,
  "characters": [
    { "character": "鍵", "pronunciation": "ㄐㄧㄢˋ",
      "selectionCount": 6, "lastSelectedAt": 1755235200000, "pinned": false }
  ],
  "phrases": [
    { "phrase": "久空", "readings": ["ㄐㄧㄡˇ", "ㄎㄨㄥ"],
      "selectionCount": 2, "createdAt": 1755235200000,
      "lastUsedAt": null, "pinned": false }
  ]
}
```

Timestamps are UTC Unix milliseconds, matching the database, so an export never depends on a locale or time zone. The local `phrase_id` is deliberately not exported: it is a row identity, not user data. Encoding uses sorted keys and pretty printing so an export is stable and diffable.

Decoding is total where it safely can be. An unreadable file, a foreign `format`, or a version newer than this build is refused outright. A structurally valid document is otherwise accepted without its unusable rows, and the count of skipped characters and phrases is reported to the user. A row is unusable when the text is not exactly one character (or does not match its reading count, for a phrase), when a reading is not canonical Bopomofo, when a count is negative, or when it repeats an identity already read from the same file.

Import merges rather than replaces, inside one transaction:

```text
selection_count   max(existing, imported)
last_selected_at  the newer of the two, ignoring a missing one
last_used_at      the newer of the two, ignoring a missing one
created_at        the earlier of the two
pinned            existing OR imported
```

Every rule is idempotent, so importing the same file twice changes nothing the second time, and importing a file from another Mac cannot lower a count or unpin an entry. An entry that cannot be applied — for example a phrase whose readings disagree with an existing row — aborts the whole import and leaves the database exactly as it was.

## Settings window

`InputController.menu()` contributes 偏好設定… to the macOS input menu. Choosing it finalizes any active composition first, so no marked text is stranded in a client that is about to lose focus.

`SettingsWindowController` owns one window for the whole process. The bundle is an `LSUIElement` agent, so the process is activated explicitly before the window is ordered front and deactivated when it closes; the window is kept, not released, so reopening restores its position. Four tabs divide the surface:

```text
一般        Shift side pop-up, automatic-learning checkbox
使用者詞    phrase list with search, pin/unpin, delete
選字紀錄    character list with search, pin/unpin, delete
資料        export, import, and the three clear buttons
```

Every destructive action is confirmed by an alert that names exactly what will be removed and states that it cannot be undone. A failed clear, delete, or import reports that the existing data was kept, and a completed import reports how many entries were merged and how many were skipped.

The window is Traditional Chinese only for now, matching the bundle's development region.

## Automated verification

The suite covers all earlier milestones plus:

- default preferences for an empty domain, per-field fallback for malformed and unknown values, wrong-type isolation, boolean spellings, missing version, and refusal to guess a future or invalid version;
- a persisted round trip for every Shift side, version stamping, preservation of unrelated keys, rejection of unnamespaced keys, and manually written defaults;
- controller caching, single persist and single notification per real change, no write or notification for an unchanged update, observer reads during the notification, `reload()` after an external edit, and concurrent readers and writers converging on one saved value;
- automatic learning off for every commit reason, for both character and phrase candidates, while ranking and explicit phrase creation still work;
- clearing characters only, phrases only with their ordered readings, and both; schema, application ID, table set, and further writes surviving a clear; ranking returning to base CNS order after a clear; and failure reporting without storage;
- listing order for both data sets, ordered readings for listed phrases, identity-keyed deletion that spares another reading of the same text, phrase-reading removal, and a tolerated absent row;
- archive round trips without loss, omission of the local phrase identifier, refusal of a foreign format, a future version, and an unreadable file, per-row skipping with counts, duplicate collapsing, and distinct readings of the same text;
- merge inserting new entries with their imported metadata, keeping the larger count, the newer timestamp in both directions, the earlier creation time and the combined pin, staying idempotent on re-import, reproducing a data set on a second database, and rolling back completely when one entry cannot be applied;
- an imported phrase being offered as a candidate immediately, and every management operation reporting missing storage.

Run:

```sh
xcodegen generate
xcodebuild -project "Jiukong Zhuyin.xcodeproj" -scheme "Jiukong Zhuyin" -configuration Debug -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData test
xcodebuild -project "Jiukong Zhuyin.xcodeproj" -scheme "Jiukong Zhuyin" -configuration Release -destination "generic/platform=macOS" -derivedDataPath .build/DerivedData build
```

On 2026-08-16, Xcode 26.6 with the macOS 26.5 SDK completed all 243 Debug tests with no failures, and the generic Release build produced a strict-code-signature-valid universal `arm64`/`x86_64` application with no warnings.

The settings window itself is AppKit UI and stays outside the unit-test target, like the candidate panel and the mode HUD. For local verification the executable accepts a maintainer-only argument that shows the same window without starting an input session:

```sh
"$(pwd)/.build/DerivedData/Build/Products/Debug/Jiukong Zhuyin.app/Contents/MacOS/Jiukong Zhuyin" --settings
```

On 2026-08-16 that window rendered correctly in dark appearance at 520 points wide. All four tabs laid out as intended: the pop-up and checkbox showed the persisted values, the character list showed the real learned entry (`鍵` / `ㄐㄧㄢˋ` / 6) with its count and status line, the empty phrase list showed its empty message, and the pin and delete buttons stayed disabled while no row was selected.

Installed acceptance through the real macOS input menu — choosing 偏好設定…, changing the Shift side, deleting an entry, and completing an export/import round trip through the file panels — has not been recorded yet.

## Intentional limitations

Preferences are read from the input method's own defaults domain, so a change made while the process is running applies immediately, but an external edit needs `reload()` or a relaunch. The settings window is not localized into English. The lists show every entry with an in-memory filter and no paging, which suits a personal dictionary but is not designed for hundreds of thousands of rows. Import merges and never deletes, so removing an entry that exists only on another Mac still has to be done on both. Export writes a plain JSON file with no encryption; it contains what the user has typed and chosen, so it should be handled like any other personal file.
