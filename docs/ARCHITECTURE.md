# Architecture

Milestone 3 adds a reproducible character dictionary and system candidate presentation while keeping native macOS APIs, composition logic, and data tooling separate.

## Process boundary

`main.swift` validates the bundle configuration, creates exactly one `IMKServer`, and starts the background AppKit run loop. InputMethodKit creates one `InputController` for each client input session.

`InputController` accepts key-down events that belong to the current composition. Candidate mode first routes selection and navigation keys, treating the `.function` and `.numericPad` flags inherent to macOS navigation-key events separately from Command, Control, Option, and Shift shortcuts. Outside candidate mode, the controller translates an `NSEvent` into a semantic physical key, asks the composition session for a result, then performs the requested `IMKTextInput` marked-text update or commit. Unhandled events are returned to the client application.

## Composition pipeline

```text
NSEvent key code
  → MacVirtualKeyResolver
  → KeyboardKey
  → StandardZhuyinLayout
  → BopomofoComponent
  → BopomofoParser / BopomofoSyllable
  → BopomofoInputSession result
  → CharacterDictionary lookup
  → CandidateSession
  → InputController / IMKCandidates
  → IMKTextInput marked text or committed character
```

- `KeyboardLayout` is the extension point for a future keyboard arrangement. Milestone 2 provides only `StandardZhuyinLayout`.
- `BopomofoSyllable` stores one optional initial, medial, final, and tone. It renders them in canonical order while separately preserving input order for Backspace.
- Horizontal neutral tone is rendered before the syllable body, such as `˙ㄉㄜ`; first tone has no visible mark.
- `BopomofoParser` completes and resets one syllable when a tone arrives.
- Outside candidate mode, `BopomofoInputSession` owns Backspace, Escape, Enter, pass-through, commit, and reset behavior without importing AppKit or InputMethodKit.

A tone-completed syllable remains distinct from a forced raw-text commit. The former starts dictionary conversion; Return on an unfinished syllable and pass-through finalization retain the Milestone 2 raw Bopomofo behavior.

## Dictionary pipeline

```text
Pinned CNS11643 phonetic and CNS/Unicode TSV files
  → SHA-256 manifest validation
  → strict DictionaryBuilder parsing
  → remove Unicode private-use scalars
  → deduplicate pronunciation/character pairs
  → indexed, versioned SQLite artifact
  → read-only CharacterDictionary queries at runtime
```

The normal app build never downloads data and never parses raw TSV files. `JiukongDictionaryBuilder` is a separate command-line target. It records the upstream version, source archive hashes, transformation, license, and exact row statistics in the generated database. The runtime validates SQLite `application_id` and `user_version`, opens one full-mutex read-only connection per input controller, and enables `query_only`.

The schema indexes both `pronunciation → characters` and `character → pronunciations`. Candidate order is deterministic CNS source order, not an inferred frequency rank. Unicode Plane 15 private-use mappings are deliberately excluded because they have no portable character identity or glyph without additional proprietary conventions.

## Candidate lifecycle

After a tone completes a syllable, `InputController` queries the dictionary and stores an immutable candidate snapshot before asking `IMKCandidates` to update. The reading stays as marked text. A final candidate callback validates the value against that snapshot and inserts exactly one character, replacing the marked reading.

`CandidateSession` is a pure Swift state model for stable deduplication, highlight tracking, and stale-selection rejection. `SystemCandidatePresenter` is the small InputMethodKit adapter. Missing data, a failed lookup, or an empty candidate result falls back to committing literal Bopomofo; there is no hidden hand-written dictionary.

The built-in single-row `IMKCandidates` panel owns presentation, paging controls, and mouse callbacks. Its public server-first routing attribute lets the controller handle keyboard interaction deterministically: arrows, Home/End, and Page Up/Page Down update the session highlight through `candidateStringIdentifier` and `selectCandidate(withIdentifier:)`; `1`–`9` select from the immutable session snapshot page that contains the current highlight, and an empty final-page slot is consumed without changing the composition. Escape and Backspace cancel. Return, client-driven commit, input-source deactivation, and controller closure commit the highlighted or first candidate through one idempotent path.

## InputMethodKit boundary

Active composition is sent with `setMarkedText`; its caret range is relative to the supplied UTF-16 string. Literal Bopomofo or a selected candidate is sent once with `insertText`. Candidate-mode Escape or Backspace clears the complete marked reading; raw-syllable Escape and Backspace-to-empty use the same empty marked string. The controller does not call `cancelComposition`, whose framework behavior is restoration rather than discard.

Client-driven commit, input-source deactivation, and controller closure all use the same idempotent session finalization path. The controller keeps InputMethodKit's default key-down-only recognized event mask.

## Configuration

`InputMethodConfiguration` validates the connection name and bundle identifier before server startup. Its Foundation-only implementation can be tested without starting an input method or hosting an AppKit application.

The bundle metadata declares:

- a background-only macOS application that stays out of the Dock;
- the InputMethodKit connection and Objective-C controller class names;
- the Traditional Chinese intended language and repertoire;
- a stable Text Input Sources identifier;
- a localized English and Traditional Chinese display name.

Milestone 1 uses `LSBackgroundOnly` because it is the configuration explicitly listed by Apple's current `IMKServer` initializer documentation. A later milestone can reassess the process policy when settings or other app-owned UI are introduced. `LSBackgroundOnly` and `LSUIElement` are not declared together.

The current application-bundle lifecycle was also compared with [McBopomofo](https://github.com/openvanilla/McBopomofo/tree/73d0379eca621377fb46416ceb4a7dc9bb576d47) and [OpenVanilla](https://github.com/openvanilla/openvanilla/tree/8f09dc6a66f10aecfdc928e7ff63753d7bc19b25). Only their public architecture was studied; no source code or language data was copied.

The custom expandable candidate panel, phrase conversion, frequency ranking, user learning, punctuation, and settings remain outside Milestone 3. Those modules will not be placed in `InputController`.
