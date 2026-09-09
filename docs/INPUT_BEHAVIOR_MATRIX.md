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
| Standalone Shift switches Chinese → English → Chinese | `shift-round-trip` | English `a`, then Chinese `我` |
| Exact built-in phrase replacement | `builtin-phrase` | `測試` |
| A provisional phrase can extend to a longer exact phrase | `provisional-phrase-extension` | `ㄒㄧㄥˊ ㄕˋ ㄌㄧˋ` previews `形式`, then becomes `行事曆`; never `形式立` |
| Phrase extension preserves a preceding phrase's complete span | `phrase-homophone-boundary` | `室友` + `有沒有` remains `室友有沒有` |
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

`eten` and `ibm` remain opt-in because they require changing the persisted
keyboard arrangement before the input-method process starts. They must still
be run whenever their layout tables or shared event routing changes.

## Change rule

Any intentional change to a contract above must update, in the same focused
change, its product documentation, pure unit tests, installed acceptance
expectation, and this matrix. A passing test that merely encodes a newly
changed behavior is not sufficient evidence that the product contract was
meant to change.
