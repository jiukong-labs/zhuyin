# Changelog

All notable changes to Jiukong Zhuyin will be documented in this file.

## [Unreleased]

### Added

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
