# Changelog

All notable changes to Jiukong Zhuyin will be documented in this file.

## [Unreleased]

### Added

- Built-in phrases can now be removed from the candidate window. Every phrase
  candidate carries the inline `×`; removing one records the deletion in the
  user's own database rather than editing the bundled dictionary, so a
  dictionary shipped with a later update cannot bring the phrase back and a
  personal word list keeps converging on what someone actually types. Single
  characters remain non-deletable, since removing one could leave a reading
  with no candidate at all.
- A new 「已刪除內建詞」 settings tab lists every removed built-in phrase and
  restores them one at a time; 「恢復內建詞…」 in the data tab restores all of
  them, and 「清除全部」 does too. Removals synchronize through iCloud as their
  own record kind and travel with a JSON export, so neither another Mac nor a
  restored backup resurrects a deleted phrase.
- A shareable word list. 「匯出詞庫…」 writes a phrase pack one person can hand
  to another: their own phrases and which built-in phrases they removed, with
  no selection counts, timestamps, or pins. The bundled dictionary is not
  copied into a pack — both Macs ship the identical lexicon — so the file
  stays small and the recipient's list matches the sender's. 「匯入詞庫…」
  merges a pack without lowering a count or clearing a pin the recipient set,
  and applying the sender's removals is a separate opt-out.

### Changed

- The user database schema is now version 4. The upgrade adds the removed
  built-in phrase table in place and leaves existing selection counts and user
  phrases untouched.

## [0.1.14] - 2026-09-04

### Fixed

- Backspacing a positioned caret's revised character all the way down to
  nothing no longer leaves every further Backspace silently swallowed; it now
  resumes deleting the reading before it, as usual.

## [0.1.13] - 2026-09-03

### Fixed

- Shift plus a letter now commits the uppercase Latin letter directly instead
  of relying on the client to handle a separately redelivered key event. On
  some clients that redelivery raced the just-finished composition's commit,
  landing the letter away from the caret instead of right after it.
- An already-accepted phrase from the dictionary or the user's own word list
  no longer gets split apart by a later homophone. For example, completing
  「室友」and then typing 「有沒有」stopped turning it into 「室有沒有」— 「友」
  and 「有」share a reading, and continued typing could previously re-segment
  back across the settled phrase and overwrite part of it.

## [0.1.11] - 2026-09-01

### Fixed

- The input method now declares its Chinese and English modes once through
  `ComponentInputModeDict`, preventing System Settings from accumulating
  duplicate 久空中文 or 久空英文 entries.

## [0.1.10] - 2026-09-01

### Fixed

- macOS can now cold-launch the input method server by using the recognized
  `_1_Connection` service-name form. This fixes an input source that appeared
  selected but did not receive keyboard events.
- Installed-input acceptance now proves that keys reached Jiukong through its
  unique Option-ASCII behavior instead of mistaking the cursor indicator for
  the candidate panel.

## [0.1.9] - 2026-09-01

### Fixed

- Ordinary composition now obtains its clause attributes through
  InputMethodKit's `markForStyle` API instead of storing a Carbon highlight
  constant directly as a clause identifier.

## [0.1.8] - 2026-09-01

### Fixed

- Ordinary composition now includes the system converted-text style as a
  fallback for web-backed input fields that ignore the explicit green
  underline attributes.

## [0.1.7] - 2026-08-31

### Fixed

- The installer now stops the cached pre-update input-method process before
  replacing the bundle and once more afterward. This prevents an older
  process from handling the installation's CloudKit cache-reset notification
  and turning off iCloud sync before the updated account check can run.

## [0.1.6] - 2026-08-31

### Added

- Typing `ㄊㄧˋ` now offers 「剔」 as a selectable character candidate.
- Learned characters and phrases in Data settings can be sorted by text,
  pronunciation, selection count, or pinned state.

### Fixed

- Spurious CloudKit account-change notifications after an update or reinstall
  no longer disable sync when the active Apple Account is unchanged; a genuine
  account switch still turns sync off and requires fresh consent.

## [0.1.5] - 2026-08-31

### Added

- User-created phrases can include supported Chinese punctuation while
  preserving the exact reading-to-output mapping.
- Pinned candidates display `★ ×` in the candidate panel; clicking `×`
  removes only the pin and keeps the learned selection count.

### Changed

- Same-reading characters sort by explicit pin, selection count descending,
  recency for equal counts, and finally the built-in deterministic order.
- User-learning schema v3 stores phrase output patterns and migrates existing
  schema v2 phrases without losing readings or usage metadata.

### Changed

- Ordinary marked-text composition now requests a transparent background and
  green underline across applications; explicit phrase selection still uses
  the selected-text highlight.

### Added

- The built-in updater can now download the release package and checksum,
  verify SHA-256, the expected Developer ID Installer team, and Gatekeeper
  acceptance, then open the verified package in macOS Installer. System
  administrator approval remains required for `/Library/Input Methods`.
- The public Installer completion screen now explicitly reminds users to save
  their work, then sign out of macOS and sign back in or restart the Mac after
  every install or update, so the cached input-method process is refreshed.
- A project-owned default selection ranking captured from the maintainer's
  current Jiukong history: 804 character-reading rows (7,066 selections) and
  385 already-present built-in phrase rows (2,277 selections). The checked-in
  source omits private timestamps, pins, identifiers, sync state, and every
  phrase absent from the existing built-in dictionaries; personal learning
  continues to layer on top.
- First-party automatic update checks for complete stable GitHub Releases,
  limited to once per day and surfaced through the input-source menu and
  Update settings pane without sending input or learning data.
- A release-blocking installed input-behavior matrix now covers Option ASCII,
  Shift language round trips, active-composition finalization, candidates,
  revision, punctuation, and phrase selection; CI locks its required manifest.
- Developer ID signing, CloudKit production export, notarization, stapling,
  checksum, and signed installer-package release tooling, including a guarded
  GitHub Actions workflow that uploads only to an existing draft release.
- The application bundle now carries the project license, consolidated
  third-party notices, and the source-verbatim MOE dictionary usage notes.
- Chinese mode now supports Option+A–Z for lowercase ASCII letters and
  Option+Shift+A–Z for uppercase letters, alongside Option+0–9 digits.
- The General settings pane now explains the Option ASCII shortcuts and
  pass-through behavior beside the Shift language-toggle setting.
- Offline-first iCloud CloudKit synchronization for character learning and
  user phrases, including encrypted record fields, deterministic opaque IDs,
  first-launch restoration, persistent offline mutations, deletion
  tombstones, conflict merging, rate-limited refresh, settings status, and a
  manual sync action.
- User-recorded phrase candidates now show a clickable `×` that deletes that
  exact text-and-pronunciation record and refreshes the open candidate panel.
  The delete control is visually separated from the phrase; built-in phrases
  and individual characters remain non-deletable there.
- Native macOS InputMethodKit application skeleton.
- Local build, test, install, registration, and uninstall workflow.
- Milestone 1 architecture and installation documentation.
- Complete Taiwan standard Zhuyin physical-key mapping.
- Structured Bopomofo initial, medial, final, tone, and syllable parsing.
- Inline marked-text composition with tone and Enter commit behavior.
- Backspace, Escape, lifecycle finalization, and safe pass-through handling.
- Milestone 2 architecture, usage, and verification documentation.
- Reproducible CNS11643 DictionaryBuilder with pinned source hashes and provenance.
- Versioned read-only SQLite dictionary with pronunciation and reverse-character indexes.
- Strict first-party phrase TSV validation and exact pronunciation-sequence index.
- Original starter phrase lexicon, including continuous conversion of `ㄘㄜˋ ㄕˋ` to「測試」.
- A manually authored 815-entry everyday phrase foundation covering
  conversation, time, people, daily life, travel, work, learning, computing,
  descriptions, health, and weather, with pinned CNS character-reading checks.
- Base single-character candidates through the native InputMethodKit candidate panel.
- Candidate selection, cancellation, lifecycle finalization, and raw-Bopomofo fallback.
- Milestone 3 dictionary, licensing, architecture, and verification documentation.
- Custom nonactivating candidate window with compact and 27-item expanded views.
- Centralized candidate commands for grid navigation, paging, number selection, confirmation, cancellation, and editing.
- Scrollable candidate presentation with caret-relative, screen-aware boundary placement.
- Candidate Backspace restoration and Milestone 4 architecture and verification documentation.
- Token-guarded single-panel ownership across clients and deterministic finalization on input-source changes.
- Standalone left/right Shift detection with chord rejection and process-wide Chinese/English mode.
- Direct English-mode event pass-through and a token-guarded, click-through transient mode HUD.
- Explicit InputMethodKit modifier and client mouse-event handling with composition-safe finalization.
- Milestone 5 architecture, verification, and installed TextEdit acceptance documentation.
- Versioned private SQLite storage for per-reading character counts, recency, and pins.
- Centralized deterministic candidate ranking with logarithmic learning and seven-day recency decay.
- Typed immutable candidate snapshots and explicit commit-reason learning across keyboard, mouse, and lifecycle paths.
- Safe base-order fallback, atomic concurrent updates, schema/file validation, and Milestone 6 verification documentation.
- Multi-character marked composition with UTF-16-safe Shift range selection and buffer editing.
- Exact, longest-suffix user-phrase creation and conversion without reading committed client text.
- SQLite schema v2 phrase storage with ordered readings and lossless Milestone 6 migration.
- Deferred character and phrase learning that records only content surviving the final client commit.
- Milestone 7 composition-buffer, phrase-storage, and verification documentation.
- Persistent preferences with per-field fallback and a process-wide cached controller.
- Selectable left/right/both/disabled Shift language switching.
- Automatic-learning switch that stops new counting without discarding existing ranking data.
- Atomic clearing of character learning, user phrases, or all local user data.
- Traditional Chinese settings window opened from the macOS input menu.
- Searchable character and phrase management lists with per-entry pinning and deletion.
- Versioned JSON export and idempotent, transactional import of local user data.
- Milestone 8 preferences, settings, management, and verification documentation.
- Full-width Chinese punctuation on Shift plus the three keys the Zhuyin arrangement leaves free.
- Reading-free punctuation units that never join a user phrase or a phrase lookup.
- Milestone 9 punctuation and verification documentation.
- Selectable 倚天傳統 and IBM Bopomofo arrangements beside the standard one.
- Live arrangement switching that finalizes the composition before rebuilding the session.
- Milestone 10 arrangement and verification documentation.
- GitHub Actions workflow running tests, a universal Release build, and dictionary reproducibility.
- Source-membership check that fails when a Swift file is missing from the checked-in Xcode project.
- Repeatable installed-acceptance harness that drives the installed bundle and proves which input method composed the text.
- Optional cursor-following mode indicator with placement, tracking, size, Caps Lock badge, and per-mode text and color, ported from the lang-cursor utility.
- Milestone 11 cursor-indicator and verification documentation.
- Permanent original-implementation policy for product code, algorithms, UI,
  database formats, and the first-party phrase lexicon, with closed,
  documented exceptions for platform/tooling, official CNS11643 data, MOE
  standard character tables, and the pinned MOE four-character phrase data.
- Plain Left/Right revision across uncommitted reading units, with exact
  same-reading character replacement and UTF-16-safe inline focus.
- Original exact phrases for `測試中請稍後` and its useful suffixes, plus
  installed acceptance coverage for uninterrupted six-syllable conversion.
- Text-aware candidate cells that keep long phrase candidates fully visible.
- Explicit Left/Right revision feedback through a collapsed text caret; the
  positioning stage is windowless and sends transparent marked-text styling.
- Two-stage revision controls: Left/Right first position a persistent caret,
  Down opens candidates for the character immediately before it, Left/Right
  then move the candidate highlight, and Up or Escape returns without moving
  or expanding that caret into a text selection.
- A character selected and committed once now becomes the first same-reading
  character candidate on the next lookup; the latest choice wins while manual
  pins retain their explicit highest priority.
- Revision candidate numbers 1-9 become explicit selections only after Down
  opens the panel, so hidden positioning never selects an unseen candidate.
- Revision Backspace now restores the character immediately before the focus
  and deletes its tone, final, medial, and initial components one press at a
  time; forward Delete does the same to the character immediately after the
  caret. Revision focus now uses the client's blinking caret without a colored
  character background or underline.
- Standalone Shift detection now also checks WindowServer's key-down counter,
  so clients that deliver Shift-up before the modified key cannot turn
  `Shift+9` into a language toggle and Chinese full-width parenthesis.
- Ordinary conversion now previews the first candidate inline without opening
  a window. Down explicitly opens the expanded chooser; only then do 1-9 and
  navigation keys select candidates, removing the number/Bopomofo ambiguity.
- Chinese and English are first-class macOS input modes with original color
  icons showing red `中` and blue `A` when selected from the input menu.
- Shift-Left and Shift-Right can now start phrase selection from the currently
  located reading and extend the matching left or right edge; revision locating
  no longer consumes those gestures without feedback.
- Phrase selection now draws its exact range itself and gives clients a
  collapsed marked-text caret, preventing web-backed fields from displaying a
  two-character phrase range as a full-composition selection.
- A persistent, nonactivating phrase-range status now shows the exact selected
  text and length after every Shift-arrow, including in clients that ignore
  marked-text colors entirely.
- Backspace and forward Delete now edit the readings on the left and right of
  the explicitly located revision caret, or remove an active phrase range,
  before candidate-window routing.

### Changed

- Disabling iCloud sync now cancels in-flight CloudKit operations without
  clearing pending local mutations. Changing the active Apple Account also
  turns sync off until the user explicitly enables it again.
- CI now overrides development-team and entitlement settings for reproducible
  ad-hoc builds, and temporary `/tmp` diagnostics now use privacy-protected
  unified logging.
- Standalone Shift updates the persistent cursor indicator without showing a
  second short-lived boxed `中` or `A` HUD.
- Down Arrow at a revision caret positioned before the first composition
  character now opens candidates for that first character; other caret
  positions continue to target the reading immediately to the left.
- Candidate anchors reject the corner-band and far-outside-screen rectangles
  returned by some web-backed editors. Placement also tries the modern
  visible-selection rect, preserves a valid caret captured before marked text
  begins, and remembers the client's last click before falling back to the
  current mouse position.
- Duplicate Shift-down modifier events from web-backed editors no longer
  imitate a Shift release or switch languages before the key is released.
- Positioned Shift-arrow phrase selection now treats the caret as a true text
  boundary, so Shift-Left selects readings before it and Shift-Right selects
  readings after it.
- Default character candidates now use exact character-reading attestations
  from Jiukong's manually authored phrase lexicon within each commonness tier;
  government-sourced phrase data is excluded and CNS order remains the final
  fallback.
- Rare `食／ㄧˋ` and `射／ㄧˋ` readings are reviewed per-reading overrides,
  without changing their everyday pronunciations.
- Standalone Shift now changes language inside Jiukong and presents its own
  cursor-matched red `中`／blue `A` HUD beside the pointer, avoiding both
  macOS's fixed `ABC` overlay and invalid client coordinates at screen edges.
- Windowless candidate preview yields the number row to the next syllable,
  allowing uninterrupted composition across readings that begin on a number
  key; pressing Down makes all displayed `1`–`9` slots explicit selections.
- Return accepts a windowless preview and submits the whole composition in one
  keystroke; Space accepts the first candidate without submitting the buffer.
- Runtime dictionary schema 2 adds first-party exact phrase entries without an
  imported corpus or frequency score.

### Fixed

- Manual iCloud synchronization now preempts a stalled automatic attempt,
  permits cellular-network access, uses user-initiated CloudKit operations,
  and reports a clear timeout after one retry instead of waiting indefinitely.
- Left and Right now stop at both sides of punctuation inside an uncommitted
  composition instead of skipping the mark while positioning the revision
  caret.
