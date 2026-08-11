# Architecture

Milestone 2 adds standard Zhuyin keyboard composition while keeping the native macOS boundary separate from language logic.

## Process boundary

`main.swift` validates the bundle configuration, creates exactly one `IMKServer`, and starts the background AppKit run loop. InputMethodKit creates one `InputController` for each client input session.

`InputController` accepts only unmodified key-down events that belong to the current composition. It translates an `NSEvent` into a semantic physical key, asks the composition session for a result, then performs the requested `IMKTextInput` marked-text update or commit. Unhandled events are returned to the client application.

## Composition pipeline

```text
NSEvent key code
  → MacVirtualKeyResolver
  → KeyboardKey
  → StandardZhuyinLayout
  → BopomofoComponent
  → BopomofoParser / BopomofoSyllable
  → BopomofoInputSession result
  → InputController
  → IMKTextInput marked text or committed text
```

- `KeyboardLayout` is the extension point for a future keyboard arrangement. Milestone 2 provides only `StandardZhuyinLayout`.
- `BopomofoSyllable` stores one optional initial, medial, final, and tone. It renders them in canonical order while separately preserving input order for Backspace.
- Horizontal neutral tone is rendered before the syllable body, such as `˙ㄉㄜ`; first tone has no visible mark.
- `BopomofoParser` completes and resets one syllable when a tone arrives.
- `BopomofoInputSession` owns Backspace, Escape, Enter, pass-through, commit, and reset behavior without importing AppKit or InputMethodKit.

The current completed-syllable action commits literal Bopomofo. Milestone 3 can replace that action with dictionary lookup without moving language logic into `InputController`.

## InputMethodKit boundary

Active composition is sent with `setMarkedText`; its caret range is relative to the supplied UTF-16 string. Completed composition is sent once with `insertText`. Escape and Backspace-to-empty clear marked text with an empty marked string instead of calling `cancelComposition`, whose framework behavior is restoration rather than discard.

Client-driven commit, input-source deactivation, and controller closure all use the same idempotent session finalization path. The controller keeps InputMethodKit's default key-down-only recognized event mask.

## Configuration

`InputMethodConfiguration` validates the connection name and bundle identifier before server startup. Its Foundation-only implementation can be tested without starting an input method or hosting an AppKit application.

The bundle metadata declares:

- a background-only macOS application that stays out of the Dock;
- the InputMethodKit connection and Objective-C controller class names;
- the Traditional Chinese intended language and repertoire;
- a stable Text Input Sources identifier;
- a localized English and Traditional Chinese display name.

Milestone 1 uses `LSBackgroundOnly` because it is the configuration explicitly listed by Apple's current `IMKServer` initializer documentation. A later milestone can reassess the process policy when settings and candidate UI are introduced. `LSBackgroundOnly` and `LSUIElement` are not declared together.

The current application-bundle lifecycle was also compared with [McBopomofo](https://github.com/openvanilla/McBopomofo/tree/73d0379eca621377fb46416ceb4a7dc9bb576d47) and [OpenVanilla](https://github.com/openvanilla/openvanilla/tree/8f09dc6a66f10aecfdc928e7ff63753d7bc19b25). Only their public architecture was studied; no source code or language data was copied.

Future modules for dictionaries, candidates, learning, punctuation, and settings will not be placed in `InputController`.
