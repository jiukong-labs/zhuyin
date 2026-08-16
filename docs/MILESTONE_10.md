# Milestone 10: alternative Zhuyin arrangements

## Goal

Let a user who learned a different Bopomofo keyboard keep their muscle memory, using the extension point `KeyboardLayout` has provided since Milestone 2, without changing composition, conversion, ranking, or punctuation.

This milestone adds only one-to-one arrangements. The ambiguous 26-key arrangements — 倚天26鍵 and 許氏 — are deliberately excluded: they map several symbols onto one key and need per-keystroke disambiguation, which is a different feature from a key table.

## Arrangements

`ZhuyinKeyboardArrangement` is the persisted identity, and each case supplies its layout:

```text
standard  標準（大千）  the arrangement shipped since Milestone 2
eten      倚天傳統      Wade-Giles-like letters, every letter key used once
ibm       IBM           the 37 symbols in Bopomofo order across the rows
```

倚天傳統:

```text
1 ˙   2 ˊ   3 ˇ   4 ˋ   7 ㄑ  8 ㄢ  9 ㄣ  0 ㄤ  - ㄥ  = ㄦ
q ㄟ  w ㄝ  e ㄧ  r ㄜ  t ㄊ  y ㄡ  u ㄩ  i ㄞ  o ㄛ  p ㄆ
a ㄚ  s ㄙ  d ㄉ  f ㄈ  g ㄐ  h ㄏ  j ㄖ  k ㄎ  l ㄌ  ; ㄗ  ' ㄘ
z ㄠ  x ㄨ  c ㄒ  v ㄍ  b ㄅ  n ㄋ  m ㄇ  , ㄓ  . ㄔ  / ㄕ
Space 一聲
```

IBM:

```text
1 ㄅ  2 ㄆ  3 ㄇ  4 ㄈ  5 ㄉ  6 ㄊ  7 ㄋ  8 ㄌ  9 ㄍ  0 ㄎ  - ㄏ
q ㄐ  w ㄑ  e ㄒ  r ㄓ  t ㄔ  y ㄕ  u ㄖ  i ㄗ  o ㄘ  p ㄙ
a ㄧ  s ㄨ  d ㄩ  f ㄚ  g ㄛ  h ㄜ  j ㄝ  k ㄞ  l ㄟ  ; ㄠ
z ㄡ  x ㄢ  c ㄣ  v ㄤ  b ㄥ  n ㄦ  m ˊ   , ˇ   . ˋ   / ˙
Space 一聲
```

Both tables were taken from public descriptions of the arrangements and cross-checked for internal consistency: each covers all 21 initials, 3 medials, 13 finals, and 5 tones exactly once, 倚天 uses every letter key exactly once, and IBM runs the symbols in Bopomofo order. No layout data was copied from another input method's source.

`KeyboardKey` gained `quote` and `equal`, which 倚天 needs. The standard arrangement returns `nil` for both, and its exhaustive switch made that an explicit decision rather than an oversight.

## Interaction with existing behavior

Punctuation is unaffected. Milestone 9 places marks on Shift or on the three keys (`[`, `]`, `\`) that no arrangement uses, so every arrangement offers the same punctuation, and a test asserts that no arrangement claims those keys.

Everything downstream of `BopomofoComponent` is arrangement-independent: parsing, the composition buffer, candidates, ranking, learning, and phrases all work on components and readings, never on key codes.

The arrangement is read from preferences on each key-down. When it differs from the one the current session was built with, the controller finalizes the composition first and then rebuilds the session, so keys already pressed are never reinterpreted under a new table. A change therefore takes effect on the next keystroke in every client, with no restart.

## Automated verification

The suite covers all earlier milestones plus:

- every arrangement covering all 37 symbols and 5 tones with exactly 42 keys;
- no arrangement mapping two keys to the same component;
- control keys and the punctuation keys carrying no component in any arrangement;
- the same syllable composing from each arrangement's own keys;
- 倚天 using every letter key, and IBM running the initials in Bopomofo order;
- arrangement raw values round-tripping through preferences, and an unknown stored value falling back to the standard arrangement without disturbing other settings;
- grave and Tab still resolving to no key at all.

Run:

```sh
xcodegen generate
xcodebuild -project "Jiukong Zhuyin.xcodeproj" -scheme "Jiukong Zhuyin" -configuration Debug -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData test
xcodebuild -project "Jiukong Zhuyin.xcodeproj" -scheme "Jiukong Zhuyin" -configuration Release -destination "generic/platform=macOS" -derivedDataPath .build/DerivedData build
```

On 2026-08-16, Xcode 26.6 with the macOS 26.5 SDK completed all 269 Debug tests with no failures, and the generic Release build produced a universal `arm64`/`x86_64` application. The settings window rendered the new 注音鍵盤配置 pop-up showing the persisted arrangement.

## Installed acceptance results

On 2026-08-16 each arrangement was driven through real `CGEvent` delivery to an isolated TextEdit document, with the persisted arrangement set before the input method process started:

```text
standard   j i 3, Return, Return   → 我
倚天傳統   x o 3, Return, Return   → 我
IBM        s g , , Return, Return  → 我
```

The two new arrangements are confirmed by the difference rather than by the result alone: under the standard arrangement `x o 3` is `ㄌㄟˇ` and `s g ,` is not a syllable at all, so neither could have produced 我 if the table had not actually changed. Switching the preference and restarting the process changed nothing else in the pipeline.

This is a spot check of three keys per arrangement, not a full table audit. The remaining keys must still be confirmed against a physical reference before release, because a wrong key here fails silently: it composes a valid but unintended syllable, which no unit test can detect — the tests assert the table's internal consistency, not its correspondence to a real keyboard.

## Intentional limitations

Only one-to-one arrangements are supported. The 26-key arrangements and any user-defined table are out of scope, as is showing the current arrangement in the input menu. The arrangement is process-wide per preference, not per client.
