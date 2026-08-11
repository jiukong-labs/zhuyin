# Milestone 3: base Chinese character dictionary

## Goal

Convert a completed Zhuyin syllable into base single-character candidates and allow the user to select a character through macOS's native candidate panel. In particular, `ㄨㄛˇ` must offer and select「我」without first committing the literal Bopomofo.

This milestone deliberately does not implement a custom candidate window, phrases, frequency ranking, user learning, or settings.

## Dictionary source and license

The dictionary is generated from the Ministry of Digital Affairs' `CNS11643中文標準交換碼全字庫`, snapshot `20260805`, under Taiwan's Open Government Data License 1.0.

Pinned source inputs:

- [`Properties.zip`](https://www.cns11643.gov.tw/opendata/Properties.zip): SHA-256 `3d56ef14cc8099893245dac58fe4718d2fa64812b9159352a98a4588ad3efa5c`
- [`MapingTables.zip`](https://www.cns11643.gov.tw/opendata/MapingTables.zip): SHA-256 `4502fcf7b433d679dee51127298929543ec7f4aa99be93cd219df1552bc3d2bf`
- [`release.txt`](https://www.cns11643.gov.tw/opendata/release.txt): its hash and archive-version declarations are validated with the parser inputs.
- Each extracted TSV file also has an individual hash in `Data/CNS11643/20260805/manifest.json`.

The upstream `MapingTables.zip` spelling is retained intentionally. The checked-in snapshot makes ordinary builds and verification independent of a mutable download URL. The builder refuses a source file whose hash does not match the manifest.

Only the phonetic property and CNS/Unicode mappings are used. The transformation excludes Unicode private-use scalars, removes duplicate pronunciation/character pairs, and preserves the first official source occurrence as deterministic candidate order. CNS11643 does not publish a candidate frequency field, so this order is not described as frequency ranking.

The generated SQLite artifact contains:

```text
94,708 pronunciation/character entries
76,373 Unicode characters
1,458 pronunciations
13,837 characters with multiple pronunciations
21,981 excluded private-use phonetic rows
560 duplicate pronunciation/character entries removed
```

The artifact SHA-256 produced by the current toolchain is `d7a87a45dcfc665c15653cb21de03802d52e1211454e27f39c35725a3ddaf051`.

See `THIRD_PARTY_NOTICES.md` and the notice bundled beside the runtime database for attribution and license boundaries.

## Build pipeline

`Jiukong Dictionary Builder` is a separate Xcode command-line target. It is not a build phase of the input method and performs no network access.

```sh
./scripts/build-dictionary.sh
```

The command validates every pinned input, strictly parses the TSV rows, builds a temporary database, inserts entries and metadata in one transaction, adds both query indexes, runs `VACUUM` and `PRAGMA integrity_check`, and atomically replaces the output only after success. The runtime opens the result read-only, verifies its `application_id` and schema version, and enables SQLite `query_only`.

Running the builder twice from the same snapshot on the validation machine produced byte-identical database files.

## Runtime behavior

- A tone key completes the syllable and starts dictionary lookup.
- The full reading remains marked while candidates are visible.
- `IMKCandidates` supplies the native single-row candidate UI, paging controls, and mouse callbacks. Public server-first routing lets the controller process arrows, Home/End, Page Up/Page Down, `1`–`9`, Return, Escape, and Backspace deterministically through public candidate-selection APIs.
- A selected candidate is validated against the current snapshot and replaces the marked reading exactly once.
- Client commit, input-source deactivation, and controller closure commit the selected or first candidate.
- Escape or Backspace cancels an active candidate composition.
- Missing/corrupt data, lookup failure, or no candidates falls back to literal Bopomofo; there is no hand-written fallback dictionary.
- Return on an unfinished syllable still commits literal Bopomofo, preserving Milestone 2 behavior.

## Automated verification

The Debug suite covers:

- pinned manifest hashes and exact official snapshot statistics;
- strict malformed-row rejection, CNS/Unicode joining, PUA filtering, and deduplication;
- `ㄨㄛˇ → 我…`, common `ㄐㄧㄢˋ` homophones, empty lookups, and reverse multi-pronunciation lookup for「行」and「樂」;
- SQLite application/schema identity, metadata, and `quick_check`;
- stable candidate snapshots, highlighting, stale-selection rejection, navigation-key routing, nine-item page selection, and shortcut-modifier rejection;
- tone-completion conversion actions and all earlier keyboard/composition behavior.

On 2026-08-11, Xcode 26.6 with the macOS 26.5 SDK completed all 58 Debug tests with no failures. The generic Release build produced a valid ad-hoc-signed universal `arm64`/`x86_64` application, and the bundled database hash matched the checked-in artifact. Xcode emitted only its informational AppIntents metadata warning because this target intentionally has no AppIntents dependency.

Run:

```sh
xcodebuild -project "Jiukong Zhuyin.xcodeproj" -scheme "Jiukong Zhuyin" -configuration Debug -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData test
./scripts/install.sh
```

The installed input method was also exercised end to end in TextEdit with synthetic physical key events and Accessibility reads. These checks reproduce the real `NSEvent → IMKInputController → IMKCandidates → IMKTextInput` path rather than calling the parser directly:

```text
j i 3, Return             → 我
j i 3, Right, Return      → 倭
j i 3, Right × 2, Return  → 婑
j i 3, Right, Left, Return → 我
j i 3, 2                  → 倭
j i 3, Page Down, 1       → 𥑽 (first candidate on the second page)
j i 3, click 倭           → 倭
j i 3, Escape / Backspace → empty text
```

The navigation, page, and number checks were also repeated with only 50 ms between tone completion and selection to cover the candidate-panel visibility race. A human acceptance pass can repeat the same rows and additionally switch input sources with a candidate active; deactivation must commit exactly one highlighted or first candidate.

## Intentional limitations

The candidate UI is Apple's built-in panel. A custom expanded 20–30 item window, custom Down Arrow expansion, positioning refinements, phrase conversion, candidate frequency data, adaptive ordering, user dictionary, alternate layouts, punctuation, Shift language toggle, and settings are future milestones.
