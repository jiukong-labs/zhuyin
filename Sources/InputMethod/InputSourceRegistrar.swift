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
    case unavailableBundleIDProperty
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
        case .unavailableBundleIDProperty:
            return "The macOS SDK did not provide kTISPropertyBundleID."
        case let .inputSourceNotFound(bundleIdentifier):
            return "macOS did not return an installed input source for \(bundleIdentifier)."
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

        guard let source = try inputSource(bundleIdentifier: bundleIdentifier) else {
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
            let expectedType = kTISTypeKeyboardInputMethodWithoutModes,
            source.type == expectedType as String
        else {
            throw InputSourceRegistrationError.inputSourceMetadataMismatch(
                "expected a keyboard input method without modes, got \(source.type)"
            )
        }

        let enablingStatus = TISEnableInputSource(source.reference)
        guard enablingStatus == noErr else {
            throw InputSourceRegistrationError.enablingFailed(enablingStatus)
        }

        return RegisteredInputSource(
            identifier: source.identifier,
            localizedName: source.localizedName,
            type: source.type
        )
    }

    static func disable(bundleIdentifier: String) throws -> RegisteredInputSource? {
        guard let source = try inputSource(bundleIdentifier: bundleIdentifier) else {
            return nil
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

    private struct InputSourceMetadata {
        let reference: TISInputSource
        let identifier: String
        let bundleIdentifier: String
        let localizedName: String
        let type: String
    }

    private static func inputSource(
        bundleIdentifier: String
    ) throws -> InputSourceMetadata? {
        guard let bundleIDProperty = kTISPropertyBundleID else {
            throw InputSourceRegistrationError.unavailableBundleIDProperty
        }

        let properties = [
            bundleIDProperty: bundleIdentifier as CFString
        ] as CFDictionary
        guard let unmanagedSources = TISCreateInputSourceList(properties, true) else {
            return nil
        }

        return readInputSources(
            from: unmanagedSources.takeRetainedValue()
        ).first(where: {
            $0.bundleIdentifier == bundleIdentifier
        })
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
