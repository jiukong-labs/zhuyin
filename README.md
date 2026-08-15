# Jiukong Zhuyin 久空輸入法

> 久空輸入法 — A Traditional Chinese Zhuyin input method for macOS.

久空輸入法是一套為 macOS 設計的繁體中文注音輸入法，著重於快速選字、完整候選字顯示，以及單按 Shift 切換中英文，並規劃加入個人字詞學習。

Jiukong Zhuyin is a Traditional Chinese Zhuyin input method for macOS, focused on fast and complete candidate selection with single-Shift Chinese/English switching. Personal learning remains planned for later milestones.

> 開發狀態：Milestone 5 已加入單按左右 Shift 切換中英文。中文模式保留自有候選視窗；英文模式把鍵盤事件直接交給目前 App。

## Current features

- Traditional Chinese Zhuyin composition
- Native macOS input method with a custom nonactivating candidate window
- CNS11643 base character candidates
- Compact and 27-item expanded candidate views with scrolling
- Standalone left/right Shift Chinese/English switching
- Fully offline
- Open source
- MIT-licensed source code

## Planned features

- Personal character learning
- Personal phrase learning

## Milestone 5 input

目前版本使用台灣標準注音實體鍵位，與目前選用的英文字母鍵盤配置無關：

```text
1 ㄅ  2 ㄉ  3 ˇ  4 ˋ  5 ㄓ  6 ˊ  7 ˙  8 ㄚ  9 ㄞ  0 ㄢ  - ㄦ
q ㄆ  w ㄊ  e ㄍ  r ㄐ  t ㄔ  y ㄗ  u ㄧ  i ㄛ  o ㄟ  p ㄣ
a ㄇ  s ㄋ  d ㄎ  f ㄑ  g ㄕ  h ㄘ  j ㄨ  k ㄜ  l ㄠ  ; ㄤ
z ㄈ  x ㄌ  c ㄏ  v ㄒ  b ㄖ  n ㄙ  m ㄩ  , ㄝ  . ㄡ  / ㄥ
Space 一聲
```

例如 `j i 3` 會完成 `ㄨㄛˇ` 並顯示候選，第一個候選是「我」；`r u 0 4` 會顯示 `ㄐㄧㄢˋ` 的同音候選。輸入中的注音會先顯示為 marked text；聲調鍵會完成音節並查詢字典。候選窗起初顯示目前一列、最多 9 個候選；第一次按 ↓ 只展開視窗，不移動反白，展開後同時顯示最多 27 個候選，更多內容可用滑鼠滾輪查看。

精簡模式可用 ←／→（以及 ↑）逐字移動，第一次按 ↓ 只展開；展開後 ←／→ 移動一字、↑／↓ 移動九字列，Home／End 與 Page Up／Page Down 可快速跳轉。按主鍵區 `1`–`9` 選擇反白所在 9 字列的候選，Return／Keypad Enter 選定反白候選，Space 永遠選第一候選，也可直接用滑鼠點選。對沒有候選的讀音，或字典無法使用時，會安全地送出字面注音。Enter 仍可直接送出尚未加聲調的音節。

- Backspace：組字時刪除最後輸入的注音 component；候選顯示時關閉候選窗、刪除聲調，回到注音編輯。
- Escape：丟棄目前音節或取消目前候選組字。
- 未組字時的 Space、Enter、Escape 與 Backspace：交回目前 App 正常處理。
- 未映射按鍵或一般 Command／Control／Option／Shift／Fn 快捷鍵：先完成目前組字；候選模式會提交目前反白候選，再交回 App。

候選順序在此階段忠實保留 CNS11643 注音資料的來源順序，並不代表使用頻率。個人排序學習屬後續 Milestone。

`1`、`q`、`a`、`z` 都是聲母鍵；要連續驗證 `ㄅㄆㄇㄈ`，請在每個鍵後按 Enter 或一聲 Space 完成音節。直接連按四鍵會合理地以後一個聲母取代前一個。

### 中英文切換

中文模式下單獨按一下左 Shift 或右 Shift，會切換到英文模式；再單獨按一次會切回中文。按住 Shift 搭配字母、數字、方向鍵或其他修飾鍵時不會切換。切換後會在游標附近短暫顯示「中」或「A」，不會搶走目前 App 的鍵盤焦點。

英文模式不合成注音，也不自行產生 ASCII；久空會把字母、數字、標點、Space、Return、Backspace、dead key 與 App 快捷鍵原樣交給目前的 macOS 鍵盤配置處理。目前中英文狀態在同一個輸入法 process 的所有 client 間共享，process 重新啟動後預設回到中文。左右／單側／關閉 Shift 切換的持久設定屬 Milestone 8。

若切換模式時仍有未完成注音或候選，久空會先完成一次目前組字再切換，避免吃字或重複插入。因 Milestone 5 需要接收 Shift 的 modifier 事件，久空也會透過 InputMethodKit 公開事件路徑處理 client 內的滑鼠按下：先完成現有組字，再把點擊交回 App。

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

Milestone 5 提供單按左右 Shift 的中英文切換、英文直通模式與短暫模式提示，並保留 Milestone 4 的自製候選視窗及輸入行為。詞組轉換、候選頻率排序、使用者學習及設定仍屬後續 Milestone。

詳見 [Milestone 5 notes](docs/MILESTONE_5.md)、[Milestone 4 notes](docs/MILESTONE_4.md)、[Milestone 3 notes](docs/MILESTONE_3.md)、[Milestone 2 notes](docs/MILESTONE_2.md)、[Milestone 1 notes](docs/MILESTONE_1.md) 與 [architecture](docs/ARCHITECTURE.md)。

## Privacy

Jiukong Zhuyin works completely offline and does not collect or transmit typing data.

## Project

- GitHub: https://github.com/jiukong-labs/jiukong-zhuyin
- Website: https://jiukong.cloudgate.org.tw
- License: [MIT](LICENSE)

The source code is MIT-licensed. The CNS11643 source snapshot and generated dictionary are distributed under Taiwan's Open Government Data License 1.0; see [Third-Party Notices](THIRD_PARTY_NOTICES.md).
