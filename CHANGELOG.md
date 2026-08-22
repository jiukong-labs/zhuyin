# Changelog

All notable changes to Jiukong Zhuyin will be documented in this file.

## [Unreleased]

### Added

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
  database formats, and the built-in phrase lexicon, with only the documented
  platform, tooling, and official CNS11643 standard-data exceptions.
- Plain Left/Right revision across uncommitted reading units, with exact
  same-reading character replacement and UTF-16-safe inline focus.
- Original exact phrases for `測試中請稍後` and its useful suffixes, plus
  installed acceptance coverage for uninterrupted six-syllable conversion.
- Text-aware candidate cells that keep long phrase candidates fully visible.
- Explicit Left/Right revision feedback: the focused unit is styled inline and
  identified by position, character, and reading in a candidate-panel header.
- Two-stage revision controls: Left/Right first locate the reading unit, Down
  enters candidate choosing, Left/Right then move the candidate highlight, and
  Escape returns to locating without losing the text focus.
- A character selected and committed once now becomes the first same-reading
  character candidate on the next lookup; the latest choice wins while manual
  pins retain their explicit highest priority.
- Revision candidate numbers 1-9 are now always explicit selections, so a
  number-row Bopomofo key cannot escape the panel and start a stray syllable.
- Ordinary conversion now previews the first candidate inline without opening
  a window. Down explicitly opens the expanded chooser; only then do 1-9 and
  navigation keys select candidates, removing the number/Bopomofo ambiguity.
- Chinese and English are now first-class macOS input modes with original
  template icons, so the existing input-menu icon shows `中` or `英` after a
  Shift language switch.

### Changed

- Windowless candidate preview yields the number row to the next syllable,
  allowing uninterrupted composition across readings that begin on a number
  key; pressing Down makes all displayed `1`–`9` slots explicit selections.
- Return accepts a windowless preview and submits the whole composition in one
  keystroke; Space accepts the first candidate without submitting the buffer.
- Runtime dictionary schema 2 adds first-party exact phrase entries without an
  imported corpus or frequency score.
