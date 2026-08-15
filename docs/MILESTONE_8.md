# Milestone 8: preferences and settings

Milestone 8 is delivered in two phases. Phase A, described here, adds persistent
preferences, the settings window, the automatic-learning switch, and user-data
clearing. Phase B will add the user-dictionary management list and
import/export.

## Goal

Let the user change how the input method behaves and remove what it has learned, without ever letting a settings failure interfere with typing. A malformed or unreadable preference must degrade to the shipped default rather than block input, and clearing data must never leave the database half-emptied.

Phase A does not add the phrase management list, import/export, punctuation mapping, or per-entry pin editing.

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

## Settings window

`InputController.menu()` contributes 偏好設定… to the macOS input menu. Choosing it finalizes any active composition first, so no marked text is stranded in a client that is about to lose focus.

`SettingsWindowController` owns one window for the whole process. The bundle is an `LSUIElement` agent, so the process is activated explicitly before the window is ordered front and deactivated when it closes; the window is kept, not released, so reopening restores its position. It offers the Shift side pop-up, the automatic-learning checkbox, and three clear buttons. Every clear is confirmed by an alert that names exactly what will be deleted and states that it cannot be undone, and a failed clear reports that the existing data was kept.

The window is Traditional Chinese only for now, matching the bundle's development region.

## Automated verification

The suite covers all earlier milestones plus:

- default preferences for an empty domain, per-field fallback for malformed and unknown values, wrong-type isolation, boolean spellings, missing version, and refusal to guess a future or invalid version;
- a persisted round trip for every Shift side, version stamping, preservation of unrelated keys, rejection of unnamespaced keys, and manually written defaults;
- controller caching, single persist and single notification per real change, no write or notification for an unchanged update, observer reads during the notification, `reload()` after an external edit, and concurrent readers and writers converging on one saved value;
- automatic learning off for every commit reason, for both character and phrase candidates, while ranking and explicit phrase creation still work;
- clearing characters only, phrases only with their ordered readings, and both; schema, application ID, table set, and further writes surviving a clear; ranking returning to base CNS order after a clear; and failure reporting without storage.

Run:

```sh
xcodegen generate
xcodebuild -project "Jiukong Zhuyin.xcodeproj" -scheme "Jiukong Zhuyin" -configuration Debug -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData test
xcodebuild -project "Jiukong Zhuyin.xcodeproj" -scheme "Jiukong Zhuyin" -configuration Release -destination "generic/platform=macOS" -derivedDataPath .build/DerivedData build
```

On 2026-08-15, Xcode 26.6 with the macOS 26.5 SDK completed all 222 Debug tests with no failures, and the generic Release build produced a strict-code-signature-valid universal `arm64`/`x86_64` application with no warnings.

The settings window itself is AppKit UI and stays outside the unit-test target, like the candidate panel and the mode HUD. For local verification the executable accepts a maintainer-only argument that shows the same window without starting an input session:

```sh
"$(pwd)/.build/DerivedData/Build/Products/Debug/Jiukong Zhuyin.app/Contents/MacOS/Jiukong Zhuyin" --settings
```

On 2026-08-15 that window rendered correctly in dark appearance at 460 points wide, with all three sections, the pop-up showing the persisted side policy, and the checkbox reflecting the persisted learning state.

Installed acceptance through the real macOS input menu — choosing 偏好設定…, changing the Shift side, and confirming a clear — has not been recorded yet.

## Intentional limitations

Preferences are read from the input method's own defaults domain, so a change made while the process is running applies immediately, but an external edit needs `reload()` or a relaunch. The settings window is not localized into English. Pins can be set through the store and honored by the ranker, but there is still no list to manage them. Phase B adds the user-dictionary management list, per-entry deletion and pinning, and import/export.
