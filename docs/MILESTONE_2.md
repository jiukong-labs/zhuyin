# Milestone 2: standard Zhuyin keyboard

## Goal

Accept Taiwan standard Zhuyin physical keys in the installed macOS input method, display the current syllable as inline marked text, and commit literal Bopomofo when the user enters a tone or presses Enter.

This milestone deliberately does not contain a Chinese character dictionary or candidate window.

## Implemented behavior

- Complete 42-key standard mapping: 21 initials, 3 medials, 13 finals, and 5 tones.
- Independent keyboard layout, Bopomofo parser, syllable model, and composition session.
- Canonical syllable rendering, including an omitted first-tone mark and a leading horizontal neutral-tone mark.
- Input-order-aware Backspace, Escape discard, Return and keypad Enter commit.
- Pass-through for empty control keys, unmapped keys, and Command／Control／Option／Shift／Fn combinations.
- InputMethodKit marked-text updates with a UTF-16 caret range and final commits through public `IMKTextInput` methods.
- Idempotent composition finalization for client commit, input-source deactivation, and controller closure.

## Verification

Automated checks cover the complete physical-key mapping, all component groups and tones, canonical rendering, both required example syllables, replacement, Backspace including out-of-order input, Escape, Return, keypad Enter, empty-state pass-through, and commit-before-pass-through.

Run:

```sh
xcodebuild -project "Jiukong Zhuyin.xcodeproj" -scheme "Jiukong Zhuyin" -configuration Debug -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData test
./scripts/install.sh
```

Manual TextEdit checks after selecting **久空輸入法**:

```text
j i 3       → ㄨㄛˇ
r u 0 4     → ㄐㄧㄢˋ
2 k 7       → ˙ㄉㄜ
1 Enter     → ㄅ
q Enter     → ㄆ
a Enter     → ㄇ
z Enter     → ㄈ
```

Validated on macOS 26.5.2 with Xcode 26.6 and the macOS 26.5 SDK. The Debug suite passes with no compiler warnings, and the Release build produces a valid signed universal `arm64`/`x86_64` application. The updated bundle was installed and accepted by the public Text Input Sources registration and enable APIs. Manual TextEdit testing confirmed `ㄨㄛˇ`, `ㄐㄧㄢˋ`, `˙ㄉㄜ`, and the individual `ㄅㄆㄇㄈ` inputs.

## References

- [Apple InputMethodKit `IMKServerInput`](https://developer.apple.com/documentation/inputmethodkit/imkserverinput)
- [Apple `IMKInputController.commitComposition(_:)`](https://developer.apple.com/documentation/objectivec/nsobject-swift.class/commitcomposition(_:))
- Apple macOS 26.5 SDK public headers: `IMKInputSession.h`, `IMKInputController.h`, and `Events.h`
- [Ministry of Education: Mandarin Phonetic Symbols handbook](https://language.moe.gov.tw/001/Upload/files/site_content/M0001/juyin/html_ch/)

## Intentional limitations

There is no character lookup, candidate UI, alternate layout, punctuation mapping, Shift language toggle, learning, user dictionary, settings UI, telemetry, or network access in this milestone.
