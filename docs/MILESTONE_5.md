# Milestone 5: single-Shift language switching

## Goal

Add Windows-style standalone Shift switching without confusing a normal Shift shortcut with a language toggle. Chinese mode keeps the existing Zhuyin composition and custom candidate window. English mode bypasses the parser and returns keyboard events to the client application and its current macOS keyboard layout.

This milestone deliberately does not add persistent preferences, user learning, phrase composition, punctuation mapping, or settings.

## Shift gesture state

Every `InputController` owns one `ShiftToggleController` because InputMethodKit creates a controller per client session. The state machine has no timeout:

1. A left or right Shift `flagsChanged` press starts a possible standalone gesture.
2. Any key-down, another modifier transition, an already-held Command/Control/Option/Fn modifier, or the other Shift marks the gesture as a chord. An already-locked Caps Lock state does not block a standalone Shift tap, while changing Caps Lock during the gesture does.
3. Releasing the same Shift toggles only when the gesture was never marked as a chord and the configured side is allowed.
4. Activation, deactivation, controller closure, source switching, and client mouse-down reset pending gesture state.

The first version permits both Shift keys. The pure policy already represents both, left only, right only, and disabled so Milestone 8 can persist the setting without changing the gesture recognizer. A letter key-up does not need to be observed: its earlier key-down permanently disqualifies that Shift gesture.

`LanguageModeController` owns the process-wide runtime mode, while the gesture tracker remains per client. This keeps the mode stable when the user changes fields or applications, without persisting an unspecified state across process launches. A new process starts in Chinese mode.

## InputMethodKit routing

Modifier press and release arrive as `NSEvent.EventType.flagsChanged`, so `InputController.recognizedEvents(_:)` now declares key-down, flags-changed, and client mouse-down masks. Event handling order is:

```text
NSEvent
  → ShiftToggleController observes modifier/key state
  → standalone Shift finalizes active composition once and toggles mode
  → English mode returns key-down to the client unchanged
  → Chinese mode continues through candidate and Zhuyin routing
```

English mode never calls `insertText` with synthesized event characters. Returning `false` preserves the host keyboard layout, capitalization, dead keys, repeats, text substitutions, and Command shortcuts.

Apple's default click-outside composition handling applies only to input methods recognizing exactly key-down. Milestone 5 therefore recognizes client left, right, and other mouse-down events explicitly. An active composition is finalized idempotently, and the event is returned to the client. This intentionally gives every client mouse-down the same predictable finalization rule, including a click inside the marked text; the input method does not install a global event monitor.

## Mode indicator and lifecycle

`LanguageModeHUD` is one reusable borderless, nonactivating panel. It displays the cursor indicator's configured `中` or `A` text, color, size, and placement for 0.75 seconds beside the pointer, stays above the client level, cannot become key or main, and ignores mouse events. Each presentation receives a UUID. Timer and hide operations must match that UUID, so an old controller or timer cannot hide a newer client's indicator.

Switching away from Jiukong, deactivation, palette hiding, and controller closure reset the pending Shift gesture and hide only the HUD owned by that controller. The shared language mode itself remains unchanged until the input-method process exits.

## Automated verification

The Debug suite covers all earlier milestones plus:

- standalone left and right Shift press/release;
- Shift with letters, arrows, numbers, Command, Control, Option, Fn, a Caps Lock transition, a pre-existing Caps Lock state, and both Shift keys;
- modifier-first and Shift-first chord ordering;
- both/left/right/disabled side policy;
- unmatched releases and lifecycle-style state reset;
- independent per-client gesture state driving one shared language mode;
- Chinese → English → Chinese mode transitions.

Run:

```sh
xcodebuild -project "Jiukong Zhuyin.xcodeproj" -scheme "Jiukong Zhuyin" -configuration Debug -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData test
xcodebuild -project "Jiukong Zhuyin.xcodeproj" -scheme "Jiukong Zhuyin" -configuration Release -destination "generic/platform=macOS" -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

On 2026-08-15, Xcode 26.6 with the macOS 26.5 SDK completed all 99 Debug tests without failure, static analysis succeeded, and the generic Release build produced a universal `arm64`/`x86_64` application. The only build warning was Xcode's informational AppIntents metadata message for a target that intentionally has no AppIntents dependency.

## Installed acceptance results

The ad-hoc-signed Release bundle was installed and exercised through real targeted `CGEvent → NSEvent → IMKInputController → IMKTextInput` delivery in an isolated TextEdit process:

```text
Chinese j i 3, Return                  → 我 exactly once
left Shift tap                         → transient A; TextEdit remains focused
English letters/digits/punctuation     → client Latin text; no marked text or candidates
Shift+A, then an unmodified letter     → uppercase A plus Latin letter; mode remains English
Command held before Shift, then j i 3  → no toggle; Chinese 我 remains active
right Shift tap                        → transient 中; TextEdit remains focused
Chinese j i 3, Return                  → 我 exactly once
unfinished j i, then Shift tap         → literal ㄨㄛ once, then English mode
candidate j i 3, Right, then Shift tap → highlighted 倭 once, panel hidden, then English mode
client click followed by Escape        → ㄨㄛ remains committed; click and focus reach TextEdit
second isolated TextEdit client         → inherits the process-wide English mode
click through visible HUD onto text     → caret moves and input reaches TextEdit beneath the HUD
```

Both HUD labels disappeared within the specified 0.5–1 second interval and never stole keyboard focus. The HUD is click-through, and client mouse finalization preserved the earlier candidate and raw-composition lifecycle guarantees.

## Intentional limitations

Shift behavior is fixed to both keys until Milestone 8 provides persistent preferences. Candidate ordering remains the deterministic CNS source order; Milestone 6 will add local user ranking. Phrase composition, user dictionaries, import/export, and settings remain outside this milestone.
