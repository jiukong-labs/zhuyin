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
| Longest exact sentence replacement | `sentence` | `測試中請稍後` |
| Revision caret and candidate arrows remain two-stage | `revision-arrows` | unchanged `測試` |
| Backspace edits the reading left of the revision caret | `revision-backspace` | `ㄘㄜ試` |
| Backspace keeps working after a revised reading is fully erased | `revision-backspace-exhausted` | `ㄨㄛ試` |
| Forward Delete edits the reading right of the revision caret | `revision-forward-delete` | `測ㄕ` |
| Escape cancels without leaking text | `escape` | empty document |
| Shift punctuation stays Chinese | `punctuation` | `我，我` |
| Revision caret stops immediately before punctuation | `punctuation-caret` | `測試？| → 測試|？`; Backspace commits `測ㄕ？` |
| Direct bracket and slash punctuation mappings | `brackets` | `「我」、／` |
| Shift-Left phrase selection | `phrase` | `九空` |
| Shift-Right phrase selection | `phrase-right` | `九空` |

`eten` and `ibm` remain opt-in because they require changing the persisted
keyboard arrangement before the input-method process starts. They must still
be run whenever their layout tables or shared event routing changes.

## Change rule

Any intentional change to a contract above must update, in the same focused
change, its product documentation, pure unit tests, installed acceptance
expectation, and this matrix. A passing test that merely encodes a newly
changed behavior is not sufficient evidence that the product contract was
meant to change.
