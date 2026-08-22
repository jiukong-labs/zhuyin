# Jiukong Zhuyin 久空輸入法

> 久空輸入法 — A Traditional Chinese Zhuyin input method for macOS.

久空輸入法是一套為 macOS 設計的繁體中文注音輸入法，著重於快速選字、完整候選字顯示、單按 Shift 切換中英文，以及完全離線的個人選字與詞組學習。

Jiukong Zhuyin is a Traditional Chinese Zhuyin input method for macOS, focused on fast and complete candidate selection, single-Shift Chinese/English switching, and fully local character and phrase learning.

> 開發狀態：Milestone 11 已加入跟隨游標的輸入模式指示器。字與詞的學習資料只保存在目前 Mac。

## 原創開發原則

久空輸入法採完全自主設計：輸入法核心、組字流程、候選排序、學習機制、資料庫格式、介面，以及內建詞表，均針對本專案自行設計與實作，不複製、移植或改寫其他輸入法的程式碼、演算法實作或詞庫資料。這是本專案後續開發的永久原則。

為了正確支援 macOS 與正式中文字碼，本專案只保留清楚揭露的基礎例外：Apple 平台 SDK／系統程式庫、僅供開發使用的工具，以及數位發展部公布的 CNS11643 官方字碼與注音標準資料。這些例外只提供平台介面與單字標準，不提供久空的輸入引擎、排序演算法或自製詞表；完整範圍列於 [Third-Party Notices](THIRD_PARTY_NOTICES.md)。

## Current features

- Traditional Chinese Zhuyin composition
- Native macOS input method with a custom nonactivating candidate window
- CNS11643 base character candidates
- Compact and 27-item expanded candidate views with scrolling
- Standalone left/right Shift Chinese/English switching
- Persistent, local character-selection learning and deterministic ranking
- Multi-character marked composition and exact user-phrase learning
- Original built-in phrase lexicon maintained by this project
- Persistent settings for Shift switching and automatic learning
- Searchable user-dictionary management with pinning, deletion, and clearing
- Local JSON export and merging import of personal learning data
- Full-width Chinese punctuation on every arrangement
- Standard, Eten Traditional, and IBM Bopomofo arrangements
- Optional cursor-following indicator for the current input mode
- Fully offline
- Open source
- MIT-licensed source code

## Planned features

- Punctuation candidate window and remappable symbol tables

## Milestone 11 input

預設使用台灣標準（大千）注音實體鍵位，與目前選用的英文字母鍵盤配置無關：

```text
1 ㄅ  2 ㄉ  3 ˇ  4 ˋ  5 ㄓ  6 ˊ  7 ˙  8 ㄚ  9 ㄞ  0 ㄢ  - ㄦ
q ㄆ  w ㄊ  e ㄍ  r ㄐ  t ㄔ  y ㄗ  u ㄧ  i ㄛ  o ㄟ  p ㄣ
a ㄇ  s ㄋ  d ㄎ  f ㄑ  g ㄕ  h ㄘ  j ㄨ  k ㄜ  l ㄠ  ; ㄤ
z ㄈ  x ㄌ  c ㄏ  v ㄒ  b ㄖ  n ㄙ  m ㄩ  , ㄝ  . ㄡ  / ㄥ
Space 一聲
```

也可在設定視窗改用「倚天傳統」或「IBM」配置：

```text
倚天傳統
1 ˙   2 ˊ   3 ˇ   4 ˋ   7 ㄑ  8 ㄢ  9 ㄣ  0 ㄤ  - ㄥ  = ㄦ
q ㄟ  w ㄝ  e ㄧ  r ㄜ  t ㄊ  y ㄡ  u ㄩ  i ㄞ  o ㄛ  p ㄆ
a ㄚ  s ㄙ  d ㄉ  f ㄈ  g ㄐ  h ㄏ  j ㄖ  k ㄎ  l ㄌ  ; ㄗ  ' ㄘ
z ㄠ  x ㄨ  c ㄒ  v ㄍ  b ㄅ  n ㄋ  m ㄇ  , ㄓ  . ㄔ  / ㄕ

IBM
1 ㄅ  2 ㄆ  3 ㄇ  4 ㄈ  5 ㄉ  6 ㄊ  7 ㄋ  8 ㄌ  9 ㄍ  0 ㄎ  - ㄏ
q ㄐ  w ㄑ  e ㄒ  r ㄓ  t ㄔ  y ㄕ  u ㄖ  i ㄗ  o ㄘ  p ㄙ
a ㄧ  s ㄨ  d ㄩ  f ㄚ  g ㄛ  h ㄜ  j ㄝ  k ㄞ  l ㄟ  ; ㄠ
z ㄡ  x ㄢ  c ㄣ  v ㄤ  b ㄥ  n ㄦ  m ˊ   , ˇ   . ˋ   / ˙
```

三種配置都是一鍵一符號，Space 都是一聲。切換配置會先送出尚未完成的組字，下一次按鍵立即生效，不需重新啟動。倚天26鍵與許氏這類一鍵多符號的配置不在目前範圍內。標點不受配置影響。

例如 `j i 3` 會完成 `ㄨㄛˇ`，並直接在 marked composition 中預覽第一候選「我」；`r u 0 4` 會預覽 `ㄐㄧㄢˋ` 的第一候選。完成音節時不主動顯示候選窗，按 ↓ 才開啟完整選字模式；開啟後同時顯示最多 27 個候選，更多內容可用滑鼠滾輪查看，原本第一候選仍保持反白。

一般輸入的候選尚未開啟時，←／→ 與數字列都保留給文字定位或下一個注音；按 ↓ 後才由候選格接管方向鍵與 `1`–`9`。已有未送出的文字後，逐字修改分成兩層：先用 ←／→ 在整段 marked composition 中選擇要修改的字，候選窗標題會顯示例如「定位 1／3：測　ㄘㄜˋ　↓ 進入選字」，目前字也會加上黃色底色與橘色粗底線；按 ↓ 進入選字層後，標題改為「選字」，←／→ 才會移動候選反白，↑／↓ 可跨列移動，Esc 返回定位層。Return、數字鍵或滑鼠可確認候選；逐字修改期間畫面列出的 `1`–`9` 永遠代表候選編號，不會被當成下一個注音鍵。確認後仍停在同一個文字位置，方便再用 ←／→ 定位。移到最後一字再按 → 會回到文末繼續輸入。

完成一個音節後可直接輸入下一個音節，久空會先把目前預覽的第一候選收進 marked composition；這也適用於標準、倚天與 IBM 配置中位於數字列的聲母、介音或韻母。候選窗未開啟時，主鍵區 `1`–`9` 不選候選，而是照鍵盤配置繼續輸入；要改選時先按 ↓，開窗後 `1`–`9` 才全部明確代表候選編號。Return／Keypad Enter 會接受預覽並直接提交整段組字，Space 接受第一候選並留在組字中，也可開窗後用方向鍵、數字或滑鼠選定。對沒有候選的讀音，或字典無法使用時，會安全地送出字面注音。Enter 仍可直接送出尚未加聲調的音節。

- Backspace：組字時刪除最後輸入的注音 component；第一候選預覽或候選窗開啟時，回到注音並刪除聲調。
- Escape：候選窗開啟時先回到隱藏的第一候選預覽；再按一次才丟棄目前音節。
- 未組字時的 Space、Enter、Escape 與 Backspace：交回目前 App 正常處理。
- 未映射按鍵或一般 Command／Control／Option／Shift／Fn 快捷鍵：先完成目前組字；候選模式會提交目前反白候選，再交回 App。

候選選定後會先留在輸入法自己的 marked composition，而不是立刻寫入 App。可以直接開始下一個音節；隱藏預覽時按 Return／Keypad Enter 會接受預覽並一次提交整段組字。Escape 依序關閉已開啟的候選窗、取消目前預覽、關閉逐字修改、丟棄 raw 注音、取消範圍選取或丟棄整段 buffer；Backspace 會從候選或預覽回到注音編輯，再刪除當前修改字、注音 component，或 buffer 的選取範圍／最後一個讀音單位。

未學習過的單字候選忠實保留 CNS11643 注音資料的來源順序；該順序不是字頻。使用者實際提交選字後，該字會在下一次同音單字查詢時直接成為第一候選；選過多個同音字時以最近一次提交者優先，手動置頂仍高於自動學習。已開啟的候選快照不會在操作途中跳動，尚未送進 App 就被丟棄的組字也不會留下學習紀錄。

完成第二個以上的音節時，久空也會查詢自製內建詞表與個人詞庫，最長的完整尾端讀音優先。例如依序輸入 `h k 4 g 4`（`ㄘㄜˋ ㄕˋ`），即使第一音暫時顯示 CNS 順序的「冊」，第二音完成後第一候選會成為「測試」；按 Return、Space 或直接輸入下一音即可用整詞取代暫存單字。內建詞表位於 `Data/JiukongPhrases/phrases.tsv`，由本專案逐筆編寫，不含外部詞庫或匯入詞頻；未收錄的詞仍可透過 Shift 範圍造詞與本機學習補充。

同一機制可處理「測試中請稍後」：前五音可不停頓直接繼續，完成 `ㄏㄡˋ` 後會把六音完整句列為第一候選，而不是只顯示「後」的單字候選。候選格會依詞的長度自動加寬，不會把整句裁成一個字。

`1`、`q`、`a`、`z` 都是聲母鍵；要連續驗證 `ㄅㄆㄇㄈ`，請在每個鍵後按 Enter 或一聲 Space 完成音節。直接連按四鍵會合理地以後一個聲母取代前一個。

### 中文標點

中文模式下的全形標點放在 Shift；注音鍵不加 Shift 時維持原本的注音：

```text
Shift+,  ，      Shift+.  。      Shift+/  ？      Shift+;  ：
Shift+1  ！      Shift+6  …       Shift+9  （      Shift+0  ）
Shift+-  —
[  「            ]  」            \  、
Shift+[  『      Shift+]  』
```

`…` 與 `—` 每次插入一個，慣用的 `……`、`——` 請按兩下。`[`、`]`、`\` 不在注音鍵盤配置內，所以不必按 Shift。表格以外的鍵仍交回目前 App 與 macOS 鍵盤配置，英文模式完全不受影響；也就是說中文模式下 `[` 不會再打出半形 `[`，需要半形時請切到英文模式。

標點會結束目前的讀音但不結束整段組字：按下標點時會先把反白候選或未完成注音收進 buffer，再把標點接在後面，仍是 marked text，Return 時才一起送出，Backspace 也能直接刪掉標點。標點本身沒有讀音，因此不會參與造詞或詞查詢；`「久空` 這種情況前面的 `久空` 仍然可以造詞。

### 中英文切換

中文模式下單獨按一下左 Shift 或右 Shift，會切換到英文模式；再單獨按一次會切回中文。按住 Shift 搭配字母、數字、方向鍵或其他修飾鍵時不會切換。切換後會在游標附近短暫顯示「中」或「A」，不會搶走目前 App 的鍵盤焦點；若已開啟游標指示器，就改由它常駐顯示，不再另外閃現提示。

英文模式不合成注音，也不自行產生 ASCII；久空會把字母、數字、標點、Space、Return、Backspace、dead key 與 App 快捷鍵原樣交給目前的 macOS 鍵盤配置處理。目前中英文狀態在同一個輸入法 process 的所有 client 間共享，process 重新啟動後預設回到中文。要用哪一側 Shift（左右皆可／只用左／只用右／關閉）可在設定視窗選擇，並會保存下來。

若切換模式時仍有未完成注音或候選，久空會先完成一次目前組字再切換，避免吃字或重複插入。因 Milestone 5 需要接收 Shift 的 modifier 事件，久空也會透過 InputMethodKit 公開事件路徑處理 client 內的滑鼠按下：先完成現有組字，再把點擊交回 App。

### 游標指示器

設定視窗的「游標指示器」分頁可讓目前輸入模式常駐顯示在滑鼠游標旁，功能來自獨立工具 `lang-cursor`（付費的 StoreKit 授權部分未移植）：

- 位置：游標右上／右側／右下；
- 追蹤：固定距離（貼齊游標）或跟隨游標（帶尾隨感的緩動）；
- 文字大小五段；
- Caps Lock 開啟時可一併顯示 `⇪`，並有五段大小；
- 中文與英文各自的自訂文字（最多 4 字元）與顏色，留空即用預設的「中」「A」與紅／藍。

指示器**預設關閉**。它只在久空是目前輸入來源時顯示，切換到其他輸入法會自動消失 —— 想在所有輸入法下都看得到，仍需使用獨立的 `lang-cursor`。Caps Lock 狀態以每 0.2 秒輪詢取得，不需要輸入監控權限。

### 個人選字學習

Space、Return、數字鍵、滑鼠點選，以及切換欄位／輸入來源前實際提交的候選，都只會學習一次。Escape、Backspace、方向鍵移動、空的數字槽與字面注音 fallback 不會改變學習資料。相同文字的不同讀音分開統計；置頂狀態是獨立的最高排序層級，可在設定視窗的清單中逐項調整。

在設定視窗關閉「自動學習」後，就不再累積新的使用次數；既有紀錄仍會影響排序，Shift 造詞也仍可使用。

選定候選只會先建立待提交事件；整段 composition 真正送進 App 後才會學習。被 Escape 丟棄、被 Backspace 刪除或被詞候選取代的內容不會留下錯誤計數。

### 使用者造詞

每個已選候選都保留其精確注音。按 Shift+← 從 buffer 尾端逐字向左擴張範圍，Shift+→ 向右縮小；選取至少兩個讀音單位後按 Return，即把該範圍的文字與逐音注音加入使用者詞庫，再一次提交整段 composition。這個功能只處理輸入法尚未提交的 buffer，不會讀取其他 App 已有的文字。

之後重打相同的完整逐音序列時，使用者詞會出現在最後一個音節的候選中。查詢是完整相等、最長後綴優先；目前不做詞首聯想，也不會未經確認自動補完整詞。置頂仍是最高排序層，未置頂的精確使用者詞則優先於一般未置頂單字。

學習資料使用具 schema 版本的 SQLite，存放於 `~/Library/Application Support/JiukongZhuyin/user.sqlite`，不會寫進 `.app` bundle。schema v2 原地保留 M6 字頻並加入使用者詞與有順序的逐音讀音。資料庫無法使用時，輸入仍會安全退回 CNS 原始順序。重新安裝或執行 `scripts/uninstall.sh` 不會刪除 Application Support 中的使用者資料。

### 設定視窗

在 macOS 輸入選單中選擇久空的「偏好設定…」即可開啟設定視窗，共四個分頁：

- **一般**：注音鍵盤配置（標準／倚天傳統／IBM）、中英文切換要用哪一側 Shift（左右皆可／只用左／只用右／關閉）、自動學習開關；
- **游標指示器**：在游標旁顯示目前輸入模式，可設定位置、追蹤方式、文字大小、Caps Lock 指示，以及中／英文各自的文字與顏色；
- **使用者詞**：列出所有自己造的詞與逐音注音，可搜尋、置頂或刪除單筆；
- **選字紀錄**：列出所有已學習的單字讀音、次數與置頂狀態，可搜尋、置頂或刪除單筆；
- **資料**：匯出／匯入 JSON，以及清除選字紀錄、清除使用者詞、清除全部。

設定存放在輸入法自己的 defaults domain，重新啟動後仍然有效；所有刪除與清除動作只影響 `user.sqlite`，不會動到內建字典，且都需要再次確認。開啟設定視窗前會先完成目前的組字。

刪除是以「文字 + 完整讀音」為單位，所以刪掉 `行／ㄒㄧㄥˊ` 不會影響 `行／ㄏㄤˊ`。

### 匯出與匯入

匯出會寫出帶版本的 JSON，時間一律使用 UTC 毫秒，不含本機的內部 ID。匯入是合併而非覆蓋：次數與時間取較大／較新者、建立時間取較早者、置頂取聯集，因此重複匯入同一個檔案不會重複累加，也不會把次數變小或取消置頂。無法辨識的資料列會被略過並回報數量；若其中一筆無法套用，整次匯入會完整回復原狀。匯出檔沒有加密，內容是你打過與選過的字，請比照個人檔案保管。

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

The checked-in Xcode project builds without XcodeGen. Maintainers who add a file or change `project.yml` must regenerate it with XcodeGen 2.46 or later and commit the result:

```sh
xcodegen generate
```

A file that exists on disk but is missing from the checked-in project is silently not compiled and its tests never run, so verify membership before committing:

```sh
./scripts/check-project-sources.sh
```

GitHub Actions runs the same checks on every push and pull request: the source-membership check, the Debug test suite, a universal Release build, and a rebuild of the dictionary from its pinned snapshot that must reproduce the checked-in artifact byte for byte. A separate advisory job reports when the checked-in project no longer matches `project.yml`.

The runtime dictionary is already checked in. To verify or regenerate it from the pinned, hash-validated CNS11643 snapshot and Jiukong's first-party phrase TSV without network access:

```sh
./scripts/build-dictionary.sh
```

Normal app builds never download or parse the raw CNS11643 or phrase-source files.

## Install for local development

The installer builds a Release configuration, copies it to the current user's supported Input Methods directory, validates the bundle, then registers it and requests enablement through Apple's public Text Input Sources APIs. It does not switch away from your current input source:

```sh
./scripts/install.sh
```

The default build uses an ad-hoc local signature. A maintainer with an Apple Development certificate can select it without changing the project:

```sh
SIGNING_IDENTITY="Apple Development: Your Name (TEAMID)" ./scripts/install.sh
```

The bundle identifier is `tw.idv.jiukong.inputmethod.zhuyin`. Two constraints were established by experiment on macOS 26 and both make registration fail silently:

The bundle is the parent of two selectable modes:
`tw.idv.jiukong.inputmethod.zhuyin.Chinese` and
`tw.idv.jiukong.inputmethod.zhuyin.English`. Their first-party template icons
show `中` and `英`; Shift selects the other mode so macOS updates the existing
input-menu icon.

- **The identifier must contain an `inputmethod` component that is not the last one.** `tw.idv.jiukong.inputmethod.zhuyin` and `tw.idv.inputmethod.zhuyin` register; `tw.idv.jiukong.zhuyin`, `tw.idv.jiukong.zhuyinim`, and `tw.idv.jiukong.zhuyin.inputmethod` do not. `TISRegisterInputSource` still returns `noErr` for the rejected ones, so the only symptom is that the source never appears.
- **No other bundle may claim the same identifier in LaunchServices.** A build product under `.build/`, or a deleted bundle whose record survives, can take the identifier over and make an already-registered input source disappear. Repair it with:

```sh
lsregister=/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister
"$lsregister" -f -R -trusted ~/Library/Input\ Methods/Jiukong\ Zhuyin.app
~/Library/Input\ Methods/Jiukong\ Zhuyin.app/Contents/MacOS/Jiukong\ Zhuyin --register
```

If the installer reports that macOS did not register the input source, check both of those before anything else.

A registered source still has to be enabled, and that is a user decision macOS does not delegate: `TISEnableInputSource` returns `noErr` while leaving the source disabled, and `TISSelectInputSource` then fails with `-50`. A newly registered identifier may also not appear in **System Settings > Keyboard > Text Input > Edit… > +** until the next login, so log out and back in once if it is missing there.

On current macOS versions, enabling a newly installed third-party input method can also require explicit user approval. Then verify or approve the input source:

1. Open **System Settings**.
2. Choose **Keyboard**.
3. Under **Text Input**, click **Edit…**.
4. Confirm **久空輸入法** is present. If it is not already enabled, click **+**, select **Traditional Chinese**, choose **久空輸入法**, and approve the prompt.
5. If the newly installed input method does not appear immediately, sign out and back in once, then repeat the steps.

## Installed acceptance

Unit tests cannot reach the InputMethodKit event path, so the behavior that only exists in a real client is checked by driving the installed bundle:

```sh
./scripts/install.sh
./scripts/run-acceptance.sh              # single, continuous, escape, punctuation, brackets, phrase
./scripts/run-acceptance.sh eten         # after setting the arrangement preference
```

Each run launches its own TextEdit instance, types with real `CGEvent` delivery, compares the resulting text with the expectation, then restores the previous input source and closes the instance it launched. Existing TextEdit windows are untouched.

Every run first completes a probe syllable, presses Down, and requires Jiukong's own candidate panel to appear before it types anything. Without that check a run can silently be composed by the system's built-in Zhuyin input method, which produces the same Bopomofo from the same keys and would look like a pass. A run that cannot prove the connection aborts instead of reporting a result.

The `phrase` script creates the user phrase 九空 in the local learning database, and every run that commits text advances that character's count. Clear them from the settings window if the data is unwanted. The harness needs Accessibility and event-posting permission for the terminal running it, which is why it is not part of continuous integration.

To disable the development input source and remove only its installed bundle:

```sh
./scripts/uninstall.sh
```

No root access, SIP changes, or private APIs are required.

## Current milestone scope

Milestone 11 把獨立工具 `lang-cursor` 的免費功能併入輸入法：跟隨游標的模式指示器（位置、追蹤方式、五種大小、Caps Lock 指示、中／英文自訂文字與顏色），付費的 StoreKit 授權部分未移植。Milestone 10 提供倚天傳統與 IBM 兩種一鍵一符號的注音配置，可在設定視窗切換；配置只影響鍵位對應，組字、選字、學習與標點都不受影響。一鍵多符號的 26 鍵配置與自訂配置仍在後續里程碑。

詳見 [Milestone 11 notes](docs/MILESTONE_11.md)、[Milestone 10 notes](docs/MILESTONE_10.md)、[Milestone 9 notes](docs/MILESTONE_9.md)、[Milestone 8 notes](docs/MILESTONE_8.md)、[Milestone 7 notes](docs/MILESTONE_7.md)、[Milestone 6 notes](docs/MILESTONE_6.md)、[Milestone 5 notes](docs/MILESTONE_5.md)、[Milestone 4 notes](docs/MILESTONE_4.md)、[Milestone 3 notes](docs/MILESTONE_3.md)、[Milestone 2 notes](docs/MILESTONE_2.md)、[Milestone 1 notes](docs/MILESTONE_1.md) 與 [architecture](docs/ARCHITECTURE.md)。

## Privacy

Jiukong Zhuyin works completely offline and does not collect or transmit typing data.

## Project

- GitHub: https://github.com/jiukong-labs/jiukong-zhuyin
- Website: https://jiukong.cloudgate.org.tw
- License: [MIT](LICENSE)

The product implementation and built-in phrase lexicon are original to this project and MIT-licensed. The CNS11643 source snapshot and the character portion of the generated dictionary are distributed under Taiwan's Open Government Data License 1.0; see [Third-Party Notices](THIRD_PARTY_NOTICES.md).
