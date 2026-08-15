import Foundation

protocol PreferencesStoring: AnyObject {
    func load() -> Preferences
    func save(_ preferences: Preferences)
}

/// Persists settings in the input method's own defaults domain.
///
/// Only the keys this build owns are read, so an unrelated value in the same
/// domain can never be mistaken for a setting, and only those keys are written,
/// so nothing else in the domain is destroyed by a save.
final class UserDefaultsPreferencesStore: PreferencesStoring {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> Preferences {
        var values: [String: Any] = [:]
        for key in PreferenceKey.allCases {
            if let value = defaults.object(forKey: key.rawValue) {
                values[key.rawValue] = value
            }
        }
        return Preferences.decoded(from: values)
    }

    func save(_ preferences: Preferences) {
        for (key, value) in preferences.encoded() {
            defaults.set(value, forKey: key)
        }
    }
}
