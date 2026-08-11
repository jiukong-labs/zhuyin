# Jiukong Zhuyin 久空輸入法

> 久空輸入法 — A Traditional Chinese Zhuyin input method for macOS.

久空輸入法是一套為 macOS 設計的繁體中文注音輸入法，著重於快速選字、完整候選字顯示、個人字詞學習，以及單按 Shift 切換中英文。

Jiukong Zhuyin is a Traditional Chinese Zhuyin input method for macOS, focused on fast candidate selection, personal vocabulary learning, and a familiar Shift-based Chinese/English switching experience.

> 開發狀態：Milestone 2 已實作台灣標準注音鍵盤、音節組字與 InputMethodKit 行內標記文字。目前輸出的是注音符號；中文字典與候選字將在 Milestone 3 開始實作。

## Features

- Traditional Chinese Zhuyin
- Native macOS input method
- Shift Chinese/English switching
- Expandable candidate window
- Personal character learning
- Personal phrase learning
- Fully offline
- Open source
- MIT License

上述產品功能將依 Milestone 逐步實作；目前已完成原生輸入法基礎與注音鍵盤組字。

## Milestone 2 input

目前版本使用台灣標準注音實體鍵位，與目前選用的英文字母鍵盤配置無關：

```text
1 ㄅ  2 ㄉ  3 ˇ  4 ˋ  5 ㄓ  6 ˊ  7 ˙  8 ㄚ  9 ㄞ  0 ㄢ  - ㄦ
q ㄆ  w ㄊ  e ㄍ  r ㄐ  t ㄔ  y ㄗ  u ㄧ  i ㄛ  o ㄟ  p ㄣ
a ㄇ  s ㄋ  d ㄎ  f ㄑ  g ㄕ  h ㄘ  j ㄨ  k ㄜ  l ㄠ  ; ㄤ
z ㄈ  x ㄌ  c ㄏ  v ㄒ  b ㄖ  n ㄙ  m ㄩ  , ㄝ  . ㄡ  / ㄥ
Space 一聲
```

例如 `j i 3` 會送出 `ㄨㄛˇ`，`r u 0 4` 會送出 `ㄐㄧㄢˋ`，`2 k 7` 會送出 `˙ㄉㄜ`。輸入中的注音會先顯示為 marked text；聲調鍵會完成並送出音節，Enter 可送出尚未加聲調的音節。

- Backspace：刪除最後輸入的注音 component。
- Escape：丟棄目前音節。
- 未組字時的 Space、Enter、Escape 與 Backspace：交回目前 App 正常處理。
- 未映射按鍵或 Command／Control／Option／Shift／Fn 組合鍵：先送出既有音節，再交回 App。

`1`、`q`、`a`、`z` 都是聲母鍵；要連續驗證 `ㄅㄆㄇㄈ`，請在每個鍵後按 Enter 或一聲 Space 完成音節。直接連按四鍵會合理地以後一個聲母取代前一個。

## Requirements

- macOS 13 or later for the input method
- macOS 14 or later for the current unit-test target
- Xcode 26.6 or a compatible Xcode version with the macOS SDK

## Build and test

```sh
xcodebuild \
  -project "Jiukong Zhuyin.xcodeproj" \
  -scheme "Jiukong Zhuyin" \
  -configuration Debug \
  -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath .build/DerivedData \
  build

xcodebuild \
  -project "Jiukong Zhuyin.xcodeproj" \
  -scheme "Jiukong Zhuyin" \
  -configuration Debug \
  -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath .build/DerivedData \
  test
```

The checked-in Xcode project builds without XcodeGen. Maintainers who change `project.yml` can regenerate it with XcodeGen 2.46 or later:

```sh
xcodegen generate
```

## Install for local development

The installer builds a Release configuration, copies it to the current user's supported Input Methods directory, validates the bundle, then registers it and requests enablement through Apple's public Text Input Sources APIs. It does not switch away from your current input source:

```sh
./scripts/install.sh
```

The default build uses an ad-hoc local signature. A maintainer with an Apple Development certificate can select it without changing the project:

```sh
SIGNING_IDENTITY="Apple Development: Your Name (TEAMID)" ./scripts/install.sh
```

On current macOS versions, enabling a newly installed third-party input method can require explicit user approval. Then verify or approve the input source:

1. Open **System Settings**.
2. Choose **Keyboard**.
3. Under **Text Input**, click **Edit…**.
4. Confirm **久空輸入法** is present. If it is not already enabled, click **+**, select **Traditional Chinese**, choose **久空輸入法**, and approve the prompt.
5. If the newly installed input method does not appear immediately, sign out and back in once, then repeat the steps.

To disable the development input source and remove only its installed bundle:

```sh
./scripts/uninstall.sh
```

No root access, SIP changes, or private APIs are required.

## Current milestone scope

Milestone 2 只輸出字面注音，不會把 `ㄨㄛˇ` 轉成「我」。中文字典、候選視窗、單按 Shift 切換、使用者學習及設定仍屬後續 Milestone。See [Milestone 2 notes](docs/MILESTONE_2.md), [Milestone 1 notes](docs/MILESTONE_1.md), and [architecture](docs/ARCHITECTURE.md).

## Privacy

Jiukong Zhuyin works completely offline and does not collect or transmit typing data.

## Project

- GitHub: https://github.com/jiukong-labs/jiukong-zhuyin
- Website: https://jiukong.cloudgate.org.tw
- License: [MIT](LICENSE)
