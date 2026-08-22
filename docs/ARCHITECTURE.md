# Architecture

Milestone 11 adds a cursor-following mode indicator while keeping parsing, composition state, ranking, storage, candidate presentation, settings UI, InputMethodKit side effects, and reproducible dictionary tooling separate.

## Process boundary

`main.swift` validates the bundle configuration, creates exactly one `IMKServer`, and starts the AppKit run loop. The bundle is an `LSUIElement` agent, so it can own a nonactivating candidate panel without appearing in the Dock. InputMethodKit creates one `InputController` for each client input session.

`InputController` accepts key-down, modifier-change, and client mouse-down events. Modifier and key events first update the independent `ShiftToggleController`. Shift-arrow phrase selection is routed first. Plain arrows then follow the revision session's explicit mode: Left/Right own the composition cursor while locating a reading unit, Down expands the candidates and enters choosing mode, and the candidate grid owns arrows until Escape collapses it back to locating mode. The routers treat the `.function` and `.numericPad` flags inherent to macOS navigation-key events separately from real Command, Control, Option, and Shift shortcuts. The controller then translates a Chinese-mode key-down into a semantic physical key and asks the syllable session for a result. Converted units remain in `CompositionBuffer`; the controller renders one combined marked snapshot or performs one final `IMKTextInput` commit. English-mode and otherwise unhandled events are returned to the client application after active composition is finalized.

## Composition pipeline

```text
NSEvent key code
  → ShiftToggleController / LanguageModeController
  → MacVirtualKeyResolver
  → KeyboardKey
  → StandardZhuyinLayout
  → BopomofoComponent
  → BopomofoParser / BopomofoSyllable
  → BopomofoInputSession result
  → CompositionBuffer
  → CharacterDictionary lookup
  → UserLearningService character + exact phrase snapshots / CandidateRanker
  → CandidateSession / CandidateCommandReducer
  → InputController / CandidateWindowPresenter
  → IMKTextInput marked text or committed character
```

- `KeyboardLayout` is the arrangement extension point. `ZhuyinKeyboardArrangement` selects between the standard 大千 switch-based layout and the 倚天傳統 and IBM tables, all of them one-to-one; ambiguous 26-key arrangements are out of scope. Everything downstream works on `BopomofoComponent`, never on key codes, so only this layer is arrangement-aware. The controller rebuilds its session after finalizing the composition when the persisted arrangement changes.
- `PunctuationLayout` is a separate pure table over the same physical keys. Bopomofo keys keep their meaning unshifted and carry punctuation on Shift; the three keys the arrangement never uses carry bracket-style marks directly. Caps Lock is ignored, and real shortcut modifiers still pass through.
- `BopomofoSyllable` stores one optional initial, medial, final, and tone. It renders them in canonical order while separately preserving input order for Backspace.
- Horizontal neutral tone is rendered before the syllable body, such as `˙ㄉㄜ`; first tone has no visible mark.
- `BopomofoParser` completes and resets one syllable when a tone arrives.
- Outside candidate mode, `BopomofoInputSession` owns Backspace, Escape, Enter, pass-through, commit, and reset behavior without importing AppKit or InputMethodKit.

A tone-completed syllable remains distinct from forced raw text. The former starts dictionary conversion; Return on an unfinished syllable and pass-through finalization preserve literal Bopomofo as one unlearned buffer unit.

`CompositionBuffer` owns every converted or literal unit not yet inserted into the client. Each unit keeps display text, exact reading, a UUID, and a kind. A punctuation unit shares the buffer, the marked text, and Backspace with converted text but carries no reading: phrase lookups extend only across the trailing run of reading units, and neither a Shift selection nor a phrase candidate may cover a mark. Punctuation therefore never reaches the phrase store as a reading. Candidate selections become pending learning events tied to surviving unit UUIDs. Phrase replacement or Backspace prunes events touching removed units; Escape can discard the buffer without producing learning. A real commit first detaches one immutable snapshot, resets all mutable state, inserts its full text once, and only then records the snapshot's surviving events.

The buffer selection is an end-anchored suffix. Shift+Left expands it one reading unit toward the beginning and Shift+Right shrinks it. Plain Left/Right instead owns a stable reading-unit revision focus while converted text remains uncommitted. It skips punctuation and reopens the exact single-reading candidates with the current character highlighted. A compact revision session is the locating mode: Left/Right changes the focused reading unit and candidate navigation remains dormant. Down expands the session into choosing mode, where arrows move the candidate highlight; Escape restores the current character highlight and returns to locating mode. Revision is also an explicit number-selection context, so every displayed 1-9 slot selects its candidate instead of leaking a number-row Bopomofo body key into a new syllable. A confirmed choice replaces only a validated one-character candidate carrying the same reading, invalidates any pending phrase event that covered an actual replacement, and retains the reading-unit focus after closing the panel. The focus includes its one-based position among reading units and is rendered twice: a yellow/orange attributed-text mark on the exact UTF-16 unit range, plus a mode-aware candidate-panel header containing position, text, reading, and the next available controls. The header remains reliable in clients that visually select the entire marked composition. Accepting the unchanged character is a no-op, so merely inspecting a phrase cannot corrupt its pending learning. Every selection or focus `NSRange` is calculated from unit UTF-16 lengths. Starting a new raw syllable clears the range and returns the caret to the full marked string's UTF-16 end.

## Language mode

Each input controller owns a `ShiftToggleController` for its own modifier gesture, while every controller reads one process-wide `LanguageModeController`. A left or right Shift release toggles only when that Shift was pressed without any intervening key, other modifier, or second Shift. The state machine deliberately has no tap timeout. Its policy models both, left-only, right-only, and disabled behavior; since Milestone 8 the active policy comes from the persisted `ShiftKeyPreference` rather than a fixed value.

A toggle first uses the existing idempotent composition finalization path, then changes mode. Chinese mode continues through candidate and Bopomofo handling. English mode returns key events unchanged, allowing the client and selected macOS keyboard layout to own characters, capitalization, dead keys, repeats, and shortcuts. Mode is shared across client sessions for the lifetime of the input-method process and defaults to Chinese after relaunch.

`CursorIndicatorController` owns the optional persistent indicator that follows the mouse pointer, ported from the separate `lang-cursor` utility without its paid licensing. Because the input method knows its own mode, the indicator is driven by `LanguageModeController` rather than by classifying the system input source, and custom text and color are stored per mode. `CursorIndicatorGeometry` keeps placement, clamping, and easing pure and testable; the panel, its 30 Hz tracking timer, and the 5 Hz Caps Lock poll run only while the indicator is enabled and a client is active. Enabling it suppresses the transient HUD.

`LanguageModeHUD` displays `中` or `A` for 0.75 seconds in a process-wide nonactivating, click-through panel. Presentations and hides are UUID-guarded so delayed timers or lifecycle callbacks from an old client cannot hide a newer indicator.

## Dictionary pipeline

```text
Pinned CNS11643 phonetic and CNS/Unicode TSV files
  → SHA-256 manifest validation
  → strict DictionaryBuilder parsing
  → remove Unicode private-use scalars
  → deduplicate pronunciation/character pairs
                                           ↘
Jiukong first-party phrase TSV
  → strict phrase/readings/duplicate validation
  → exact length-prefixed pronunciation keys
                                           ↗
  → indexed, versioned SQLite artifact (characters + phrases)
  → read-only CharacterDictionary queries at runtime
```

The generated artifact is byte-for-byte reproducible from the pinned character snapshot and checked-in first-party phrase file, so continuous integration rebuilds it on every change and fails if the checked-in database no longer matches its sources. The phrase file is manually authored for Jiukong, has no imported corpus or frequency values, and is governed by the repository's original-implementation policy.

The normal app build never downloads data and never parses raw TSV files. `JiukongDictionaryBuilder` is a separate command-line target. It records the upstream version, source archive hashes, transformation, license, and exact row statistics in the generated database. The runtime validates SQLite `application_id` and `user_version`, opens one full-mutex read-only connection per input controller, and enables `query_only`.

The schema indexes `pronunciation → characters`, `character → pronunciations`, and exact `pronunciation sequence → phrases`. Character order is deterministic CNS source order, not an inferred frequency rank; first-party phrase ties preserve repository file order. Unicode Plane 15 private-use mappings are deliberately excluded because they have no portable character identity or glyph without additional proprietary conventions.

## User learning and ranking

`CharacterCandidateProvider` joins each read-only `DictionaryCharacter` with the matching local `CharacterLearningRecord`, merges exact longest-suffix phrases from the first-party and user dictionaries, then asks `CandidateRanker` for a deterministic ordered snapshot. A phrase candidate replaces the already accepted reading suffix inside `CompositionBuffer`, so a provisional single-character choice can become the complete phrase without touching committed client text. CNS `source_order` and first-party phrase file order remain stable base ranks and are never presented as corpus frequency. Exact phrases use a neutral zero base score so the fixed phrase tier cannot be mistaken for imported frequency data; `baseFrequency` has no corpus-derived value in this project.

Pinned candidates form the highest tier. Within unpinned character candidates, any actually committed selection outranks untouched CNS entries, and the most recently selected learned character comes first; this makes one deliberate choice effective on the next lookup even when its CNS source rank was low. Remaining ties use `-baseRank + 8 × log2(selectionCount + 1) + recency`, where recency starts at 4 and decays with a seven-day half-life, followed by base rank, source order, text, reading, and candidate type. Phrase candidates retain their independent exact-phrase tier. Future timestamps clamp to age zero. The tiers, formula, and tie-breaks live only in `CandidateRanker` and are covered by exact-position tests.

`UserLearningStore` owns a versioned SQLite database under the user Application Support directory. It validates `application_id`, schema version, columns, and regular-file identity before use; enables full-mutex access, a one-second busy timeout, WAL, normal synchronous writes, and foreign keys; and keeps the directory/database at `0700`/`0600`. An atomic UPSERT saturates counts at `Int64.max`, keeps the newest timestamp, and preserves an existing pin. `UserLearningService` serializes process-wide access and logs only generic failures without characters or readings. If storage fails, candidate lookup continues with the untouched CNS order.

## Preferences and settings

`Preferences` is a plain value holding the Shift toggle policy and the automatic-learning switch. Decoding is pure and total: a missing, malformed, or unknown stored value falls back per field to the shipped default, and a version newer than this build is not guessed at. `UserDefaultsPreferencesStore` reads and writes only the namespaced keys this build owns, so nothing else in the domain is misread or destroyed.

`PreferencesController` is the process-wide owner. It caches the decoded value behind a lock so a keystroke never reads `UserDefaults`, persists a change only when it differs, and posts `didChangeNotification` outside the lock so an observer can read `current` while handling it.

Automatic learning gates only implicit recording. Existing counts and pins still rank candidates while it is off, and explicit Shift phrase creation still works, because the user asked for that phrase directly. `UserLearningStore` clears character data, phrase data, or both inside one immediate transaction that revalidates the schema, so the database stays usable without reopening and a failure cannot half-clear the data.

`SettingsWindowController` owns the single settings window for every client session. Because the bundle is an agent, it activates the process explicitly before ordering the window front and deactivates again on close. `InputController.menu()` contributes the input-menu item and finalizes any active composition before the window opens. Four tabs separate general settings, the phrase list, the character list, and data transfer; each `UserDataListController` re-reads its snapshot after every edit so a list can never act on an entry another window already deleted.

`UserDataArchive` is the portable JSON representation of both data sets, with UTC millisecond timestamps and no local row identifiers. Decoding refuses an unreadable file, a foreign format, or a newer version, and otherwise drops only unusable rows while reporting how many. Import merges inside one transaction — larger count, newer timestamp, earlier creation time, combined pin — so it is idempotent, cannot lower a count, and rolls back entirely if one entry cannot be applied.

## Candidate lifecycle

After a tone completes a syllable, `InputController` queries the candidate provider and stores an immutable typed candidate snapshot without showing a window. `CompositionPresentation` applies the highlighted candidate to a copy of the buffer, including phrase suffix replacement, so marked text previews the default conversion without mutating real composition or learning state. Down changes the session to expanded mode and presents the custom panel. A final keyboard or mouse selection is resolved against the current session and inserts exactly one validated candidate into the real buffer.

`CandidateSession` is the canonical pure Swift state model for stable typed-ID deduplication, inline-preview versus visible-panel state, absolute highlight, nine-item selection row, and grid/page navigation. An ordinary compact session is a windowless preview; expanded sessions and compact revision locating sessions are visible. It remains an immutable ordering snapshot: a selection recorded while the panel is open affects only the next lookup. `CandidateCommandRouter` maps one unmodified physical key event to a semantic command; `CandidateCommandReducer` turns that command and session into a state update or a typed candidate plus explicit commit reason. `InputController` clears the session before inserting and recording one selection, preventing reentrant lifecycle callbacks from counting twice. Missing data, a failed lookup, or an empty candidate result falls back to committing literal Bopomofo; there is no hidden hand-written dictionary.

`CandidateWindowPresenter` is a process-wide coordinator that owns the single AppKit panel and mouse callbacks; multiple client controllers can never leave multiple candidate windows on screen. A new owner first asks the previous owner to finalize its candidate session, then replaces the panel snapshot. Its borderless `NSPanel` cannot become key or main, and is shown without activating the input-method process, so keyboard focus remains in the client. Ordinary conversion does not call the presenter until Down expands the snapshot into a nine-column, three-row viewport for up to 27 simultaneous candidates. Compact layout remains available for the visible revision-locating panel. Candidate columns are measured from their own text, with each expanded-grid column adopting the widest cell in that column, so a multi-character phrase remains visible without overlapping its neighbors. Expanded snapshots larger than the viewport become scrollable, and every keyboard highlight is scrolled into view. Mouse callbacks carry the session UUID and absolute index, while hide requests are owner-token guarded, so an old controller cannot click or dismiss a newer session's panel.

Four arrows, Home/End, Page Up/Page Down, top-row `1`–`9`, Space, Return/Keypad Enter, Escape, and Backspace all enter through the same router. During a windowless inline preview, only Down, Space, Escape, and Backspace stay in candidate routing. Number and navigation commands bypass it: the controller first accepts the preview and then sends the same physical key into the next syllable or normal buffer handling. Return similarly accepts the preview and commits the whole buffer in one keystroke. Down expands the panel into fully explicit selection mode, where every `1`–`9` selects from the highlighted nine-item row and arrows navigate the grid. Space accepts candidate zero; an empty numeric slot is consumed without mutation. Candidate-mode Backspace restores the completed `BopomofoSyllable`, removes its last input component (normally the tone, including invisible first tone), hides the window, and resumes marked-text editing. Escape from an ordinary expanded panel collapses to the inline preview; a second Escape discards that pending syllable. Lifecycle callbacks commit through one idempotent path.

Panel placement uses the text client's public marked/selected ranges and candidate anchor rectangles. Sizing and placement are pure geometry: choose the display containing or nearest the caret, use its current `visibleFrame`, prefer below the caret, flip above when necessary, then clamp width and height inside an inset frame. Coordinates do not assume the primary display begins at `(0, 0)`, so negative-origin displays are supported. The panel level is the client window level plus one, as required for a custom input-method candidate window.

## InputMethodKit boundary

Active composition is sent with `setMarkedText`; its caret range is relative to the supplied UTF-16 string. Literal Bopomofo or a selected candidate is sent once with `insertText`. Escape from an expanded ordinary chooser returns to its inline preview, while Escape on that preview clears the completed reading; candidate Backspace updates it with the restored incomplete reading. Raw-syllable Escape and Backspace-to-empty use the same empty marked string. The controller does not call `cancelComposition`, whose framework behavior is restoration rather than discard.

Client-driven commit, input-source change notification or deactivation, palette hiding, and controller closure all use the same idempotent session finalization path. The public distributed source-change notification is registered for immediate delivery and only finalizes after the current source identifier confirms a switch away from Jiukong.

Milestone 5 must recognize `flagsChanged`, so InputMethodKit no longer provides its key-down-only default mouse finalization. The controller explicitly recognizes client left/right/other mouse-down events, resets a pending Shift gesture, finalizes active composition once, and returns the mouse event to the client. No global event monitor or Accessibility-based document reading is used.

## Installed acceptance

`Tools/AcceptanceHarness` is a separate command-line target that drives the installed bundle through real `CGEvent` delivery to its own TextEdit instance, then restores the previous input source. It exists because no unit test can reach the InputMethodKit event path.

Two rules in it are load-bearing. The system's own Zhuyin input method composes identical Bopomofo from identical keys, so every run must complete a probe syllable, press Down, and identify Jiukong's own candidate panel by window owner or abort; without that check a run that never reached this input method looks like a pass. And because a running application keeps the input source it already adopted, the harness selects the source first and then launches a new client instance rather than trying to convert an existing one.

## Continuous integration

The Xcode project is checked in so the repository builds without XcodeGen, which means a file added to disk but not to the project is compiled by nobody and tested by nobody. `scripts/check-project-sources.sh` fails on exactly that, and it gates the GitHub Actions build, which then runs the Debug suite, produces a universal Release binary, and verifies the architectures. It also builds the acceptance harness, which cannot run there but must not rot against the sources it drives. A second job rebuilds the dictionary from its pinned snapshot and requires the checked-in artifact to be unchanged. A third job regenerates the project from `project.yml` and reports any difference, kept advisory because XcodeGen formatting can change between releases.

## Configuration

`InputMethodConfiguration` validates the connection name and bundle identifier before server startup. Its Foundation-only implementation can be tested without starting an input method or hosting an AppKit application.

The bundle metadata declares:

- an `LSUIElement` macOS agent that can present UI while staying out of the Dock;
- the InputMethodKit connection and Objective-C controller class names;
- the Traditional Chinese intended language and repertoire;
- one stable Text Input Sources parent with Chinese and English modes;
- a localized English and Traditional Chinese display name.

Each language mode has its own first-party template icon (`中` or `英`). Shift
selects the corresponding mode through Text Input Sources, so macOS updates its
existing input-menu icon without adding a duplicate application status item.

The bundle identifier is not free-form. Text Input Sources only creates an input source when the identifier contains an `inputmethod` component that is not the last one, and only while no other bundle claims the same identifier in LaunchServices. Both failures are silent: `TISRegisterInputSource` returns `noErr` and the source simply never appears. `tw.idv.jiukong.inputmethod.zhuyin` satisfies the first; the second is a workflow hazard, because every build registers another copy of the same identifier under `.build`.

Milestones 1–3 used `LSBackgroundOnly`. Milestone 4 replaces it with `LSUIElement` because AppKit defines a background-only application as unable to create windows, while an agent application may present the custom nonactivating panel and remain absent from the Dock. The two keys are never declared together.

The current application-bundle lifecycle was also compared with [McBopomofo](https://github.com/openvanilla/McBopomofo/tree/73d0379eca621377fb46416ceb4a7dc9bb576d47) and [OpenVanilla](https://github.com/openvanilla/openvanilla/tree/8f09dc6a66f10aecfdc928e7ff63753d7bc19b25). Only their public architecture was studied; no source code or language data was copied.

A punctuation candidate window, a half-width/full-width toggle, and user-remappable symbol tables remain outside the current milestone. Those modules will not be placed in `InputController`.
