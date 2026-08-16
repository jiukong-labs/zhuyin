# Milestone 1: native macOS input method

## Goal

Build and install a real AppKit application bundle backed by Apple's public InputMethodKit framework, then confirm that macOS registers it as an installed Traditional Chinese input source.

## Public APIs used

- `IMKServer` owns the input-method service connection.
- `IMKInputController` is the per-client controller base class.
- `TISRegisterInputSource` notifies macOS after installation under `~/Library/Input Methods`.
- `TISEnableInputSource` requests that the registered source become available without selecting it; current macOS versions can still require user approval.
- `TISCreateInputSourceList` verifies registration by the stable bundle identifier.

No private API, Accessibility API, global event monitor, analytics, or network service is used.

## Verification

Run:

```sh
xcodebuild -project "Jiukong Zhuyin.xcodeproj" -scheme "Jiukong Zhuyin" -configuration Debug -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData build
xcodebuild -project "Jiukong Zhuyin.xcodeproj" -scheme "Jiukong Zhuyin" -configuration Debug -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData test
./scripts/install.sh
```

After installation, the registration helper must report the source ID `tw.idv.jiukong.zhuyin`, the expected type, and an accepted enable request. It does not select the source. The final UI check is **System Settings > Keyboard > Text Input > Edit… > 久空輸入法**; if approval is pending, use **+ > Traditional Chinese > 久空輸入法**. If a system-session cache prevents it from appearing, sign out and back in once.

## Validated environment

- macOS 26.5.2 (25F84), Apple Silicon
- Xcode 26.6 (17F113), macOS SDK 26.5
- Debug tests: 5 passed, 0 failed
- Release bundle: valid local signature and universal `arm64`/`x86_64` executable
- Installation: `~/Library/Input Methods/Jiukong Zhuyin.app`
- System Settings: manually confirmed that `久空輸入法` appears in the installed input-source list

During repeated remove-and-reinstall testing, the validation Mac's current login session reported an empty HIToolbox system input-source table. Registration returned `noErr`, exposed the expected metadata in the registering process, and System Settings visibly listed the installed input method. A separate TIS diagnostic process still returned no matching entry after the visual confirmation; this session-cache inconsistency remains a known diagnostic limitation. The project intentionally does not reset private caches or modify `com.apple.HIToolbox` preferences.

## References

- [Apple InputMethodKit](https://developer.apple.com/documentation/inputmethodkit)
- [Apple `IMKServer.init(name:bundleIdentifier:)`](https://developer.apple.com/documentation/inputmethodkit/imkserver/init%28name%3Abundleidentifier%3A%29)
- [Apple `IMKInputController.init(server:delegate:client:)`](https://developer.apple.com/documentation/inputmethodkit/imkinputcontroller/init%28server%3Adelegate%3Aclient%3A%29)
- [Apple: Change Input Sources settings on Mac](https://support.apple.com/guide/mac-help/change-input-sources-settings-mchl84525d76/26/mac/26)

## Intentional limitations

This milestone does not map keys to Bopomofo, parse syllables, look up characters, display candidates, toggle with Shift, or learn user selections. Those are Milestones 2 through 8.
