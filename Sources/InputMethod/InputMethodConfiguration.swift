import Foundation

enum InputMethodConfigurationError: LocalizedError, Equatable {
    case missingValue(String)

    var errorDescription: String? {
        switch self {
        case let .missingValue(key):
            return "The input method is missing the required Info.plist value: \(key)."
        }
    }
}

struct InputMethodConfiguration: Equatable {
    static let connectionNameKey = "InputMethodConnectionName"
    static let bundleIdentifierKey = "CFBundleIdentifier"

    let connectionName: String
    let bundleIdentifier: String

    init(infoDictionary: [String: Any]) throws {
        connectionName = try Self.nonemptyString(
            forKey: Self.connectionNameKey,
            in: infoDictionary
        )
        bundleIdentifier = try Self.nonemptyString(
            forKey: Self.bundleIdentifierKey,
            in: infoDictionary
        )
    }

    private static func nonemptyString(
        forKey key: String,
        in infoDictionary: [String: Any]
    ) throws -> String {
        guard
            let value = infoDictionary[key] as? String,
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw InputMethodConfigurationError.missingValue(key)
        }

        return value
    }
}
