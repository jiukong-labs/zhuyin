# Changelog

All notable changes to Jiukong Zhuyin will be documented in this file.

## [Unreleased]

### Added

- Private CloudKit snapshot sync for learned characters and exact user phrases, with automatic reinstall restoration.
- iCloud sync preference, live status, manual synchronization, account-change handling, and conflict retry.
- Apple Development signing, CloudKit container entitlements, and CI-safe ad-hoc signing overrides.

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
