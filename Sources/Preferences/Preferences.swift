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
    var cursorIndicator: CursorIndicatorPreferences

    init(
        shiftKeyPreference: ShiftKeyPreference = .both,
        automaticLearningEnabled: Bool = true,
        keyboardArrangement: ZhuyinKeyboardArrangement = .standard,
        cursorIndicator: CursorIndicatorPreferences = CursorIndicatorPreferences()
    ) {
        self.shiftKeyPreference = shiftKeyPreference
        self.automaticLearningEnabled = automaticLearningEnabled
        self.keyboardArrangement = keyboardArrangement
        self.cursorIndicator = cursorIndicator
    }
}

/// The cursor-following mode indicator.
///
/// It is off by default: an input method that already shows a transient HUD
/// should not start painting a persistent overlay without being asked.
struct CursorIndicatorPreferences: Equatable {
    var isEnabled: Bool
    var placement: CursorIndicatorPlacement
    var tracking: CursorIndicatorTracking
    var textSize: CursorIndicatorTextSize
    var showsCapsLockIndicator: Bool
    var capsLockIndicatorSize: CapsLockIndicatorSize
    var appearance: CursorIndicatorAppearance

    init(
        isEnabled: Bool = false,
        placement: CursorIndicatorPlacement = .lowerRight,
        tracking: CursorIndicatorTracking = .fixedDistance,
        textSize: CursorIndicatorTextSize = .small,
        showsCapsLockIndicator: Bool = true,
        capsLockIndicatorSize: CapsLockIndicatorSize = .extraLarge,
        appearance: CursorIndicatorAppearance = CursorIndicatorAppearance()
    ) {
        self.isEnabled = isEnabled
        self.placement = placement
        self.tracking = tracking
        self.textSize = textSize
        self.showsCapsLockIndicator = showsCapsLockIndicator
        self.capsLockIndicatorSize = capsLockIndicatorSize
        self.appearance = appearance
    }
}

/// The persisted key names. They are namespaced because the input method
/// shares its defaults domain with anything else the process may store.
enum PreferenceKey: String, CaseIterable {
    case version = "JiukongPreferencesVersion"
    case shiftLanguageToggle = "JiukongShiftLanguageToggle"
    case automaticLearningEnabled = "JiukongAutomaticLearningEnabled"
    case keyboardArrangement = "JiukongKeyboardArrangement"
    case cursorIndicatorEnabled = "JiukongCursorIndicatorEnabled"
    case cursorIndicatorPlacement = "JiukongCursorIndicatorPlacement"
    case cursorIndicatorTracking = "JiukongCursorIndicatorTracking"
    case cursorIndicatorTextSize = "JiukongCursorIndicatorTextSize"
    case cursorIndicatorShowsCapsLock = "JiukongCursorIndicatorShowsCapsLock"
    case cursorIndicatorCapsLockSize = "JiukongCursorIndicatorCapsLockSize"
    case cursorIndicatorChineseText = "JiukongCursorIndicatorChineseText"
    case cursorIndicatorEnglishText = "JiukongCursorIndicatorEnglishText"
    case cursorIndicatorChineseColor = "JiukongCursorIndicatorChineseColor"
    case cursorIndicatorEnglishColor = "JiukongCursorIndicatorEnglishColor"
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
            PreferenceKey.cursorIndicatorEnabled.rawValue:
                cursorIndicator.isEnabled,
            PreferenceKey.cursorIndicatorPlacement.rawValue:
                cursorIndicator.placement.rawValue,
            PreferenceKey.cursorIndicatorTracking.rawValue:
                cursorIndicator.tracking.rawValue,
            PreferenceKey.cursorIndicatorTextSize.rawValue:
                cursorIndicator.textSize.rawValue,
            PreferenceKey.cursorIndicatorShowsCapsLock.rawValue:
                cursorIndicator.showsCapsLockIndicator,
            PreferenceKey.cursorIndicatorCapsLockSize.rawValue:
                cursorIndicator.capsLockIndicatorSize.rawValue,
            PreferenceKey.cursorIndicatorChineseText.rawValue:
                cursorIndicator.appearance.chineseText ?? "",
            PreferenceKey.cursorIndicatorEnglishText.rawValue:
                cursorIndicator.appearance.englishText ?? "",
            PreferenceKey.cursorIndicatorChineseColor.rawValue:
                cursorIndicator.appearance.chineseColorHex ?? "",
            PreferenceKey.cursorIndicatorEnglishColor.rawValue:
                cursorIndicator.appearance.englishColorHex ?? "",
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

        preferences.cursorIndicator = decodedCursorIndicator(from: values)

        return preferences
    }

    private static func decodedCursorIndicator(
        from values: [String: Any]
    ) -> CursorIndicatorPreferences {
        var indicator = CursorIndicatorPreferences()

        if let enabled = boolean(
            from: values[PreferenceKey.cursorIndicatorEnabled.rawValue]
        ) {
            indicator.isEnabled = enabled
        }
        if let showsCapsLock = boolean(
            from: values[PreferenceKey.cursorIndicatorShowsCapsLock.rawValue]
        ) {
            indicator.showsCapsLockIndicator = showsCapsLock
        }
        if let raw = values[PreferenceKey.cursorIndicatorPlacement.rawValue]
            as? String,
           let placement = CursorIndicatorPlacement(rawValue: raw) {
            indicator.placement = placement
        }
        if let raw = values[PreferenceKey.cursorIndicatorTracking.rawValue]
            as? String,
           let tracking = CursorIndicatorTracking(rawValue: raw) {
            indicator.tracking = tracking
        }
        if let raw = values[PreferenceKey.cursorIndicatorTextSize.rawValue]
            as? String,
           let size = CursorIndicatorTextSize(rawValue: raw) {
            indicator.textSize = size
        }
        if let raw = values[PreferenceKey.cursorIndicatorCapsLockSize.rawValue]
            as? String,
           let size = CapsLockIndicatorSize(rawValue: raw) {
            indicator.capsLockIndicatorSize = size
        }

        // Empty strings mean "no override" so a cleared field in the settings
        // window restores the default rather than blanking the indicator.
        indicator.appearance = CursorIndicatorAppearance(
            chineseText: values[PreferenceKey.cursorIndicatorChineseText.rawValue]
                as? String,
            englishText: values[PreferenceKey.cursorIndicatorEnglishText.rawValue]
                as? String,
            chineseColorHex:
                values[PreferenceKey.cursorIndicatorChineseColor.rawValue]
                as? String,
            englishColorHex:
                values[PreferenceKey.cursorIndicatorEnglishColor.rawValue]
                as? String
        )

        return indicator
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
