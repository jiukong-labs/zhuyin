import Foundation

/// Every persisted user setting owned by Milestone 8.
///
/// The type is a plain value so that decoding, normalization, and defaults can
/// be tested without touching `UserDefaults` or the settings window.
struct Preferences: Equatable {
    static let currentVersion = 1
    static let `default` = Preferences()

    var shiftKeyPreference: ShiftKeyPreference
    var automaticLearningEnabled: Bool
    var keyboardArrangement: ZhuyinKeyboardArrangement

    init(
        shiftKeyPreference: ShiftKeyPreference = .both,
        automaticLearningEnabled: Bool = true,
        keyboardArrangement: ZhuyinKeyboardArrangement = .standard
    ) {
        self.shiftKeyPreference = shiftKeyPreference
        self.automaticLearningEnabled = automaticLearningEnabled
        self.keyboardArrangement = keyboardArrangement
    }
}

/// The persisted key names. They are namespaced because the input method
/// shares its defaults domain with anything else the process may store.
enum PreferenceKey: String, CaseIterable {
    case version = "JiukongPreferencesVersion"
    case shiftLanguageToggle = "JiukongShiftLanguageToggle"
    case automaticLearningEnabled = "JiukongAutomaticLearningEnabled"
    case keyboardArrangement = "JiukongKeyboardArrangement"
}

extension Preferences {
    /// Reads a stored representation, replacing anything missing, malformed, or
    /// unknown with the shipped default rather than refusing to start.
    ///
    /// A version newer than this build is treated as unreadable: the defaults
    /// are used until the user changes a setting, which then rewrites the file
    /// at `currentVersion`.
    static func decoded(from values: [String: Any]) -> Preferences {
        guard let version = values[PreferenceKey.version.rawValue]
            .flatMap(integer(from:)) else {
            return decodedFields(from: values)
        }
        guard version >= 1, version <= currentVersion else {
            return .default
        }
        return decodedFields(from: values)
    }

    func encoded() -> [String: Any] {
        [
            PreferenceKey.version.rawValue: Self.currentVersion,
            PreferenceKey.shiftLanguageToggle.rawValue:
                shiftKeyPreference.rawValue,
            PreferenceKey.automaticLearningEnabled.rawValue:
                automaticLearningEnabled,
            PreferenceKey.keyboardArrangement.rawValue:
                keyboardArrangement.rawValue,
        ]
    }

    private static func decodedFields(from values: [String: Any]) -> Preferences {
        var preferences = Preferences.default

        if let rawValue = values[PreferenceKey.shiftLanguageToggle.rawValue]
            as? String,
           let preference = ShiftKeyPreference(rawValue: rawValue) {
            preferences.shiftKeyPreference = preference
        }

        if let enabled = boolean(
            from: values[PreferenceKey.automaticLearningEnabled.rawValue]
        ) {
            preferences.automaticLearningEnabled = enabled
        }

        if let rawValue = values[PreferenceKey.keyboardArrangement.rawValue]
            as? String,
           let arrangement = ZhuyinKeyboardArrangement(rawValue: rawValue) {
            preferences.keyboardArrangement = arrangement
        }

        return preferences
    }

    /// `defaults write` can produce a boolean, an integer, or a string, and a
    /// property list round trip may narrow a boolean to a number.
    private static func boolean(from value: Any?) -> Bool? {
        switch value {
        case let value as Bool:
            return value
        case let value as NSNumber:
            return value.boolValue
        case let value as String:
            switch value.lowercased() {
            case "true", "yes", "1":
                return true
            case "false", "no", "0":
                return false
            default:
                return nil
            }
        default:
            return nil
        }
    }

    private static func integer(from value: Any) -> Int? {
        switch value {
        case let value as Int:
            return value
        case let value as NSNumber:
            return value.intValue
        case let value as String:
            return Int(value)
        default:
            return nil
        }
    }
}
