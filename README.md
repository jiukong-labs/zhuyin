# Jiukong Zhuyin 久空輸入法

> 久空輸入法 — A Traditional Chinese Zhuyin input method for macOS.

久空輸入法是一套為 macOS 設計的繁體中文注音輸入法，著重於快速選字、完整候選字顯示、個人字詞學習，以及單按 Shift 切換中英文。

Jiukong Zhuyin is a Traditional Chinese Zhuyin input method for macOS, focused on fast candidate selection, personal vocabulary learning, and a familiar Shift-based Chinese/English switching experience.

> 開發狀態：Milestone 3 已接上 CNS11643 基礎中文字典與 macOS 系統候選面板。輸入完整注音與聲調後，可查詢、顯示並選取單字候選。

## Current features

- Traditional Chinese Zhuyin composition
- Native macOS input method and candidate panel
- CNS11643 base character candidates
- Fully offline
- Open source
- MIT-licensed source code

## Planned features

- Shift Chinese/English switching
- Expandable candidate window
- Personal character learning
- Personal phrase learning

## Milestone 3 input

目前版本使用台灣標準注音實體鍵位，與目前選用的英文字母鍵盤配置無關：

```text
1 ㄅ  2 ㄉ  3 ˇ  4 ˋ  5 ㄓ  6 ˊ  7 ˙  8 ㄚ  9 ㄞ  0 ㄢ  - ㄦ
q ㄆ  w ㄊ  e ㄍ  r ㄐ  t ㄔ  y ㄗ  u ㄧ  i ㄛ  o ㄟ  p ㄣ
a ㄇ  s ㄋ  d ㄎ  f ㄑ  g ㄕ  h ㄘ  j ㄨ  k ㄜ  l ㄠ  ; ㄤ
z ㄈ  x ㄌ  c ㄏ  v ㄒ  b ㄖ  n ㄙ  m ㄩ  , ㄝ  . ㄡ  / ㄥ
Space 一聲
```

例如 `j i 3` 會完成 `ㄨㄛˇ` 並顯示候選，第一個候選是「我」；`r u 0 4` 會顯示 `ㄐㄧㄢˋ` 的同音候選。輸入中的注音會先顯示為 marked text；聲調鍵會完成音節並查詢字典。候選模式可用方向鍵、Home／End、Page Up／Page Down 移動反白，按 `1`–`9` 選擇目前頁面的候選，Return／Keypad Enter 選定目前候選，也可直接用滑鼠點選 macOS 系統候選面板。對沒有候選的讀音，或字典無法使用時，會安全地送出字面注音。Enter 仍可直接送出尚未加聲調的音節。

- Backspace：組字時刪除最後輸入的注音 component；候選顯示時取消整個候選組字。
- Escape：丟棄目前音節或取消目前候選組字。
- 未組字時的 Space、Enter、Escape 與 Backspace：交回目前 App 正常處理。
- 未映射按鍵或一般 Command／Control／Option／Shift／Fn 快捷鍵：先完成目前組字；候選模式會提交反白或第一候選，再交回 App。

候選順序在此階段忠實保留 CNS11643 注音資料的來源順序，並不代表使用頻率。個人排序學習屬後續 Milestone。

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

The runtime dictionary is already checked in. To verify or regenerate it from the pinned, hash-validated CNS11643 snapshot without network access:

```sh
./scripts/build-dictionary.sh
```

Normal app builds never download or parse the raw CNS11643 files.

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

Milestone 3 提供 CNS11643 基礎單字查詢與 Apple 系統候選面板。自製可展開候選視窗、詞組轉換、候選頻率排序、單按 Shift 切換、使用者學習及設定仍屬後續 Milestone。See [Milestone 3 notes](docs/MILESTONE_3.md), [Milestone 2 notes](docs/MILESTONE_2.md), [Milestone 1 notes](docs/MILESTONE_1.md), and [architecture](docs/ARCHITECTURE.md).

## Privacy

Jiukong Zhuyin works completely offline and does not collect or transmit typing data.

## Project

- GitHub: https://github.com/jiukong-labs/jiukong-zhuyin
- Website: https://jiukong.cloudgate.org.tw
- License: [MIT](LICENSE)

The source code is MIT-licensed. The CNS11643 source snapshot and generated dictionary are distributed under Taiwan's Open Government Data License 1.0; see [Third-Party Notices](THIRD_PARTY_NOTICES.md).
