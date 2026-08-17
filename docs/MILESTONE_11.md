# Milestone 11: cursor mode indicator

## Goal

Bring the free functionality of the separate `lang-cursor` menu bar utility into the input method itself, so the current mode is visible next to the mouse pointer without running a second application.

The paid parts of that project — the StoreKit trial and full-unlock products and their licensing gate — are deliberately not ported. Neither is its menu bar shell nor its 50-language menu localization; this settings window is Traditional Chinese, and the input method has no menu bar item.

## What carried over

```text
lang-cursor                          Jiukong
────────────────────────────────────────────────────────────────────
overlay near the mouse cursor    →   CursorIndicatorController
Fixed Distance / Follow Cursor   →   CursorIndicatorTracking
upper-right / right / lower-right →  CursorIndicatorPlacement
five overlay text sizes          →   CursorIndicatorTextSize
Caps Lock badge, hide + 5 sizes  →   CapsLockIndicatorSize + toggle
custom text per input source     →   custom text per language mode
custom color per input source    →   custom color per language mode
UserDefaults persistence         →   Preferences / PreferencesController
StoreKit trial and full unlock   →   not ported
menu bar item, 50 UI languages   →   not ported
```

The geometry, easing factor, tracking interval, size tables, and Caps Lock scale factors are carried over unchanged, so the indicator looks and moves the way the original does.

## Why the per-mode simplification

`lang-cursor` watches the system input source and has to classify it by keyword, falling back to `⌨︎` when a third-party method cannot be recognized. Inside the input method that whole problem disappears: it knows its own mode, so the indicator is driven by `LanguageModeController` and only ever shows Chinese or English. Custom text and color are therefore stored per mode rather than per input-source identifier, and there is no unknown state to render.

The consequence is the one real behavioral difference: the indicator exists only while Jiukong is the active input source. Switching to another input method hides it, because this process is no longer the one handling input.

## Behavior

`CursorIndicatorController` owns a single borderless, nonactivating panel, like the candidate window and the mode HUD. It ignores mouse events, joins all spaces, and never activates the process.

- A 30 Hz timer repositions the panel. `fixedDistance` snaps to the cursor; `followCursor` eases 24% of the remaining distance per sample, which reads as a light trail.
- Placement is computed by `CursorIndicatorGeometry` and clamped to the display holding the cursor, so the panel cannot be pushed off-screen and negative-origin displays work.
- Caps Lock is polled at 5 Hz through `CGEventSource.flagsState`, which needs no Input Monitoring permission and works even while another application holds key focus. The badge widens the panel; the panel is resized and repositioned in the same step so it never clips.
- Timers run only while the indicator is enabled *and* a client is using the input method. `activateServer` starts it, and every path that already resets transient state — deactivation, controller closure, palette hiding, input-source change — stops it.
- When the indicator is enabled, the transient Shift HUD is suppressed. Two indicators for one fact, in two different places, is worse than either alone.

Settings are read when a client activates, so a change applies on the next activation without an observer.

## Preferences

Seven new namespaced keys follow the Milestone 8 rules: pure, total decoding with per-field fallback, and no guessing at a future version. An empty stored string means "no override", so clearing the text field in the settings window restores `中` / `A` rather than blanking the indicator. Colors are stored as `#RRGGBB`; anything unparsable falls back to the default red or blue.

The indicator is **off by default**. An input method that already shows a transient HUD should not start painting a persistent overlay, and a 30 Hz timer, without being asked.

## Automated verification

The suite covers all earlier milestones plus:

- every placement sitting right of the cursor, ordered upper to lower, with the lower-right panel fully below it;
- clamping at the right and bottom edges, on a negative-origin display, with the cursor outside every display, and with no displays at all;
- easing moving toward the target without overshoot and converging on it;
- text sizes and Caps Lock scales growing monotonically, and the badge always widening and never shrinking the panel;
- default text and color per mode, trimming and the four-character limit, blank overrides falling back, hex normalization, malformed hex rejection, a color round trip, and one mode's override not disturbing the other;
- indicator preferences round-tripping, cleared overrides decoding as no override, and unknown placement/tracking/size/color values falling back per field.

On 2026-08-17, Xcode 26.6 completed all 292 Debug tests with no failures. The settings tab and the overlay panel were both rendered and captured: the tab shows the enable switch, placement, tracking, size, Caps Lock controls, and the per-mode text fields and color wells; the overlay drew `中` in red in a 56×38 transparent panel at the huge text size. The overlay was exercised through a temporary launch argument that was removed afterwards, because the indicator cannot otherwise be seen until the input source is enabled by the user.

Installed acceptance — enabling the indicator from the settings window and watching it track the cursor and follow a Shift toggle in a real client — is still pending, because the input source is awaiting approval in System Settings.

## Intentional limitations

The indicator cannot show anything while another input method is active, which is exactly what the standalone utility exists for; the two are complementary rather than equivalent. There is no menu bar item, no per-application behavior, and no localization beyond Traditional Chinese. Caps Lock polling continues at 5 Hz while the indicator is enabled and a client is active.
