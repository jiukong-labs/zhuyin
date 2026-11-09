# Input behavior regression matrix

This matrix records user-visible keyboard contracts that must survive every
input-method, event-routing, candidate, or input-source change. Unit tests
cover pure routing and state transitions. The installed acceptance harness is
the release gate for behavior that crosses `CGEvent`, InputMethodKit, and a
real client application.

Run the complete installed gate after installing the working build:

```sh
./scripts/install.sh
./scripts/run-acceptance.sh
```

Use an account or Mac without a simultaneous public installation under
`/Library/Input Methods`. The development installer deliberately refuses to
create a second copy with the production bundle identifier.

The complete local release preflight also runs source checks and the full unit
test suite before this installed matrix:

```sh
./scripts/install.sh
./scripts/run-release-preflight.sh
```

The harness itself owns the default release list. `run-acceptance.sh` reads
that manifest instead of maintaining a second copy, while CI runs
`check-acceptance-matrix.sh` to prevent a required scenario from silently
leaving the default gate.

| Contract | Installed script | Expected result |
| --- | --- | --- |
| Basic Chinese conversion and commit | `single` | `ㄨㄛˇ` commits `我` once |
| Candidate number after explicitly opening the chooser | `number-one` | slot 1 commits the displayed candidate |
| A number-row Zhuyin key continues composition before the chooser opens | `continuous` | `我不` |
| Chinese-mode Option letters and digits are explicit ASCII | `option-ascii` | `azAZ09` |
| Option ASCII finalizes an active candidate exactly once | `option-after-composition` | `我a1` |
| Option ASCII stays at a positioned caret like punctuation | `option-ascii-insertion` | `測｜試` + `⌥6⌥A` commits `測6a試` |
| Standalone Shift switches Chinese → English → Chinese | `shift-round-trip` | English `1`, then Chinese `我` |
| The within-Jiukong Shift style switches language without selecting another source | `shift-within-input-method` | English `1`, and the Chinese mode stays selected |
| Exact built-in phrase replacement | `builtin-phrase` | `測試` |
| A provisional phrase can extend to a longer exact phrase | `provisional-phrase-extension` | `ㄒㄧㄥˊ ㄕˋ ㄌㄧˋ` previews `形式`, then becomes `行事曆`; never `形式立` |
| Phrase extension preserves a preceding phrase's complete span | `phrase-homophone-boundary` | `室友` + `有沒有` remains `室友有沒有` |
| The chooser offers a phrase across a provisional phrase without preferring it | `provisional-phrase-split` | `ㄕˋ ㄧㄡˇ ㄇㄟˊ ㄧㄡˇ` previews `室友沒有`; Down then `2` commits `是有沒有` |
| Longest exact sentence replacement | `sentence` | `測試中請稍後` |
| Revision caret and candidate arrows remain two-stage | `revision-arrows` | unchanged `測試` |
| Revision opens the full candidate grid with one Down, and rows move with Up/Down | `revision-candidate-rows` | `是室`: two standalone `ㄕˋ` compositions select row 1 after Down/Up, then row 2 after Down |
| Candidate arrows wrap in both directions instead of stopping at an edge | `candidate-wrap` | `有` |
| Backspace edits the reading left of the revision caret | `revision-backspace` | `ㄘㄜ試` |
| Backspace keeps working after a revised reading is fully erased | `revision-backspace-exhausted` | `ㄨㄛ試` |
| Forward Delete edits the reading right of the revision caret | `revision-forward-delete` | `測ㄕ` |
| Escape cancels without leaking text | `escape` | empty document |
| Shift punctuation stays Chinese | `punctuation` | `我，我` |
| Revision caret stops immediately before punctuation | `punctuation-caret` | `測試？| → 測試|？`; Backspace commits `測ㄕ？` |
| Punctuation and subsequent input stay at the positioned caret | `punctuation-insertion` | `測｜試` + `？！我？` commits `測？！我？試` |
| Direct bracket and slash punctuation mappings | `brackets` | `「我」、／` |
| Shift-Left phrase selection | `phrase` | first Return saves and retains composition; second commits `久空` |
| Shift-Right phrase selection | `phrase-right` | first Return saves and retains composition; second commits `久空` |
| Saving a prefix preserves the editable suffix | `phrase-continue` | save `測試` in `測試我`, then Forward Delete edits `我`; final Return commits `測試ㄨㄛ` |
| Removing a phrase candidate, built-in ones included | mouse only — unit tests | the exact text+reading identity stops appearing and stays gone across dictionary updates |
| Jiukong returns after a password field forced ABC, also when the page opens with the password field focused or Chrome is left for another app | manual — unit tests | 0.3 s after the field ends, or after another app comes to the front while Chrome still holds secure input, the Jiukong mode that was selected is selected again; under Terminal's Secure Keyboard Entry a switch to ABC stays |
| A moment in which macOS does not select the 久空 mode does not keep 「久空中文」 selected | manual — unit tests | with the within-Jiukong style, 「久空中文」 chosen from the input menu becomes 「久空」 at once, and again after a fallback once its retry delay has passed; the fallback's `log show` trace names that delay |
| Jiukong's overlays never cover a focused payment or authorization screen | manual — unit tests | the cursor indicator and Shift HUD hide while the sheet has focus; with the pointer on the sheet PassKit keeps logging `Payment UI is occluded: false` and Touch ID stays offered |

`revision-candidate-rows` uses isolated learning data and separate single-reading
compositions, so preceding readings cannot introduce complete phrase candidates.
The bundled `ㄕˋ` candidates span more than nine slots: row 1 starts with `是`,
row 2 with `室`. Each composition accepts the preview with Space and positions
the revision caret with Left/Right. The first Down must open the full grid.
The next Down followed by Up and `1` must commit `是`; a second composition
uses Down, Down, `1` to commit `室`. The combined `是室` checks both the return
to row 1 and actual movement to row 2; ignoring both row arrows cannot pass.
The first commit selects the already-first candidate and preserves the next
lookup's order. This replaces the unstable `測是` expectation, whose revision
lookup could put the complete phrase `測試` in slot 1.

The candidate window's inline `×` is a mouse-only control, so the keystroke
harness cannot drive it. That row is covered by unit tests over
`CharacterCandidateProvider`, `UserLearningStore`, and the archive and cloud
record models instead, matching how the pre-existing user-phrase delete is
covered.

The payment-screen row cannot be scripted: opening an App Store or Apple
Pay sheet starts a real purchase flow, and the harness types into TextEdit
only. `SecureSystemUIFocusTests` covers the focus decisions with the client
order traced from real purchases. On an installed build, open a purchase
sheet, rest the pointer on it with Jiukong's Chinese mode selected and the
indicator on, cancel the sheet, and watch:

```sh
/usr/bin/log stream --style compact --predicate 'process CONTAINS "PaymentAuthorizationUIExtension" AND eventMessage CONTAINS "occluded"'
```

Before the fix every pass of the indicator over the sheet logged `true` and
removed the Touch ID prompt.

The password-field row cannot be scripted: the harness types into TextEdit
only, and the failures needed Chrome, a page whose password field had focus
as it loaded, and a move to another app while Chrome kept secure input on.
`SecureFieldSourceRestorerTests` covers the decisions, with the order of
events traced on 2026-11-09. On an installed build, open such a login page in
Chrome with Jiukong selected, leave for another app, and check each switch
and restore, with the app holding secure input and the app in front, with:

```sh
/usr/bin/log show --last 1h --style compact --predicate 'subsystem == "tw.idv.jiukong.inputmethod.zhuyin" AND eventMessage CONTAINS "secure field guard"'
```

Before the fix the first case logged nothing at all, and the second logged
only a watch until the user chose Jiukong from the input menu.

The 久空-mode fallback row cannot be scripted: the refusal followed a
Chrome password field, apparently while secure input was still turning off
and on, which the TextEdit harness cannot reproduce on demand.
`JiukongModeRetryTests` covers the retry schedule. On an installed build
with the within-Jiukong style, choose 「久空中文」 from the input menu; it
must become 「久空」 at once. After a fallback, check the reason and the
next attempt with:

```sh
/usr/bin/log show --last 1d --style compact --predicate 'subsystem == "tw.idv.jiukong.inputmethod.zhuyin" AND eventMessage CONTAINS "久空 mode not selected"'
```

Before the fix one fallback disabled the 久空 mode until the process
restarted, so 「久空中文」 chosen from the input menu stayed selected.

`eten` and `ibm` remain opt-in because they require changing the persisted
keyboard arrangement before the input-method process starts. They must still
be run whenever their layout tables or shared event routing changes.

`shift-within-input-method` is part of the default release gate because new
installations default to `withinInputMethod`. It compares the selected source
after client activation with the source after the Shift tap; activation may
first normalize the Chinese mode to the Jiukong mode. An explicit
`inputSource` preference should fail this unchanged-source check. The release
preflight isolates both user learning and all saved preferences to exercise
fresh-install defaults, then restores the original data and preferences.

The harness focuses the isolated TextEdit editor and checks that its process
is frontmost before every system keyboard event. It keeps the input-method
service running across cases so repeated termination cannot race client
reconnection. A case that loses focus or fails the Option ASCII connection
proof is aborted rather than counted as a behavior pass. The runner retries
a failed connection proof once in a new isolated client. It never retries
a behavior mismatch or a lost-focus abort.

## Change rule

Any intentional change to a contract above must update, in the same focused
change, its product documentation, pure unit tests, installed acceptance
expectation, and this matrix. A passing test that merely encodes a newly
changed behavior is not sufficient evidence that the product contract was
meant to change.
