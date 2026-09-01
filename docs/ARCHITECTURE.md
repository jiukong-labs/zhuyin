# Architecture

Milestone 11 adds a cursor-following mode indicator while keeping parsing, composition state, ranking, storage, candidate presentation, settings UI, InputMethodKit side effects, and reproducible dictionary tooling separate.

## Process boundary

`main.swift` validates the bundle configuration, creates exactly one `IMKServer`, and starts the AppKit run loop. The bundle is an `LSUIElement` agent, so it can own a nonactivating candidate panel without appearing in the Dock. InputMethodKit creates one `InputController` for each client input session.

`InputController` accepts key-down, modifier-change, and client mouse-down events. Modifier and key events first update the independent `ShiftToggleController`. Shift-arrow phrase selection is routed first. Plain arrows then follow the revision session's explicit mode: Left/Right positions a windowless caret at every displayed-unit boundary, including either side of punctuation, Backspace restores the immediately preceding reading's exact pronunciation and removes its final Bopomofo component, forward Delete does the same to the focused reading immediately after the caret, Down opens candidates for the reading immediately before the caret and enters choosing mode, and Up or Escape closes them and returns to text positioning. The routers treat the `.function` and `.numericPad` flags inherent to macOS navigation-key events separately from real Command, Control, Option, and Shift shortcuts. The controller then translates a Chinese-mode key-down into a semantic physical key and asks the syllable session for a result. Converted units remain in `CompositionBuffer`; the controller renders one combined marked snapshot or performs one final `IMKTextInput` commit. English-mode and otherwise unhandled events are returned to the client application after active composition is finalized.

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

`CompositionBuffer` owns every converted or literal unit not yet inserted into the client. Each unit keeps display text, exact reading, a UUID, and a kind. A punctuation unit shares the buffer, marked text, Backspace, and caret boundaries with converted text but carries no reading. A selected or queried user phrase may include supported punctuation as literal output units; its `PhraseOutputPattern` records which text units consume readings and which reproduce punctuation. Candidate selections become pending learning events tied to surviving unit UUIDs. Phrase replacement or Backspace prunes events touching removed units; Escape can discard the buffer without producing learning. A real commit first detaches one immutable snapshot, resets all mutable state, inserts its full text once, and only then records the snapshot's surviving events.

The buffer phrase selection is a contiguous displayed-unit range. Shift+Left extends its left edge and Shift+Right extends its right edge. With no selection or revision focus, Shift+Left starts at the last reading while Shift+Right starts at the first. Plain Left/Right owns a stable caret boundary while converted text remains uncommitted; the first Shift+Left in windowless locating mode selects up to two adjacent readings before that boundary, while Shift+Right selects up to two after it. Selection edges can include adjacent supported punctuation; Return records either at least two readings or one reading accompanied by punctuation. Phrase range is authoritative in the buffer and reinforced with exact background and underline attributes, but the client receives a collapsed caret after the range so web-backed text fields cannot relocate the composition cursor. The same token-guarded nonactivating panel frames the exact range text with `【】` and shows its reading and text-unit counts, expansion keys, and whether Return can record it, so the target remains explicit even when a client ignores marked-text styling. After a successful Return save, the panel identifies the exact stored text for ten seconds and exposes a nonactivating `×` button. Its immutable confirmation token carries both text and the full reading sequence, so deletion targets only that user-phrase identity and never edits the already committed client text. Plain revision navigation stores only the unit following the caret, with a separate active state representing the text end, and performs no candidate query. Down derives a distinct candidate target from the adjacent reading before that caret and creates a compact nine-candidate choosing session; a second Down expands it to the full grid. While choosing, Left/Right changes the candidate highlight, and Up or Escape discards only the candidate session, leaving the caret anchor unchanged. Number keys are explicit candidate selections only while that panel exists. A confirmed choice replaces only the target before the caret, preserves the caret anchor, and invalidates any pending phrase event that covered an actual replacement. The target includes its one-based position among reading units, while the independent caret is sent as a collapsed UTF-16 selection throughout positioning and choosing. Revision marked text uses Carbon's explicit `kTSMHiliteNoHilite` style plus transparent background and underline attributes, while the zero-length selection identifies the blinking insertion caret. Accepting the unchanged character is a no-op, so merely inspecting a phrase cannot corrupt its pending learning. Starting a new raw syllable clears the range and returns the caret to the full marked string's UTF-16 end.

Deletion has its own early composition route. When a revision focus or phrase
range exists, deletion runs before candidate-window handling. Backspace removes
the reading immediately before the focused unit, reconstructs its stored
pronunciation in canonical initial–medial–final–tone input order, removes the
tone, and keeps the resulting raw reading before the unchanged focus. It does
nothing when there is no immediately preceding reading and never crosses
punctuation. Further Backspaces use the normal parser path to remove the final,
medial, and initial in turn. Forward Delete applies the same restoration and
component deletion to the reading immediately after the caret, preserving its
original position before the following unit or at the buffer end. Repeating
either physical key continues editing that restored raw reading. A phrase range
remains the explicit target for either key. With no explicit target, the
existing syllable, candidate, buffer, or client behavior continues unchanged.

## Language mode

Each input controller owns a `ShiftToggleController` for its own modifier gesture, while every controller reads one process-wide `LanguageModeController`. A left or right Shift release toggles only when that Shift was pressed without any intervening key, other modifier, or second Shift. The state machine deliberately has no tap timeout. Its policy models both, left-only, right-only, and disabled behavior; since Milestone 8 the active policy comes from the persisted `ShiftKeyPreference` rather than a fixed value.

A toggle first uses the existing idempotent composition finalization path, then calls `TISSelectInputSource` for the other Jiukong mode. This keeps the process-wide language state and the macOS input-menu icon synchronized, while allowing macOS to present its native transient input-source indicator. Chinese mode continues through candidate and Bopomofo handling. English mode returns key events unchanged, allowing the client and selected macOS keyboard layout to own characters, capitalization, dead keys, repeats, and shortcuts. Selecting a Jiukong mode directly from the macOS input menu follows the same synchronization path. A new process defaults to Chinese.

`CursorIndicatorController` owns the optional persistent indicator that follows the mouse pointer, ported from the separate `lang-cursor` utility without its paid licensing. Because the input method knows its own mode, the indicator is driven by `LanguageModeController` rather than by classifying the system input source, and custom text and color are stored per mode. `CursorIndicatorGeometry` keeps placement, clamping, and easing pure and testable; the panel, its 30 Hz tracking timer, and the 5 Hz Caps Lock poll run only while the indicator is enabled and a client is active. Standalone Shift updates this existing indicator directly and does not present a second transient boxed `中` or `A` HUD.

`UpdateController` performs one silent first-party update check at process
startup when the persisted 24-hour interval is due, then re-evaluates that
schedule hourly while the process remains alive. It accepts only the latest
published, non-prerelease GitHub release with the expected package and
checksum asset names and repository-scoped HTTPS URLs. Network and JSON work
never blocks input handling. The current result is exposed to the dynamically
built input-source menu and Update settings pane; only a user-initiated check
shows a modal result. Installation remains outside the input method and uses
the signed, notarized system-level package.

## Dictionary pipeline

```text
Pinned CNS11643 phonetic and CNS/Unicode TSV files
  → SHA-256 manifest validation
  → strict DictionaryBuilder parsing
  → remove Unicode private-use scalars
  → deduplicate pronunciation/character pairs
                                           ←
Jiukong first-party character TSV
  → strict character/reading/duplicate validation
  → reuse the character's pinned CNS code and source position
                                           ↘
Jiukong first-party phrase TSV
  → strict phrase/readings/duplicate validation
  → exact length-prefixed pronunciation keys
                                           ↗
MOE 《成語典》 government-sourced idiom TSV (all 1,642 主條 four-character entries)
  → same strict phrase/readings/duplicate validation
  → merged with the first-party phrase TSV; rejects a cross-source duplicate
                                           ↗
MOE 《重編國語辭典修訂本》 four-character phrase TSV (33,295 entries)
  → same strict phrase/readings/duplicate validation
  → merged in turn; rejects a cross-source duplicate against either source above
                                           ↗
MOE common/semi-common standard character tables
  → strict one-character-per-line parsing; reject cross-table duplicates
                                           ↘
Jiukong first-party heteronym tier overrides
  → strict (character, reading, tier) validation
  → verified against the merged character snapshot
                                           ↗
  → exact character-reading attestations from first-party phrases only
Jiukong first-party default-selection TSVs
  → validate every row against an already accepted character/phrase identity
  → discard runtime-only timestamps, pins, IDs, and sync state at capture time
  → indexed, versioned SQLite artifact (characters + phrases + usage tiers + attestations)
  → read-only CharacterDictionary queries at runtime
```

The generated artifact is byte-for-byte reproducible from the pinned character snapshot; the checked-in Jiukong first-party character, phrase, and heteronym-tier files; and the approved MOE idiom, revised-dictionary, and character-tier files, so continuous integration rebuilds it on every change and fails if the checked-in database no longer matches its sources. The Jiukong character, phrase, and heteronym-override files are authored specifically for this project with no imported corpus; the MOE tables are verbatim government standard-table promulgations rather than a private corpus or another input method's frequency table. The approved government phrase exceptions are closed and source-verbatim: the idiom TSV holds all 1,642 主條 (main-entry) four-character idioms from the Ministry of Education's copyrighted (CC BY-ND) 《成語典》, and the revised-dictionary TSV holds 33,295 validated four-character entries from the same Ministry's separate, general-purpose 《重編國語辭典修訂本》. Both retain only the headword and reading fields verbatim and discard every other field; see `Data/MOEIdioms/README.md`, `Data/MOERevisedDictionary/README.md`, and `THIRD_PARTY_NOTICES.md` for scope, attribution, and license reasoning. The repository policy still forbids any unapproved dataset, another input method's implementation or language data, and private-corpus frequency data.

The normal app build never downloads data and never parses raw TSV files. `JiukongDictionaryBuilder` is a separate command-line target. It records the upstream version, source archive hashes, transformation, license, and exact row statistics in the generated database. The runtime validates SQLite `application_id` and `user_version`, opens one full-mutex read-only connection per input controller, and enables `query_only`.

The schema indexes `pronunciation → characters`, `character → pronunciations`, and exact `pronunciation sequence → phrases`. Each character-reading row also stores how many exact occurrences it has in Jiukong's manually authored phrase TSV and its first-party default selection count; phrase rows store the corresponding default count. A default-ranking row must already exist in the merged dictionary, so ranking data cannot add a candidate. Government-sourced idiom and revised-dictionary entries remain excluded from phrase-attestation counts. A reviewed first-party reading reuses that character's pinned CNS source position, and first-party phrase ties preserve repository file order. Unicode Plane 15 private-use mappings are deliberately excluded because they have no portable character identity or glyph without additional proprietary conventions.

## User learning and ranking

`CharacterCandidateProvider` joins each read-only `DictionaryCharacter` with the matching local `CharacterLearningRecord`, merges exact longest-suffix phrases from the first-party lexicon, approved government datasets, and user dictionary, applies the selected CNS repertoire scope and its injected displayability predicate, then asks `CandidateRanker` for a deterministic ordered snapshot. Each dictionary entry exposes its plane parsed from the official `cns_code`: general mode admits planes 1 and 2, while the persisted rare-candidate option also admits later planes. Production then uses `CandidateTextDisplayability`, which checks each composed character against Core Text's system-font cascade and rejects LastResort missing-glyph fallbacks in either scope. Filtering happens before inline preview, numbering, and panel layout. A phrase candidate replaces the already accepted reading suffix inside `CompositionBuffer`, so a provisional single-character choice can become the complete phrase without touching committed client text.

Each character candidate's `baseFrequency` starts with `2 − usage_tier + count / (count + 1)`: MOE's 常用/次常用/其他 three-tier classification, per (character, reading) once a manually reviewed heteronym override is applied on top of the character-wide MOE tier, plus the exact first-party phrase-attestation count described above. It then adds the logarithmic bonus from the captured first-party default selection count. Personal selection frequency and recency remain separate candidate fields, so a fresh user choice immediately wins the character-selection tier and pins remain absolute. Exact phrases use the same default-count bonus on top of their phrase tier; when several exact suffixes match, longer phrases remain ahead of shorter ones before frequency is compared. This is project-owned usage data, not an imported corpus or another input method's frequency list.

Pinned candidates form the highest tier. Among exact phrase matches, the longest pronunciation sequence comes first. Within unpinned character candidates, any actually committed selection outranks untouched dictionary entries; learned characters are ordered by selection count descending, then by most recent selection when their counts are equal. This makes one deliberate choice effective on the next lookup while allowing repeated choices to establish a stable order. Remaining character ties and phrase scoring use `baseFrequency + 8 × log2(selectionCount + 1) + recency`; `baseFrequency` contains the immutable dictionary baseline and falls back to `-baseRank` only when absent. Recency starts at 4 and decays with a seven-day half-life, followed by base rank, source order, text, reading, and candidate type. Phrase candidates retain their independent exact-phrase tier. Future timestamps clamp to age zero. The tiers, formula, and tie-breaks live only in `CandidateRanker` and are covered by exact-position tests.

`UserLearningStore` owns a versioned SQLite database under the user Application Support directory. It validates `application_id`, schema version, columns, and regular-file identity before use; enables full-mutex access, a one-second busy timeout, WAL, normal synchronous writes, and foreign keys; and keeps the directory/database at `0700`/`0600`. An atomic UPSERT saturates counts at `Int64.max`, keeps the newest timestamp, and preserves an existing pin. `UserLearningService` serializes process-wide access and logs only generic failures without characters or readings. If storage fails, candidate lookup continues with the immutable built-in default ranking.

`UserDataCloudSyncCoordinator` is an asynchronous layer beside, not inside, the SQLite lookup path. Successful service mutations append coalesced upsert or deletion intents to a private JSON journal and schedule background work. `CloudKitUserDataTransport` fetches a custom zone in the current user's private database, maps each normalized logical identity to an opaque SHA-256 record name, and stores personal fields through `CKRecord.encryptedValues`. A first sync applies remote records and tombstones before marking the local store as migrated; later syncs retain pending local decisions while merging monotonic counts and timestamps. Input activation provides a rate-limited pull, while local edits use a short upload debounce. The local database remains fully usable when the account, entitlement, network, or CloudKit service is unavailable. See `docs/CLOUD_SYNC.md` for the record model and production-signing boundary.

## Preferences and settings

`Preferences` is a plain value holding the Shift toggle policy, automatic-learning switch, iCloud-sync switch, candidate-repertoire scope, keyboard arrangement, and cursor-indicator configuration. Rare candidates default off and iCloud learning sync defaults on; a missing or malformed stored value therefore stays on CNS planes 1 and 2 while allowing a clean Mac to restore learning at first launch. Decoding is pure and total: every other missing, malformed, or unknown stored value likewise falls back per field to the shipped default, and a version newer than this build is not guessed at. `UserDefaultsPreferencesStore` reads and writes only the namespaced keys this build owns, so nothing else in the domain is misread or destroyed.

`PreferencesController` is the process-wide owner. It caches the decoded value behind a lock so a keystroke never reads `UserDefaults`, persists a change only when it differs, and posts `didChangeNotification` outside the lock so an observer can read `current` while handling it.

Automatic learning gates only implicit recording. Existing counts and pins still rank candidates while it is off, and explicit Shift phrase creation still works, because the user asked for that phrase directly. `UserLearningStore` clears character data, phrase data, or both inside one immediate transaction that revalidates the schema, so the database stays usable without reopening and a failure cannot half-clear the data.

`SettingsWindowController` owns the single settings window for every client session. Because the bundle is an agent, it activates the process explicitly before ordering the window front and deactivates again on close. `InputController.menu()` contributes the input-menu item and finalizes any active composition before the window opens. Five tabs separate general settings, the cursor indicator, the phrase list, the character list, and data transfer with iCloud status; each `UserDataListController` re-reads its snapshot after every edit so a list can never act on an entry another window already deleted.

`UserDataArchive` is the portable JSON representation of both data sets, with UTC millisecond timestamps and no local row identifiers. Decoding refuses an unreadable file, a foreign format, or a newer version, and otherwise drops only unusable rows while reporting how many. Import merges inside one transaction — larger count, newer timestamp, earlier creation time, combined pin — so it is idempotent, cannot lower a count, and rolls back entirely if one entry cannot be applied.

## Candidate lifecycle

After a tone completes a syllable, `InputController` queries the candidate provider and stores an immutable typed candidate snapshot without showing a window. `CompositionPresentation` applies the highlighted candidate to a copy of the buffer, including phrase suffix replacement, so marked text previews the default conversion without mutating real composition or learning state. Down changes the session to expanded mode and presents the custom panel. A final keyboard or mouse selection is resolved against the current session and inserts exactly one validated candidate into the real buffer.

`CandidateSession` is the canonical pure Swift state model for stable typed-ID deduplication, inline-preview versus visible-panel state, absolute highlight, nine-item selection row, and grid/page navigation. Ordinary compact conversion is a windowless preview; revision positioning has no candidate session at all. Down creates a visible compact revision-choosing session, and a second Down expands it. The candidate order remains an immutable snapshot: a selection recorded while the panel is open affects only the next lookup. `CandidateCommandRouter` maps one unmodified physical key event to a semantic command; `CandidateCommandReducer` turns that command and session into a state update or a typed candidate plus explicit commit reason. `InputController` clears the session before inserting and recording one selection, preventing reentrant lifecycle callbacks from counting twice. Missing data, a failed lookup, or an empty candidate result falls back to committing literal Bopomofo; there is no hidden hand-written dictionary.

`CandidateWindowPresenter` is a process-wide coordinator that owns the single AppKit panel and mouse callbacks; multiple client controllers can never leave multiple candidate windows on screen. A new owner first asks the previous owner to finalize its candidate session, then replaces the panel snapshot. Its borderless `NSPanel` cannot become key or main, and is shown without activating the input-method process, so keyboard focus remains in the client. Ordinary conversion does not call the presenter until Down expands the snapshot into a nine-column, three-row viewport for up to 27 simultaneous candidates. Revision positioning also avoids the presenter; its first Down opens a compact nine-candidate row, and its second Down expands the grid. Candidate columns are measured from their own text, with each expanded-grid column adopting the widest cell in that column, so a multi-character phrase remains visible without overlapping its neighbors. Expanded snapshots larger than the viewport become scrollable, and every keyboard highlight is scrolled into view. Mouse callbacks carry the session UUID and absolute index, while hide requests are owner-token guarded, so an old controller cannot click or dismiss a newer session's panel.

Four arrows, Home/End, Page Up/Page Down, top-row `1`–`9`, Space, Return/Keypad Enter, Escape, and Backspace all enter through the same router. During a windowless inline preview, only Down, Space, Escape, and Backspace stay in candidate routing. Number and navigation commands bypass it: the controller first accepts the preview and then sends the same physical key into the next syllable or normal buffer handling. Return similarly accepts the preview and commits the whole buffer in one keystroke. Down expands the panel into fully explicit selection mode, where every `1`–`9` selects from the highlighted nine-item row and arrows navigate the grid. Space accepts candidate zero; an empty numeric slot is consumed without mutation. Candidate-mode Backspace restores the completed `BopomofoSyllable`, removes its last input component (normally the tone, including invisible first tone), hides the window, and resumes marked-text editing. Escape from an ordinary expanded panel collapses to the inline preview; a second Escape discards that pending syllable. Lifecycle callbacks commit through one idempotent path.

With a positioned revision caret, Down opens candidates for the reading immediately before the caret. The absolute start boundary is the deliberate exception: because no reading exists on its left, Down targets the first reading immediately to its right. An interior caret never crosses punctuation to find a target.

Panel placement uses the text client's public marked/selected ranges and candidate anchor rectangles. Sizing and placement are pure geometry: choose the display containing or nearest the caret, use its current `visibleFrame`, prefer below the caret, flip above when necessary, then clamp width and height inside an inset frame. Coordinates do not assume the primary display begins at `(0, 0)`, so negative-origin displays are supported. The panel level is the client window level plus one, as required for a custom input-method candidate window. `CandidateAnchorValidation` guards every candidate anchor rect the same way `LanguageModeHUD` already avoids trusting one: some web-backed clients cannot report a real caret and instead return a rect inside a small corner band or tens of thousands of points beyond every real display, either of which would otherwise pin the panel far from the editor. Placement tries the marked and selected ranges, macOS 14's visible-selection rectangle, and the line height beside the current caret. If those fail, it reuses a valid caret captured before marked text began or the client's most recent click before using the current mouse position as the final fallback.

Candidate provenance remains explicit after ranking: exact records loaded from the user phrase store carry `isUserPhrase`, while first-party phrases and character candidates do not. The candidate grid reserves a trailing `×` slot only for those user records. Clicking it asks `InputController` to delete the exact text-and-ordered-pronunciation identity, then rebuilds the live snapshot from the provider so a matching built-in phrase can remain as a normal non-deletable candidate.

## InputMethodKit boundary

Active composition is sent with `setMarkedText`; its caret range is relative to the supplied UTF-16 string. Ordinary composition carries both an explicit green underline and Carbon's converted-text style, so clients that discard attributed-string visuals can still render their native composition marker. Revision positioning deliberately keeps Carbon's no-highlight style. Literal Bopomofo or a selected candidate is sent once with `insertText`. Escape from an expanded ordinary chooser returns to its inline preview, while Escape on that preview clears the completed reading; candidate Backspace updates it with the restored incomplete reading. Raw-syllable Escape and Backspace-to-empty use the same empty marked string. The controller does not call `cancelComposition`, whose framework behavior is restoration rather than discard.

Client-driven commit, input-source change notification or deactivation, palette hiding, and controller closure all use the same idempotent session finalization path. The public distributed source-change notification is registered for immediate delivery and only finalizes after the current source identifier confirms a switch away from Jiukong.

Milestone 5 must recognize `flagsChanged`, so InputMethodKit no longer provides its key-down-only default mouse finalization. The controller explicitly recognizes client left/right/other mouse-down events, resets a pending Shift gesture, finalizes active composition once, and returns the mouse event to the client. Standalone Shift tracking records `CGEventSourceCounterForEventType` at Shift-down and compares it at Shift-up; this catches a real chord even when a client such as Word delivers the modifier release to InputMethodKit before the modified key-down callback. It is a read-only WindowServer counter and requires neither a global event monitor nor Accessibility-based document reading.

## Installed acceptance

`Tools/AcceptanceHarness` is a separate command-line target that drives the installed bundle through real `CGEvent` delivery to its own TextEdit instance, then restores the previous input source. It exists because no unit test can reach the InputMethodKit event path.

Two rules in it are load-bearing. The system's own Zhuyin input method composes identical Bopomofo from identical keys, so every run must complete a probe syllable, press Down, and identify Jiukong's own candidate panel by window owner or abort; without that check a run that never reached this input method looks like a pass. And because a running application keeps the input source it already adopted, the harness selects the source first and then launches a new client instance rather than trying to convert an existing one.

## Continuous integration

The Xcode project is checked in so the repository builds without XcodeGen, which means a file added to disk but not to the project is compiled by nobody and tested by nobody. `scripts/check-project-sources.sh` fails on exactly that, and it gates the GitHub Actions build, which then runs the Debug suite, produces a universal Release binary, and verifies the architectures. It also builds the acceptance harness, which cannot run there but must not rot against the sources it drives. The Harness is the single owner of its default release manifest; CI runs `scripts/check-acceptance-matrix.sh` against the built executable so Option, Shift, composition, candidate, revision, punctuation, and phrase-selection scenarios cannot silently leave that manifest. A second job rebuilds the dictionary from its pinned snapshot and requires the checked-in artifact to be unchanged. A third job regenerates the project from `project.yml` and reports any difference, kept advisory because XcodeGen formatting can change between releases.

## Configuration

`InputMethodConfiguration` validates the connection name and bundle identifier before server startup. Its Foundation-only implementation can be tested without starting an input method or hosting an AppKit application.

The bundle metadata declares:

- an `LSUIElement` macOS agent that can present UI while staying out of the Dock;
- the InputMethodKit connection and Objective-C controller class names;
- the Traditional Chinese intended language and repertoire;
- one stable Text Input Sources parent with Chinese and English modes;
- a localized English and Traditional Chinese display name.

Each language mode has its own first-party color icon (red `中` or blue `A`).
Direct menu selection and standalone Shift switching both select the concrete
mode so the macOS input-menu icon reflects the active language.

The bundle identifier is not free-form. Text Input Sources only creates an input source when the identifier contains an `inputmethod` component that is not the last one, and only while no other bundle claims the same identifier in LaunchServices. Both failures are silent: `TISRegisterInputSource` returns `noErr` and the source simply never appears. `tw.idv.jiukong.inputmethod.zhuyin` satisfies the first; the second is a workflow hazard, because every build registers another copy of the same identifier under `.build`.

Milestones 1–3 used `LSBackgroundOnly`. Milestone 4 replaces it with `LSUIElement` because AppKit defines a background-only application as unable to create windows, while an agent application may present the custom nonactivating panel and remain absent from the Dock. The two keys are never declared together.

The current application-bundle lifecycle was also compared with [McBopomofo](https://github.com/openvanilla/McBopomofo/tree/73d0379eca621377fb46416ceb4a7dc9bb576d47) and [OpenVanilla](https://github.com/openvanilla/openvanilla/tree/8f09dc6a66f10aecfdc928e7ff63753d7bc19b25). Only their public architecture was studied; no source code or language data was copied.

A punctuation candidate window, a half-width/full-width toggle, and user-remappable symbol tables remain outside the current milestone. Those modules will not be placed in `InputController`.
