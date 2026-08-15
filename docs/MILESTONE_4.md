# Milestone 4: expandable candidate window

## Goal

Replace the Milestone 3 `IMKCandidates` panel with a Jiukong-owned macOS candidate window. A compact view should support fast selection, while the first Down Arrow expands the same candidate snapshot without committing or moving the highlight. Large result sets must remain reachable through keyboard, mouse, and scrolling.

This milestone deliberately does not add phrase conversion, frequency ranking, user learning, punctuation, Shift language switching, or settings.

## Candidate state and commands

`CandidateSession` is the canonical state for one completed reading. It owns the immutable, stably deduplicated dictionary snapshot, absolute highlighted index, compact/expanded mode, and the nine-item row used by number selection.

`CandidateCommandRouter` maps candidate-mode physical key codes to semantic commands. It accepts the `.function` and `.numericPad` flags inherently attached to macOS navigation keys, but rejects Command, Control, Option, and Shift shortcuts. `CandidateCommandReducer` then returns either an updated session or an explicit controller side effect. This keeps keyboard behavior out of the AppKit view and prevents navigation from accidentally committing a candidate.

Behavior:

- compact mode shows up to nine candidates from the highlighted selection row;
- the first Down Arrow changes only the mode to expanded;
- expanded mode is a nine-column by three-row viewport, so a normal screen shows up to 27 candidates at once;
- Left/Right move one item, expanded Up/Down move one grid row, Home/End move to the boundaries, and Page Up/Page Down move by nine candidates in compact mode or 27 candidates in expanded mode;
- top-row `1`–`9` select from the nine-item row containing the highlight; an empty final-row slot is consumed without changing text;
- Space commits candidate zero, while Return and Keypad Enter commit the highlight;
- Escape cancels the complete candidate composition;
- Backspace closes candidates, restores the completed `BopomofoSyllable`, removes its last input component, and resumes marked-text editing. This also removes the invisible first-tone component correctly.

Outside candidate mode, the Taiwan standard Zhuyin physical layout remains unchanged. In particular, top-row digits are still Zhuyin keys; numeric-keypad input is passed through normally.

## AppKit presentation

The process owns one reusable `CandidateWindowPresenter`, regardless of how many `IMKInputController` instances InputMethodKit creates. Every candidate session has a UUID owner token that remains stable across presentation updates. A replacement first asks the previous controller to finalize its session; mouse callbacks and hide requests must match the token, so an old client cannot commit through or dismiss a newer client's window.

The presenter uses a borderless, nonactivating `NSPanel` containing an `NSScrollView` and standard `NSButton` cells. The panel cannot become key or main, is ordered without activating the input-method process, and stays one level above the client window. Buttons accept the first mouse click and expose candidate position, text, selection state, and an accessibility press action. Keyboard focus and all key handling remain in the host application.

Only the compact row is built in compact mode. Expanded mode lays out the complete immutable snapshot. The viewport shows at most 27 items at its preferred size; scroll axes are enabled whenever the actual document exceeds the screen-clamped viewport, including on unusually small displays. Keyboard updates scroll the highlighted button into view, while native `NSScrollView` behavior owns wheel and momentum scrolling.

## Caret and screen placement

`InputController` obtains a screen-coordinate anchor from the public `IMKTextInput` marked range and `firstRect(forCharacterRange:actualRange:)`, with the public line-height rectangle as a fallback. The panel level is `client.windowLevel() + 1`.

Pure placement logic:

1. Select the visible frame containing the caret, or the nearest visible frame when the caret is temporarily outside all displays.
2. Inset that frame by eight points.
3. Prefer six points below the caret.
4. Flip above the caret when the lower side does not fit.
5. Cap an oversized viewport and clamp both axes inside the selected visible frame.

The calculation accepts negative global coordinates and does not assume the first display begins at `(0, 0)`. It reads `NSScreen.screens` and `visibleFrame` for every presentation instead of caching display geometry.

## Process policy and lifecycle

Milestones 1–3 used `LSBackgroundOnly`. Milestone 4 declares only `LSUIElement`: an AppKit background-only process is prohibited from creating windows, whereas an agent application may own the nonactivating panel and remain absent from the Dock.

Candidate commit, cancellation, Backspace, client-requested commit, input-source deactivation, palette hiding, and controller closure all invalidate their owner token and remove the panel through the same state paths. A lifecycle callback from an old controller cannot hide the current controller's panel. Missing or corrupt dictionary data still falls back to literal Bopomofo.

InputMethodKit lifecycle callbacks remain the primary finalization path. As a public-API safety net, each controller observes Carbon's distributed selected-input-source notification with immediate delivery. It re-reads the current source identifier and finalizes only after a confirmed switch away from Jiukong; raw marked Bopomofo and an active candidate therefore cannot remain orphaned if a programmatic source change omits the normal deactivation callback.

## Automated verification

The Debug suite covers all Milestones 1–3 behavior plus:

- first-Down expansion and command/reducer separation from commit side effects;
- four-arrow grid navigation, first/last, page movement, and ragged-grid boundaries;
- top-row number selection, invalid final slots, Space-first, Return-highlighted, cancellation, and Backspace effects;
- 20, 27, and 28-candidate sizing, normal and screen-constrained scroll axes;
- horizontal/vertical scroller cross-effects and scroller-thickness propagation;
- below/above placement, left/right clamping, oversized panels, negative-origin displays, and nearest-display fallback;
- restoration and complete component-by-component deletion of every tone and `ㄐㄧㄢˋ`;
- owning, foreign, and unavailable input-source identifiers in the source-change finalization policy.

Run:

```sh
xcodebuild -project "Jiukong Zhuyin.xcodeproj" -scheme "Jiukong Zhuyin" -configuration Debug -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData test
xcodebuild -project "Jiukong Zhuyin.xcodeproj" -scheme "Jiukong Zhuyin" -configuration Release -destination "generic/platform=macOS" -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

On 2026-08-15, Xcode 26.6 with the macOS 26.5 SDK completed all 82 Debug tests with no failures, static analysis succeeded, and the generic Release build produced a universal `arm64`/`x86_64` application. Xcode emitted only its informational AppIntents metadata warning because this target intentionally has no AppIntents dependency. The default ad-hoc-signed Release bundle was installed, passed strict code-signature validation, matched the built executable byte for byte, and remained registered and enabled through the public Text Input Sources APIs after the `LSUIElement` change.

## Installed acceptance results

The installed build was exercised through the real `NSEvent → IMKInputController → CandidateWindowPresenter → IMKTextInput` path. Each row below began with an empty isolated TextEdit document and a fresh reading unless it continues an explicitly shown sequence:

```text
r u 0 4                                      → compact ㄐㄧㄢˋ; nine cells; 件 highlighted
r u 0 4, Right × 2, Return                   → 建 exactly once; panel hidden; TextEdit focus retained
r u 0 4, Down                                → 27 visible candidates; 件 still highlighted; no commit
r u 0 4, Down, Down                          → candidate 10 腱 highlighted; no commit
r u 0 4, Down, Down, Page Down, 1            → candidate 37 僣 exactly once
j i 3, Right, Space                          → 我 exactly once; no trailing U+0020 space
j i 3, Backspace, Backspace                  → marked ㄨㄛ, then ㄨ; candidate panel closed
j i 3, real mouse click on candidate 2       → 倭 exactly once; TextEdit focus retained
r u 0 4, Down, real mouse-wheel scroll       → viewport advances without commit or focus loss
```

Moving the isolated TextEdit window to the active display's lower-right corner kept the expanded panel inside the visible frame and flipped it above the caret. Public TIS switches with candidate and raw Bopomofo compositions, a separate real input-menu switch, and handoff between two isolated TextEdit clients each left at most one panel and finalized the prior composition at most once.

This validation Mac had one physical display, so multi-display behavior was not physically exercised. Negative-origin, nearest-display, and per-display boundary behavior remain covered by automated geometry tests.

## Intentional limitations

Candidate order remains deterministic CNS11643 source order, not frequency order. The custom window displays single-character candidates only. Phrase conversion, candidate ranking, learning, pinning, user dictionaries, alternate layouts, punctuation, Shift language mode, and settings belong to later milestones.
