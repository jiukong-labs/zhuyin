import Carbon
import Foundation

struct RegisteredInputSource {
    let identifier: String
    let localizedName: String
    let type: String
}

enum InputSourceRegistrationError: LocalizedError {
    case registrationFailed(OSStatus)
    case enablingFailed(OSStatus)
    case disablingFailed(OSStatus)
    case selectionFailed(OSStatus)
    case unavailableBundleIDProperty
    case unavailableInputSourceIDProperty
    case inputSourceNotFound(String)
    case inputSourceMetadataMismatch(String)

    var errorDescription: String? {
        switch self {
        case let .registrationFailed(status):
            return "TISRegisterInputSource failed with OSStatus \(status)."
        case let .enablingFailed(status):
            return "TISEnableInputSource failed with OSStatus \(status)."
        case let .disablingFailed(status):
            return "TISDisableInputSource failed with OSStatus \(status)."
        case let .selectionFailed(status):
            return "TISSelectInputSource failed with OSStatus \(status)."
        case .unavailableBundleIDProperty:
            return "The macOS SDK did not provide kTISPropertyBundleID."
        case .unavailableInputSourceIDProperty:
            return "The macOS SDK did not provide kTISPropertyInputSourceID."
        case let .inputSourceNotFound(identifier):
            return "macOS did not return an installed input source for \(identifier)."
        case let .inputSourceMetadataMismatch(reason):
            return "The registered input source metadata is invalid: \(reason)."
        }
    }
}

enum InputSourceRegistrar {
    static func register(
        bundleURL: URL,
        bundleIdentifier: String
    ) throws -> RegisteredInputSource {
        let status = TISRegisterInputSource(bundleURL as CFURL)
        guard status == noErr else {
            throw InputSourceRegistrationError.registrationFailed(status)
        }

        guard let source = try inputSource(identifier: bundleIdentifier) else {
            throw InputSourceRegistrationError.inputSourceNotFound(bundleIdentifier)
        }

        guard source.identifier == bundleIdentifier else {
            throw InputSourceRegistrationError.inputSourceMetadataMismatch(
                "expected source ID \(bundleIdentifier), got \(source.identifier)"
            )
        }

        guard !source.localizedName.isEmpty else {
            throw InputSourceRegistrationError.inputSourceMetadataMismatch(
                "localized name is empty"
            )
        }

        guard
            let expectedType = kTISTypeKeyboardInputMethodModeEnabled,
            source.type == expectedType as String
        else {
            throw InputSourceRegistrationError.inputSourceMetadataMismatch(
                "expected a mode-enabled keyboard input method, got \(source.type)"
            )
        }

        let enablingStatus = TISEnableInputSource(source.reference)
        guard enablingStatus == noErr else {
            throw InputSourceRegistrationError.enablingFailed(enablingStatus)
        }

        for mode in LanguageMode.allCases {
            let identifier = mode.inputSourceID(parentID: bundleIdentifier)
            guard let modeSource = try inputSource(identifier: identifier) else {
                throw InputSourceRegistrationError.inputSourceNotFound(identifier)
            }
            guard
                let expectedType = kTISTypeKeyboardInputMode,
                modeSource.type == expectedType as String
            else {
                throw InputSourceRegistrationError.inputSourceMetadataMismatch(
                    "expected \(identifier) to be a keyboard input mode, got \(modeSource.type)"
                )
            }

            let modeStatus = TISEnableInputSource(modeSource.reference)
            guard modeStatus == noErr else {
                throw InputSourceRegistrationError.enablingFailed(modeStatus)
            }
        }

        return RegisteredInputSource(
            identifier: source.identifier,
            localizedName: source.localizedName,
            type: source.type
        )
    }

    static func disable(bundleIdentifier: String) throws -> RegisteredInputSource? {
        guard let source = try inputSource(identifier: bundleIdentifier) else {
            return nil
        }

        for mode in LanguageMode.allCases {
            let identifier = mode.inputSourceID(parentID: bundleIdentifier)
            guard let modeSource = try inputSource(identifier: identifier) else {
                continue
            }
            let modeStatus = TISDisableInputSource(modeSource.reference)
            guard modeStatus == noErr else {
                throw InputSourceRegistrationError.disablingFailed(modeStatus)
            }
        }

        let status = TISDisableInputSource(source.reference)
        guard status == noErr else {
            throw InputSourceRegistrationError.disablingFailed(status)
        }

        return RegisteredInputSource(
            identifier: source.identifier,
            localizedName: source.localizedName,
            type: source.type
        )
    }

    static func select(
        mode: LanguageMode,
        bundleIdentifier: String
    ) throws {
        let identifier = mode.inputSourceID(parentID: bundleIdentifier)
        guard let source = try inputSource(identifier: identifier) else {
            throw InputSourceRegistrationError.inputSourceNotFound(identifier)
        }

        let status = TISSelectInputSource(source.reference)
        guard status == noErr else {
            throw InputSourceRegistrationError.selectionFailed(status)
        }
    }

    private struct InputSourceMetadata {
        let reference: TISInputSource
        let identifier: String
        let bundleIdentifier: String
        let localizedName: String
        let type: String
    }

    private static func inputSource(
        identifier: String
    ) throws -> InputSourceMetadata? {
        guard let inputSourceIDProperty = kTISPropertyInputSourceID else {
            throw InputSourceRegistrationError.unavailableInputSourceIDProperty
        }

        let properties = [
            inputSourceIDProperty: identifier as CFString
        ] as CFDictionary
        guard let unmanagedSources = TISCreateInputSourceList(properties, true) else {
            return nil
        }

        return readInputSources(
            from: unmanagedSources.takeRetainedValue()
        ).first(where: { $0.identifier == identifier })
    }

    private static func readInputSources(
        from sources: CFArray
    ) -> [InputSourceMetadata] {
        (0 ..< CFArrayGetCount(sources)).compactMap { index in
            guard let rawSource = CFArrayGetValueAtIndex(sources, index) else {
                return nil
            }

            let source = Unmanaged<TISInputSource>
                .fromOpaque(rawSource)
                .takeUnretainedValue()

            guard
                let identifier = stringProperty(
                    kTISPropertyInputSourceID,
                    of: source
                ),
                let bundleIdentifier = stringProperty(
                    kTISPropertyBundleID,
                    of: source
                ),
                let localizedName = stringProperty(
                    kTISPropertyLocalizedName,
                    of: source
                ),
                let type = stringProperty(
                    kTISPropertyInputSourceType,
                    of: source
                )
            else {
                return nil
            }

            return InputSourceMetadata(
                reference: source,
                identifier: identifier,
                bundleIdentifier: bundleIdentifier,
                localizedName: localizedName,
                type: type
            )
        }
    }

    private static func stringProperty(
        _ key: CFString?,
        of source: TISInputSource
    ) -> String? {
        guard
            let key,
            let rawValue = TISGetInputSourceProperty(source, key)
        else {
            return nil
        }

        return Unmanaged<CFString>
            .fromOpaque(rawValue)
            .takeUnretainedValue() as String
    }
}
