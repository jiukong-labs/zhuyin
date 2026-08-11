# Architecture

Milestone 1 contains only the native macOS input-method boundary. Later language features remain separate by design.

## Process boundary

`main.swift` validates the bundle configuration, creates exactly one `IMKServer`, and starts the background AppKit run loop. InputMethodKit creates one `InputController` for each client input session.

The current controller does not consume events. This makes the installed skeleton safe to select before Milestone 2: ordinary keyboard input continues to the client application.

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

Future modules for keyboard mapping, Bopomofo parsing, composition, dictionaries, candidates, learning, punctuation, and settings will not be placed in `InputController`.
