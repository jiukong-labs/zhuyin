# Milestone 6: local character learning

## Goal

Remember real candidate selections across applications and input-method restarts, then raise frequently and recently selected characters without changing an already visible candidate window. All learning stays on this Mac and failure of the user database must never prevent ordinary CNS character conversion.

This milestone does not add multi-character composition, phrase creation, a settings window, import/export, punctuation mapping, or a pin-management UI.

## Candidate model and ranking

`Candidate` carries a stable typed identity, text, pronunciation sequence, CNS source order and base rank, optional base frequency, user count, last-used time, pin, and character/phrase type. Milestone 6 supplies only single-character candidates. The optional frequency field remains `nil`: CNS source order is deterministic provenance, not a licensed frequency corpus.

`CandidateRanker` applies one frozen policy:

```text
base score    = -baseRank
user bonus    = 8 × log2(selectionCount + 1)
recency bonus = 4 × 0.5 ^ (age / 7 days)
score         = base score + user bonus + recency bonus
```

Pinned entries form a separate tier above every unpinned entry. Future timestamps use age zero. Equal scores fall back to base rank, source order, text, reading, and type. With the current CNS snapshot, `鍵` begins at position 23 for `ㄐㄧㄢˋ`; immediate selection counts 1, 2, 3, and 4 move it deterministically to positions 12, 7, 4, and 1.

`CharacterCandidateProvider` performs the dictionary/learning join. `CandidateSession` stores the resulting typed array as an immutable snapshot, so a write caused by the current selection is visible on the next reading without moving buttons under the pointer.

## Learning policy

Every path that actually inserts a candidate records it once:

- Space and Return/Keypad Enter;
- a valid top-row 1–9 selection;
- a candidate-window mouse click;
- implicit pass-through finalization;
- lifecycle/source-switch/Shift-toggle finalization;
- handoff of the process-wide candidate window to another client.

The controller clears candidate ownership before `insertText` and records only after insertion. Reentrant lifecycle callbacks therefore see no active candidate and cannot double-count it. Escape, Backspace, navigation, an empty numeric slot, raw Bopomofo fallback, and English-mode events do not learn.

## Persistent store

The user database is:

```text
~/Library/Application Support/JiukongZhuyin/user.sqlite
```

It uses SQLite `application_id = 0x4A5A5955` (`JZYU`) and schema version 1:

```sql
CREATE TABLE character_learning (
    pronunciation TEXT NOT NULL,
    character TEXT NOT NULL,
    selection_count INTEGER NOT NULL DEFAULT 0,
    last_selected_at INTEGER,
    pinned INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (pronunciation, character)
) WITHOUT ROWID;
```

Timestamps are UTC Unix milliseconds. Selection writes use one conflict UPSERT that saturates at `Int64.max`, retains the newest timestamp, and leaves a pin intact. A pin operation can create a zero-count row, allowing the Milestone 8 UI to pin a dictionary character without pretending it was selected.

The directory and database use `0700` and `0600` permissions. Before opening, the store rejects symbolic links and non-regular database paths. Existing files with a foreign application ID, a newer schema, or malformed columns are reported without replacement. Connections use full mutex, a one-second busy timeout, WAL, normal synchronous writes, and foreign keys. `UserLearningService` shares one serialized store across every InputMethodKit client and emits only generic error messages; no character or pronunciation is logged.

## Automated verification

The suite covers all prior milestones plus:

- exact ranking positions, logarithmic bonus, recency half-life, future clocks, pins, and deterministic ties;
- dictionary source-order metadata and base-order fallback;
- all candidate commit reasons, malformed identities, and active-snapshot stability;
- database identity/version/schema, WAL, permissions, reopen persistence, pronunciation isolation, timestamp monotonicity, count saturation, and pin preservation;
- concurrent writers with exact atomic counts;
- safe version-zero migration and rejection of wrong, future, malformed, symbolic-link, and non-regular database files;
- process-wide serialized service access and unavailable/throwing-store fallback.

Run:

```sh
xcodebuild -project "Jiukong Zhuyin.xcodeproj" -scheme "Jiukong Zhuyin" -configuration Debug -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData test
xcodebuild -project "Jiukong Zhuyin.xcodeproj" -scheme "Jiukong Zhuyin" -configuration Release -destination "generic/platform=macOS" -derivedDataPath .build/DerivedData build
```

On 2026-08-15, Xcode 26.6 with the macOS 26.5 SDK completed all 144 Debug tests with no failures. Static analysis succeeded, and the generic Release build produced a strict-code-signature-valid universal `arm64`/`x86_64` application. The installed executable matched that Release build byte for byte (SHA-256 `49841b460f284bf84e716d1cd8f6597bbb56c1d3d0206b179f4e58e924b9da9a`). Xcode emitted only its informational AppIntents metadata warning because this target intentionally has no AppIntents dependency.

Installed acceptance used a new UUID-named TextEdit document and left an existing TextEdit process and document untouched. For `ㄐㄧㄢˋ`, the candidate `鍵` moved from position 23 to 12, 7, 4, and 1 after four selections; the persisted count advanced exactly from 1 through 4. A fifth Space selection inserted only `鍵` and advanced the count to 5. Escape cancellation and English-mode `ru04 ` pass-through left the count unchanged. After restarting the input-method process, `鍵` remained first and the next selection advanced its count to 6. The database retained application ID `0x4A5A5955`, schema version 1, WAL mode, and `WITHOUT ROWID`; the directory was `0700` and the database, WAL, and shared-memory files were `0600`.

The forced process-restart test deliberately exercised a crash/reconnect boundary. Two keys typed immediately while InputMethodKit relaunched passed through to TextEdit; normal conversion resumed once the service was ready, and no learning data was lost. Ordinary source switching and lifecycle finalization remain covered by the installed Milestone 4 and 5 acceptance runs.

## Intentional limitations

Automatic character learning is fixed on for Milestone 6. Pinning exists in the schema and ranker but has no UI yet. Milestone 7 adds internal multi-character composition and user phrases; Milestone 8 adds learning settings, pin management, import/export, and data clearing.
