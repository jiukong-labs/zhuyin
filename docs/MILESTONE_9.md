# Milestone 9: Chinese punctuation

## Goal

Type the full-width punctuation Traditional Chinese writing needs without leaving Chinese mode, without disturbing any Bopomofo key, and without inventing a reading for a mark that has none.

This milestone does not add a punctuation candidate window, a half-width/full-width toggle, symbol tables beyond the marks listed here, or a settings page for remapping them.

## Key arrangement

Every Zhuyin key keeps its Bopomofo meaning unshifted, so punctuation that shares a key sits on Shift. The three keys the Taiwan standard arrangement never uses carry the bracket-style marks directly:

```text
Shift+,  ，      Shift+.  。      Shift+/  ？      Shift+;  ：
Shift+1  ！      Shift+6  …       Shift+9  （      Shift+0  ）
Shift+-  —
[  「            ]  」            \  、
Shift+[  『      Shift+]  』      Shift+\  ／
```

`…` and `—` are inserted one at a time, so the conventional `……` and `——` are two keypresses. `\` carries 、 because the arrangement never uses that key and the mark is needed constantly; `Shift+\` produces ／. Anything not in this table is still returned to the client application, so the current macOS keyboard layout keeps producing ordinary ASCII, and English mode is unaffected.

`PunctuationLayout` is a pure table keyed by physical key and Shift state, in the same `KeyboardKey` domain as `StandardZhuyinLayout`. `KeyboardKey` gained `leftBracket`, `rightBracket`, and `backslash`; the Zhuyin layout returns `nil` for them, and its exhaustive switch makes that explicit rather than implicit.

Caps Lock does not change Bopomofo input, so it does not change punctuation either. Command, Control, Option, and Function still pass their shortcuts through untouched.

## Composition behavior

Punctuation ends the active reading without ending the composition. On a punctuation key the controller accepts the highlighted candidate or the raw syllable into the buffer, then appends the mark as one more unit:

```text
ㄨㄛˇ → 我 (candidate)   Shift+,   →   我，          still marked, not committed
```

The commit reason for the implicitly accepted candidate is `.punctuation`, which learns like any other real insertion, because the user did choose that candidate before typing the mark.

`CompositionUnit` now carries a `Kind`. A punctuation unit occupies the buffer, participates in the marked text and its UTF-16 caret, and is removed by Backspace like any other unit, but it carries no reading. Two consequences are enforced by the model rather than by the controller:

- `phraseLookupQueries` only extends across the trailing run of reading units, so no lookup ever contains a mark, and the phrase store is never asked to encode a non-Bopomofo reading;
- `selectedPhrase` and `containsExactSuffix` reject any range covering punctuation, so a Shift selection spanning a mark cannot create a user phrase and a phrase candidate cannot replace a suffix containing one.

Readings before a mark are unaffected: `「久空` still offers 久空 as a phrase.

## Automated verification

The suite covers all earlier milestones plus:

- the complete punctuation table, both Shift states, and the absence of a mark for every letter, control key, and unshifted Zhuyin key;
- Bopomofo meanings surviving for every key that also carries punctuation;
- virtual key codes resolving for the three added keys;
- every produced mark being exactly one non-ASCII character;
- punctuation joining the buffer without a reading, being committed with the rest of the composition, and being deleted by Backspace;
- phrase lookup stopping at punctuation, phrase candidates refusing a suffix containing one, Shift selections across a mark producing no phrase, and phrases before a mark still working;
- the marked caret and presentation staying correct in UTF-16 with punctuation present.

Run:

```sh
xcodegen generate
xcodebuild -project "Jiukong Zhuyin.xcodeproj" -scheme "Jiukong Zhuyin" -configuration Debug -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData test
xcodebuild -project "Jiukong Zhuyin.xcodeproj" -scheme "Jiukong Zhuyin" -configuration Release -destination "generic/platform=macOS" -derivedDataPath .build/DerivedData build
```

On 2026-08-16, Xcode 26.6 with the macOS 26.5 SDK completed all 258 Debug tests with no failures, and the generic Release build produced a universal `arm64`/`x86_64` application.

## Installed acceptance results

On 2026-08-16 the installed Release bundle was driven through real `CGEvent` delivery to isolated TextEdit documents, with each run first proving that the client was routing keys through Jiukong rather than the system's own Zhuyin input method:

```text
j i 3, Shift+comma, j i 3, Return, Return   → 我，我
[ , j i 3, ] , \ , Return                   → 「我」、
```

Both confirm the intended composition behavior: `Shift+,` accepted the highlighted candidate on its own before inserting the mark, the unshifted bracket and backslash keys produced full-width marks instead of ASCII, and the whole run — converted text and punctuation together — reached the client as one commit on Return.

Typing each remaining mark, and confirming that English mode still yields ASCII for these keys, has not been recorded yet.

## Intentional limitations

The table is fixed in this build; remapping and a symbol picker are not part of it. `『』` require Shift while `「」` do not, matching the arrangement's spare keys rather than any single vendor's layout. Because the marks live in the same buffer as converted text, a composition containing punctuation is still committed as one insertion, which some clients will treat as a single undo step.
