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
- Milestone 8 preferences, settings, and verification documentation.
