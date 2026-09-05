# Jiukong Zhuyin 久空輸入法

> 久空輸入法 — A Traditional Chinese Zhuyin input method for macOS.

久空輸入法是一套為 macOS 設計的繁體中文注音輸入法，著重於快速而實用的候選字、單按 Shift 切換中英文，以及離線優先、可透過 iCloud 自動還原的個人選字與詞組學習。

Jiukong Zhuyin is a Traditional Chinese Zhuyin input method for macOS, focused on fast and practical candidate selection, single-Shift Chinese/English switching, and offline-first character and phrase learning with optional iCloud restoration.

> 開發狀態：選字、使用者詞與游標外觀偏好已具備 CloudKit 私有資料庫同步實作；正式連線須使用 Apple Developer Team 簽署、既有 container 與已部署的 production schema。

## AI 製作聲明

久空輸入法完全由 AI 製作，包括產品設計、程式碼、測試、文件與本專案原創的內建詞表。第三方平台、工具與官方標準資料不屬於本專案的創作內容，其範圍與授權另見 [Third-Party Notices](THIRD_PARTY_NOTICES.md)。

Jiukong Zhuyin is made entirely by AI, including its product design, source code, tests, documentation, and original built-in lexicon. Third-party platforms, tools, and official standards data are not project-authored content; their scope and licenses are documented in [Third-Party Notices](THIRD_PARTY_NOTICES.md).

## 原創開發原則

久空輸入法採完全自主設計：輸入法核心、組字流程、候選排序、學習機制、資料庫格式、介面與第一方詞表，均針對本專案自行設計與實作，不複製、移植或改寫其他輸入法的程式碼、演算法實作或詞庫資料。這是本專案後續開發的永久原則。

例外範圍固定為 Apple 平台 SDK／系統程式庫、僅供開發使用的工具、數位發展部公布的 CNS11643 官方字碼與注音資料，以及教育部的常用／次常用國字標準字體表、《成語典》與《重編國語辭典修訂本》。教育部字表只用於粗略的候選字分級；後兩者只保留已釘選四字條目的原文詞目與讀音，作為獨立標示的政府來源詞資料，不屬於第一方詞表或 AI 創作內容。各項版本、轉換方式與授權列於 [Third-Party Notices](THIRD_PARTY_NOTICES.md)，未經明確同意不再擴大例外。

## Current features

- Traditional Chinese Zhuyin composition
- Native macOS input method with a custom nonactivating candidate window
- CNS11643 base character candidates
- Compact and 27-item expanded candidate views with scrolling
- Standalone left/right Shift Chinese/English switching
- Persistent, local character-selection learning and deterministic ranking
- Multi-character marked composition and exact user-phrase learning
- Original first-party phrase lexicon maintained by this project
- Pinned MOE idiom and revised-dictionary four-character phrase candidates
- Persistent settings for Shift switching and automatic learning
- Searchable user-dictionary management with pinning, deletion, and clearing
- Local JSON export and merging import of personal learning data
- Full-width Chinese punctuation on every arrangement
- Standard, Eten Traditional, and IBM Bopomofo arrangements
- Optional cursor-following indicator for the current input mode
- Offline-first input with optional private iCloud learning sync
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

例如 `j i 3` 會完成 `ㄨㄛˇ`，並直接在 marked composition 中預覽第一候選「我」；`r u 0 4` 會預覽 `ㄐㄧㄢˋ` 的第一候選。完成音節時不主動顯示候選窗，按 ↓ 才開啟完整選字模式；開啟後同時顯示最多 27 個候選，更多內容可用滑鼠滾輪查看，原本第一候選仍保持反白。一般模式只採 CNS 第 1、2 字面的常用與次常用字；第 3 字面以後的罕用、異體、戶政與其他專門用字須在設定中開啟「顯示罕用字」才會加入。若 macOS 對某字只能提供 LastResort 缺字符號，則無論設定為何都會略過，避免候選窗出現方框問號。

一般輸入的候選尚未開啟時，←／→ 與數字列都保留給文字定位或下一個注音；按 ↓ 後才由候選格接管方向鍵與 `1`–`9`。已有未送出的文字後，逐字修改分成兩層：先用 ←／→ 在整段 marked composition 中逐個顯示單位移動游標，標點的前後也各自是可停靠位置，例如 `名？｜ → 名｜？ → ｜名？`；這個定位階段不顯示候選窗，也不替任何字加底色或底線。此時 Shift+← 會從游標左側開始造詞，Shift+→ 則從游標右側開始。退格鍵（⌫／Backspace）會把游標左邊緊鄰的讀音字恢復成原注音並先刪除聲調，例如 `路｜鏡 → ㄌㄨ｜鏡 → ㄌ｜鏡 → ｜鏡`；它不會跨越標點，游標在第一字前時也不會改動文字。前向 Del（Fn+Backspace）則以同樣方式倒退編輯游標右邊的字，例如 `路｜鏡 → 路ㄐㄧㄥ｜ → 路ㄐㄧ｜ → 路ㄐ｜ → 路｜`。按 ↓ 才開啟游標左邊緊鄰字的九個候選，例如 `路｜鏡` 會顯示「選字 1／2：路」，而 `路鏡｜` 會顯示「選字 2／2：鏡」；再按 ↓ 可展開完整候選格。候選窗開啟後仍把同一個零長度游標留在原位，不把任何字或整段組字當成 selection。選字層的 ←／→ 移動候選反白，↑ 或 Esc 關閉候選並回到文字定位，之後 ←／→ 又會移動游標。Return、數字鍵或滑鼠可確認候選；只有候選窗開啟後，畫面列出的 `1`–`9` 才代表候選編號。確認後仍停在同一個文字位置，方便再用 ←／→ 定位。移到最後一字再按 → 會回到文末，仍可按 ↓ 修改最後一字或直接繼續輸入。

當游標位於整段組字的第一字前方時，左邊沒有可選文字；此時按 ↓ 會改為開啟右邊第一字的候選。其他游標位置仍以左邊緊鄰字為選字目標。

完成一個音節後可直接輸入下一個音節，久空會先把目前預覽的第一候選收進 marked composition；這也適用於標準、倚天與 IBM 配置中位於數字列的聲母、介音或韻母。候選窗未開啟時，主鍵區 `1`–`9` 不選候選，而是照鍵盤配置繼續輸入；要改選時先按 ↓，開窗後 `1`–`9` 才全部明確代表候選編號。Return／Keypad Enter 會接受預覽並直接提交整段組字，Space 接受第一候選並留在組字中，也可開窗後用方向鍵、數字或滑鼠選定。對沒有候選的讀音，或字典無法使用時，會安全地送出字面注音。Enter 仍可直接送出尚未加聲調的音節。

- Backspace：組字時刪除最後輸入的注音 component；第一候選預覽或一般候選窗開啟時，回到該字注音並由聲調開始倒退刪除；逐字定位／選字時，改為倒退編輯定位字左邊緊鄰字的注音；造詞範圍存在時刪除整個範圍。
- Forward Delete（Del／Fn+Backspace）：逐字定位或選字時，倒退編輯游標右邊字的注音；造詞範圍存在時刪除整個範圍。沒有明確的輸入法範圍或定位字時交回 App。
- Escape：候選窗開啟時先回到隱藏的第一候選預覽；再按一次才丟棄目前音節。
- 未組字時的 Space、Enter、Escape 與 Backspace：交回目前 App 正常處理。
- 未映射按鍵或一般 Command／Control／Option／Shift／Fn 快捷鍵：先完成目前組字；候選模式會提交目前反白候選，再交回 App。

中文模式下，`⌥ Option` 搭配主鍵區 `0`–`9` 會直接輸入半形數字，搭配 `A`–`Z` 會輸入小寫英文字母，`Option+Shift+A`–`Z` 則輸入大寫英文字母；其他 Option 組合鍵仍交由目前 App 與 macOS 鍵盤配置處理。若久空正在組字，會先完成目前組字。英文模式不改寫任何 Option 組合鍵。

候選選定後會先留在輸入法自己的 marked composition，而不是立刻寫入 App。可以直接開始下一個音節；隱藏預覽時按 Return／Keypad Enter 會接受預覽並一次提交整段組字。Escape 依序關閉已開啟的候選窗、取消目前預覽、關閉逐字修改、丟棄 raw 注音、取消範圍選取或丟棄整段 buffer；Backspace 會從候選回到該候選的注音編輯，或從定位字向左進入前一字的注音編輯，再逐一刪除注音 component；造詞範圍存在時則刪除整個範圍。

未學習過且在目前候選範圍內、系統也能顯示的單字候選，先依教育部常用、次常用與其他字表分成三級；個別罕見破音可由久空逐筆審訂降級。同級內再依該「字＋讀音」出現在久空自製內建詞表的次數排序，完全沒有自製詞例時才保留 CNS11643 的相對來源順序。第一方詞例加分永遠小於一級，不會讓次常用字跨級超越常用字；這是久空自身詞表的排序訊號，並非匯入語料字頻。使用者實際提交選字後，該字會在下一次同音單字查詢時優先於未選過的字；同音字依「手動置頂、選用次數由多到少、次數相同時最近選用、內建排序」依序排列。已開啟的候選快照不會在操作途中跳動，尚未送進 App 就被丟棄的組字也不會留下學習紀錄。

完成第二個以上的音節時，久空也會查詢內建詞資料與個人詞庫，最長的完整尾端讀音優先。例如依序輸入 `h k 4 g 4`（`ㄘㄜˋ ㄕˋ`），第一音會依第一方詞例預覽「測」，第二音完成後第一候選成為「測試」；按 Return、Space 或直接輸入下一音即可用整詞取代暫存單字。第一方詞表位於 `Data/JiukongPhrases/phrases.tsv`，目前有 1,965 筆，涵蓋日常對話、時間、人物、生活、交通、工作學習、電腦操作與常見描述。全部由 AI 為本專案逐筆編寫，字音以專案內釘選的 CNS11643 資料自動檢查，不含外部詞庫或匯入詞頻；未收錄的詞仍可透過 Shift 範圍造詞與本機學習補充。

同一個唯讀字典另外合併教育部《成語典》的 1,642 筆四字主條，以及《重編國語辭典修訂本》的 33,295 筆四字條目。這些政府來源資料不是第一方詞表或 AI 創作內容；專案只保留來源的詞目與讀音，不匯入釋義或詞頻，也不把它們計入第一方詞例排序訊號。詳細來源、篩選方式與 CC BY-ND 3.0 TW 授權說明見 [Third-Party Notices](THIRD_PARTY_NOTICES.md)。

若 CNS11643 缺少久空需要支援的常用單字讀音，會逐筆記錄在 `Data/JiukongCharacters/characters.tsv`，由建置器驗證後合併；例如「麼／˙ㄇㄛ」與「剔／ㄊㄧˋ」，因此輸入對應讀音即可直接選到這些字。補充項目必須是 CNS 已收字元，並沿用其 CNS 字碼與來源位置。

同一機制可處理「測試中請稍後」：前五音可不停頓直接繼續，完成 `ㄏㄡˋ` 後會把六音完整句列為第一候選，而不是只顯示「後」的單字候選。候選格會依詞的長度自動加寬，不會把整句裁成一個字。

`1`、`q`、`a`、`z` 都是聲母鍵；要連續驗證 `ㄅㄆㄇㄈ`，請在每個鍵後按 Enter 或一聲 Space 完成音節。直接連按四鍵會合理地以後一個聲母取代前一個。

### 中文標點

中文模式下的全形標點放在 Shift；注音鍵不加 Shift 時維持原本的注音：

```text
Shift+,  ，      Shift+.  。      Shift+/  ？      Shift+;  ：
Shift+1  ！      Shift+6  …       Shift+9  （      Shift+0  ）
Shift+-  —
[  「            ]  」            \  、
Shift+[  『      Shift+]  』      Shift+\  ／
```

`…` 與 `—` 每次插入一個，慣用的 `……`、`——` 請按兩下。`[`、`]`、`\` 不在注音鍵盤配置內，所以不必按 Shift；`\` 輸入 `、`，`Shift+\` 輸入 `／`。表格以外的鍵仍交回目前 App 與 macOS 鍵盤配置，英文模式完全不受影響；也就是說中文模式下 `[` 不會再打出半形 `[`，需要半形時請切到英文模式。

標點會結束目前的讀音但不結束整段組字：按下標點時會先把反白候選或未完成注音收進 buffer，再把標點接在後面，仍是 marked text，Return 時才一起送出，Backspace 也能直接刪掉標點。標點本身沒有讀音，不會單獨成為查詢音節；但可作為原文單位納入使用者詞，例如把 `嗎？` 造成一個「一音＋標點」的精確詞組。

### 中英文切換

中文模式下單獨按一下左 Shift 或右 Shift，會切換到英文模式；再單獨按一次會切回中文。按住 Shift 搭配字母、數字、方向鍵或其他修飾鍵時不會切換；即使 Word 先把 Shift 放開事件送給輸入法、稍後才送組合鍵，久空仍以 macOS 的系統按鍵計數辨認它是組合鍵，所以英文模式的 `Shift+9` 會保持英文並輸入半形 `(`。切換會選取久空對應的 macOS 輸入 mode，使選單列圖示同步顯示紅「中」或藍 `A`；macOS 也可能短暫顯示其原生輸入來源提示。若已開啟游標指示器，久空會直接把它更新為相應的「中」或 `A`。

英文模式不合成注音，也不自行產生 ASCII；久空會把字母、數字、標點、Space、Return、Backspace、dead key 與 App 快捷鍵原樣交給目前的 macOS 鍵盤配置處理。目前中英文狀態在同一個輸入法 process 的所有 client 間共享，process 重新啟動後預設回到中文。要用哪一側 Shift（左右皆可／只用左／只用右／關閉）可在設定視窗選擇，並會保存下來。

若切換模式時仍有未完成注音或候選，久空會先完成一次目前組字再切換，避免吃字或重複插入。因 Milestone 5 需要接收 Shift 的 modifier 事件，久空也會透過 InputMethodKit 公開事件路徑處理 client 內的滑鼠按下：先完成現有組字，再把點擊交回 App。

### 游標指示器

設定視窗的「游標指示器」分頁可讓目前輸入模式常駐顯示在滑鼠游標旁，功能來自獨立工具 `lang-cursor`（付費的 StoreKit 授權部分未移植）：

- 位置：游標右上／右側／右下；
- 追蹤：固定距離（貼齊游標）或跟隨游標（帶尾隨感的緩動）；
- 文字大小五段；
- Caps Lock 開啟時可一併顯示 `⇪`，並有五段大小；
- 中文與英文各自的自訂文字（最多 4 字元）與顏色，留空即用預設的「中」與 `A`，顏色為紅／藍。

指示器**預設關閉**。它只在久空是目前輸入來源時顯示，切換到其他輸入法會自動消失 —— 想在所有輸入法下都看得到，仍需使用獨立的 `lang-cursor`。Caps Lock 狀態以每 0.2 秒輪詢取得，不需要輸入監控權限。

### 個人選字學習

Space、Return、數字鍵、滑鼠點選，以及切換欄位／輸入來源前實際提交的候選，都只會學習一次。Escape、Backspace、方向鍵移動、空的數字槽與字面注音 fallback 不會改變學習資料。相同文字的不同讀音分開統計；置頂狀態是獨立的最高排序層級，置頂候選會顯示 `★ ×`，點 `×` 只會取消置頂而不刪除使用次數。也可在設定視窗的清單中逐項調整。

在設定視窗關閉「自動學習」後，就不再累積新的使用次數；既有紀錄仍會影響排序，Shift 造詞也仍可使用。

選定候選只會先建立待提交事件；整段 composition 真正送進 App 後才會學習。被 Escape 丟棄、被 Backspace 刪除或被詞候選取代的內容不會留下錯誤計數。

### 使用者造詞

每個已選候選都保留其精確注音。先用 ←／→ 把游標定位在造詞範圍的一側：Shift+← 會選取游標左邊最多兩個相鄰讀音字，例如 `合併｜成` 會選到「合併」；Shift+→ 會選取游標右邊最多兩個相鄰讀音字。進入範圍選取後，Shift+← 與 Shift+→ 可繼續擴張範圍的左、右邊界，久空自己的綠色浮動提示會明確框出目前範圍，例如「造詞範圍 2 音／2 字：【載入】」，不依賴目前 App 是否正確顯示 marked-text 反白。若沒有先定位，Shift+← 由 buffer 尾端開始，Shift+→ 由 buffer 開頭開始。範圍可包含相鄰標點；選取至少兩個讀音單位，或一個讀音加標點後按 Return，即把範圍文字、逐音注音與標點位置加入使用者詞庫，再一次提交整段 composition。儲存成功後，游標旁會顯示例如「已儲存：【載入】」並保留約十秒；若選錯，可按右側 `×` 精確刪除剛儲存的使用者詞與該組逐音注音，不會刪除文件中已送出的文字。這個功能只處理輸入法尚未提交的 buffer，不會讀取其他 App 已有的文字。

之後重打相同的完整逐音序列時，使用者詞會出現在最後一個音節的候選中。查詢是完整相等、最長後綴優先；目前不做詞首聯想，也不會未經確認自動補完整詞。置頂仍是最高排序層，未置頂的精確使用者詞則優先於一般未置頂單字。

所有詞候選（包含內建詞）右側都會顯示可點選的 `×`。刪除是以「文字 + 完整讀音」為單位並立即更新候選：自己造的詞會從使用者詞庫移除，內建詞則在個人資料庫寫下一筆刪除記錄，之後就不再出現在候選中。這筆記錄存在個人資料庫而不是內建字典裡，所以更新 App 或內建詞庫都不會把刪掉的詞救回來，使用者可以持續把候選訓練成自己的用詞習慣。單字候選仍然不會顯示刪除按鈕，否則該讀音可能沒有任何候選可選。

被刪除的內建詞可在設定視窗的「已刪除內建詞」分頁查看並逐筆恢復，也可在「資料」分頁一次全部恢復。如果同一個詞既是內建詞又已存在使用者詞庫，`×` 會同時移除兩者；純粹自己造的詞（內建詞庫沒有這個文字＋讀音）刪掉後不會列進「已刪除內建詞」；用 Shift+←／→ 造詞後那十秒內的 `×` 則只是撤銷剛剛的儲存，不會刪除同名的內建詞。

學習資料使用具 schema 版本的 SQLite，存放於 `~/Library/Application Support/JiukongZhuyin/user.sqlite`，不會寫進 `.app` bundle。schema v4 原地保留選字頻率、使用者詞與有順序的逐音讀音，記錄詞內注音與標點的對應，並保存已刪除內建詞的清單。內建字典另含專案自有的預設選字基準；個人資料庫無法使用時，輸入仍會安全使用這份內建排序。重新安裝或執行 `scripts/uninstall.sh` 不會刪除 Application Support 中的使用者資料。

iCloud 同步預設開啟，可在「資料」分頁關閉或手動要求立即同步。輸入與候選查詢永遠使用本機 SQLite，不等待網路；啟動時與持續使用期間會從同一 Apple Account 的 CloudKit 私有資料庫合併變更，本機異動則短暫合併後在背景上傳。同步的是逐筆學習記錄與游標外觀偏好，而非 SQLite 或偏好檔案；學習資料刪除會留下雲端 tombstone，避免離線的另一台 Mac 或重灌後把舊資料復活。CloudKit record name 只含穩定雜湊或偏好欄位識別，個人文字、注音、次數、時間、置頂值及偏好值均使用 CloudKit encrypted values。完整設計與部署前置條件見 [iCloud sync notes](docs/CLOUD_SYNC.md)。

### 設定視窗

在 macOS 輸入選單中選擇久空的「偏好設定…」即可開啟設定視窗，共六個分頁：

- **一般**：注音鍵盤配置（標準／倚天傳統／IBM）、Shift 中英文切換與 Option 組合鍵的行為說明、自動學習開關，以及是否顯示 CNS 第 3 字面以後的罕用與專門用字；
- **游標指示器**：在游標旁顯示目前輸入模式，可設定位置、追蹤方式、文字大小、Caps Lock 指示，以及中／英文各自的文字與顏色；
- **使用者詞**：列出所有自己造的詞與逐音注音，可搜尋、置頂或刪除單筆；
- **已刪除內建詞**：列出所有被刪除的內建詞與逐音注音，可搜尋並逐筆恢復；
- **選字紀錄**：列出所有已學習的單字讀音、次數與置頂狀態，可搜尋、置頂或刪除單筆；
- **資料**：iCloud 同步開關、狀態與立即同步，個人資料的 JSON 匯出／匯入，可分享的詞庫匯出／匯入，以及清除選字紀錄、清除使用者詞、恢復內建詞、清除全部。

設定存放在輸入法自己的 defaults domain，重新啟動後仍然有效；所有刪除與清除動作只影響個人學習資料並會送出同步 tombstone，不會動到內建字典本身，且都需要再次確認。刪除內建詞同樣只是在個人資料庫記下要隱藏哪一筆，內建字典檔案不會被修改，「清除全部」則會恢復所有被刪除的內建詞。開啟設定視窗前會先完成目前的組字。

刪除是以「文字 + 完整讀音」為單位，所以刪掉 `行／ㄒㄧㄥˊ` 不會影響 `行／ㄏㄤˊ`。

### 分享詞庫

「資料」分頁的「匯出詞庫…」會把你的詞庫做成一個可以直接給別人的 JSON 檔，內容是**哪些詞**，不是你的使用統計：所有自己造的詞（含你用過而被自動學起來的內建詞）與逐音注音、標點位置，以及你刪掉了哪些內建詞。次數、時間與置頂一律不寫進檔案，分享詞庫不會透露你打字的頻率。

內建字典本身不會複製進這個檔案。兩台 Mac 裝的是同一份內建詞庫，所以對方匯入後看到的詞跟你完全一樣，檔案卻只有幾 KB；同時也不會把內建資料（含教育部授權資料集）另外散布出去。

對方用「匯入詞庫…」讀進來。匯入是合併：新詞加入他的使用者詞庫，已經有的詞保留他自己的次數與置頂，不會被你的檔案蓋掉；重複匯入同一個檔案不會有額外變化。如果檔案裡有你刪掉的內建詞，匯入時會出現一個可取消勾選的選項，讓對方自行決定要不要一起隱藏那些詞。無法辨識的資料列會被略過並回報數量。匯入後的每一筆都能照常在候選視窗按 `×` 或到設定裡刪除、恢復。

分享詞庫檔與下面的個人資料備份檔是兩種不同的文件，各有各的 `format` 標記；拿錯檔案匯入時會直接告訴你該用哪一個按鈕。

### 匯出與匯入

個人資料匯出是**備份**而不是分享用的詞庫：它包含選字紀錄與使用次數。匯出會寫出帶版本的 JSON，時間一律使用 UTC 毫秒，不含本機的內部 ID，並且包含已刪除的內建詞清單，所以還原備份不會把刪掉的詞救回來。匯入是合併而非覆蓋：次數與時間取較大／較新者、建立時間與刪除時間取較早者、置頂取聯集，因此重複匯入同一個檔案不會重複累加，也不會把次數變小或取消置頂。0.1.14 以前匯出的檔案沒有這份清單，仍然可以完整匯入。無法辨識的資料列會被略過並回報數量；若其中一筆無法套用，整次匯入會完整回復原狀。匯出檔沒有加密，內容是你打過與選過的字，請比照個人檔案保管。

## Requirements

- macOS 13 or later for the input method
- macOS 14 or later for the current unit-test target
- Xcode 26.6 or a compatible Xcode version with the macOS SDK

## Download and install

Public versions are distributed from [GitHub Releases](https://github.com/jiukong-labs/zhuyin/releases)
as universal, Developer ID-signed and Apple-notarized `.pkg` installers. The
installer places 久空輸入法 in `/Library/Input Methods`; macOS still requires
each user to approve and enable a newly installed input method in System
Settings. After every install or update, sign out of macOS and sign back in,
or restart the Mac, so macOS replaces its cached input-method process. Save
your work first. The installer shows this reminder on its completion screen.

See the [installation guide](docs/INSTALL.md) for verification, enablement,
updates, and removal. Maintainers should use the guarded release process in
[Public release](docs/RELEASING.md); the local script below is only for
development builds.

After installation, 久空 checks GitHub for a complete published release at
most once every 24 hours. The check sends no composition, learning, or user
phrase data. When an update is available, the input-source menu and Update
settings pane can download the `.pkg` and adjacent checksum, verify SHA-256,
the expected Developer ID Installer team, and Gatekeeper acceptance, then
open the verified package in macOS Installer. Installer still requests
administrator approval because the package updates `/Library/Input Methods`.

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

The runtime dictionary is already checked in. To verify or regenerate it without network access, the builder uses the pinned, hash-validated CNS11643 snapshot; Jiukong's first-party character, phrase, and heteronym-override files; the MOE common/semi-common character tables; and the pinned MOE idiom and revised-dictionary phrase extracts:

```sh
./scripts/build-dictionary.sh
```

Normal app builds never download or parse the raw dictionary-source files.

## Install for local development

The installer builds a Release configuration, copies it to the current user's supported Input Methods directory, validates the bundle, then registers it and requests enablement through Apple's public Text Input Sources APIs. It does not switch away from your current input source:

```sh
./scripts/install.sh
```

The helper refuses to install when the public package is already present at
`/Library/Input Methods/Jiukong Zhuyin.app`. A user-level development copy and
the system-level public copy would have the same bundle identifier, allowing
the ad-hoc build to shadow the signed release and break launching or settings.
Use a dedicated test account/Mac, or remove the public installation before
installing a development build.

The default build uses an ad-hoc local signature. A maintainer with an Apple Development certificate can select it without changing the project:

```sh
SIGNING_IDENTITY="Apple Development: Your Name (TEAMID)" ./scripts/install.sh
```

The bundle identifier is `tw.idv.jiukong.inputmethod.zhuyin`. Two constraints were established by experiment on macOS 26 and both make registration fail silently:

The bundle is the parent of two modes that remain directly selectable from the
macOS input menu:
`tw.idv.jiukong.inputmethod.zhuyin.Chinese` and
`tw.idv.jiukong.inputmethod.zhuyin.English`. Their first-party color icons
show red `中` and blue `A`. A standalone Shift selects the corresponding mode,
so the macOS input-menu icon and Jiukong's optional cursor indicator both
update to report the change. macOS may also show its native transient
input-source indicator.

- **The identifier must contain an `inputmethod` component that is not the last one.** `tw.idv.jiukong.inputmethod.zhuyin` and `tw.idv.inputmethod.zhuyin` register; `tw.idv.jiukong.zhuyin`, `tw.idv.jiukong.zhuyinim`, and `tw.idv.jiukong.zhuyin.inputmethod` do not. `TISRegisterInputSource` still returns `noErr` for the rejected ones, so the only symptom is that the source never appears.
- **No other bundle may claim the same identifier in LaunchServices.** A build product under `.build/`, or a deleted bundle whose record survives, can take the identifier over and make an already-registered input source disappear. Repair it with:

```sh
./scripts/register-input-source.sh
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
./scripts/run-acceptance.sh              # release-blocking input behavior matrix
./scripts/run-release-preflight.sh       # unit tests plus the installed matrix
./scripts/run-acceptance.sh eten         # after setting the arrangement preference
```

Each run launches its own TextEdit instance, types with real `CGEvent` delivery, compares the resulting text with the expectation, then restores the previous input source and closes the instance it launched. Existing TextEdit windows are untouched.

Every run first requires Option-A and Option-Z to produce Jiukong's literal
`az` before it types the requested scenario. The system keyboard layouts
produce different Option characters, so this proves that the client reached
Jiukong without mistaking its cursor indicator for a candidate panel. A run
that cannot prove the connection aborts instead of reporting a result.

The complete release-blocking contract and its script mapping are recorded in
[`docs/INPUT_BEHAVIOR_MATRIX.md`](docs/INPUT_BEHAVIOR_MATRIX.md). The default
script list comes from the Harness itself and CI verifies that none of those
required scenarios disappears silently.

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

Composition and candidate lookup stay on the Mac. When iCloud sync is enabled, Jiukong sends committed character-learning records, explicitly saved user phrases, and cursor-indicator appearance preferences to the current user's private CloudKit database; it does not upload uncommitted composition or document contents. Personal record values and preference values use CloudKit encrypted fields. Sync can be disabled in the Data settings pane, and manual JSON export/import remains available.

## Project

- GitHub: https://github.com/jiukong-labs/zhuyin
- Website: https://jiukong.cloudgate.org.tw
- License: [MIT](LICENSE)

The project-authored implementation and first-party phrase lexicon are AI-created for Jiukong and MIT-licensed. Third-party data keeps its own terms: the CNS11643 snapshot is covered by Taiwan's Open Government Data License 1.0, the MOE standard character tables are treated as public-domain government promulgations, and the MOE dictionary extracts are covered by CC BY-ND 3.0 TW. See [Third-Party Notices](THIRD_PARTY_NOTICES.md) for attribution, scope, and license details.
