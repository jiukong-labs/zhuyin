# Jiukong Zhuyin 久空輸入法

> 久空輸入法 — A Traditional Chinese Zhuyin input method for macOS.

久空輸入法是一套為 macOS 設計的繁體中文注音輸入法，著重於快速選字、完整候選字顯示、個人字詞學習，以及單按 Shift 切換中英文。

Jiukong Zhuyin is a Traditional Chinese Zhuyin input method for macOS, focused on fast candidate selection, personal vocabulary learning, and a familiar Shift-based Chinese/English switching experience.

> 開發狀態：Milestone 1 已完成原生 macOS Input Method 的 build、安裝、公開 API 註冊與系統設定可見性驗收。尚未實作注音輸入。

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

上述產品功能將依 Milestone 逐步實作；目前只完成原生輸入法的執行、安裝與註冊基礎。

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

## Milestone 1 scope

The input controller intentionally returns unhandled key events to the active app. Keyboard mapping, Bopomofo parsing, dictionaries, candidates, Shift switching, and learning belong to later milestones and are not included yet. See [Milestone 1 notes](docs/MILESTONE_1.md) and [architecture](docs/ARCHITECTURE.md).

## Privacy

Jiukong Zhuyin works completely offline and does not collect or transmit typing data.

## Project

- GitHub: https://github.com/jiukong-labs/jiukong-zhuyin
- Website: https://jiukong.cloudgate.org.tw
- License: [MIT](LICENSE)
