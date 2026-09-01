import Foundation

/// Each synchronized setting is stored as its own CloudKit record. An older
/// build therefore updates only keys it understands and cannot erase fields
/// introduced by a newer build.
enum CloudPreferenceField: String, CaseIterable, Codable {
    case chineseText
    case englishText
    case chineseColor
    case englishColor
    case compositionColor
    case showsCompositionIndicator
    case animatesCompositionIndicator
    case textSize
    case placement
    case tracking
    case showsCapsLockIndicator
    case capsLockIndicatorSize

    func value(from preferences: Preferences) -> String {
        let indicator = preferences.cursorIndicator
        switch self {
        case .chineseText:
            return indicator.appearance.chineseText ?? ""
        case .englishText:
            return indicator.appearance.englishText ?? ""
        case .chineseColor:
            return indicator.appearance.chineseColorHex ?? ""
        case .englishColor:
            return indicator.appearance.englishColorHex ?? ""
        case .compositionColor:
            return indicator.appearance.compositionIndicatorColorHex ?? ""
        case .showsCompositionIndicator:
            return String(indicator.showsCompositionIndicator)
        case .animatesCompositionIndicator:
            return String(indicator.animatesCompositionIndicator)
        case .textSize:
            return indicator.textSize.rawValue
        case .placement:
            return indicator.placement.rawValue
        case .tracking:
            return indicator.tracking.rawValue
        case .showsCapsLockIndicator:
            return String(indicator.showsCapsLockIndicator)
        case .capsLockIndicatorSize:
            return indicator.capsLockIndicatorSize.rawValue
        }
    }

    @discardableResult
    func apply(_ value: String, to preferences: inout Preferences) -> Bool {
        switch self {
        case .chineseText:
            return applyText(
                value,
                to: &preferences.cursorIndicator.appearance.chineseText
            )
        case .englishText:
            return applyText(
                value,
                to: &preferences.cursorIndicator.appearance.englishText
            )
        case .chineseColor:
            return applyColor(
                value,
                to: &preferences.cursorIndicator.appearance.chineseColorHex
            )
        case .englishColor:
            return applyColor(
                value,
                to: &preferences.cursorIndicator.appearance.englishColorHex
            )
        case .compositionColor:
            return applyColor(
                value,
                to: &preferences.cursorIndicator.appearance
                    .compositionIndicatorColorHex
            )
        case .showsCompositionIndicator:
            guard let value = Self.boolean(value) else {
                return false
            }
            preferences.cursorIndicator.showsCompositionIndicator = value
        case .animatesCompositionIndicator:
            guard let value = Self.boolean(value) else {
                return false
            }
            preferences.cursorIndicator.animatesCompositionIndicator = value
        case .textSize:
            guard let value = CursorIndicatorTextSize(rawValue: value) else {
                return false
            }
            preferences.cursorIndicator.textSize = value
        case .placement:
            guard let value = CursorIndicatorPlacement(rawValue: value) else {
                return false
            }
            preferences.cursorIndicator.placement = value
        case .tracking:
            guard let value = CursorIndicatorTracking(rawValue: value) else {
                return false
            }
            preferences.cursorIndicator.tracking = value
        case .showsCapsLockIndicator:
            guard let value = Self.boolean(value) else {
                return false
            }
            preferences.cursorIndicator.showsCapsLockIndicator = value
        case .capsLockIndicatorSize:
            guard let value = CapsLockIndicatorSize(rawValue: value) else {
                return false
            }
            preferences.cursorIndicator.capsLockIndicatorSize = value
        }
        return true
    }

    func accepts(_ value: String) -> Bool {
        var preferences = Preferences.default
        return apply(value, to: &preferences)
    }

    private func applyText(
        _ value: String,
        to destination: inout String?
    ) -> Bool {
        if value.isEmpty {
            destination = nil
            return true
        }
        guard let sanitized = CursorIndicatorAppearance.sanitizedText(value)
        else {
            return false
        }
        destination = sanitized
        return true
    }

    private func applyColor(
        _ value: String,
        to destination: inout String?
    ) -> Bool {
        if value.isEmpty {
            destination = nil
            return true
        }
        guard let sanitized = CursorIndicatorAppearance.sanitizedHex(value)
        else {
            return false
        }
        destination = sanitized
        return true
    }

    private static func boolean(_ value: String) -> Bool? {
        switch value.lowercased() {
        case "true":
            return true
        case "false":
            return false
        default:
            return nil
        }
    }
}

struct CloudPreferenceRecord: Codable, Equatable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let field: CloudPreferenceField
    let value: String
    let modifiedAt: Date
    let revision: Int64

    init(
        field: CloudPreferenceField,
        value: String,
        modifiedAt: Date,
        revision: Int64,
        schemaVersion: Int = currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.field = field
        self.value = value
        self.modifiedAt = modifiedAt
        self.revision = revision
    }

    var isValid: Bool {
        schemaVersion == Self.currentSchemaVersion
            && revision >= 1
            && field.accepts(value)
    }

    func isNewer(than other: CloudPreferenceRecord) -> Bool {
        if modifiedAt != other.modifiedAt {
            return modifiedAt > other.modifiedAt
        }
        if revision != other.revision {
            return revision > other.revision
        }
        return value > other.value
    }
}

struct CloudPreferencesSnapshot {
    let accountIdentifier: CloudAccountIdentifier
    let records: [CloudPreferenceRecord]
}

struct CloudPreferenceMetadata: Codable, Equatable {
    let modifiedAt: Date
    let revision: Int64

    init(_ record: CloudPreferenceRecord) {
        modifiedAt = record.modifiedAt
        revision = record.revision
    }

    func record(
        field: CloudPreferenceField,
        value: String
    ) -> CloudPreferenceRecord {
        CloudPreferenceRecord(
            field: field,
            value: value,
            modifiedAt: modifiedAt,
            revision: revision
        )
    }
}

struct CloudPreferencesPersistedState: Codable, Equatable {
    static let currentVersion = 1

    var version = currentVersion
    var accountIdentifier: CloudAccountIdentifier?
    var nextRevision: Int64 = 1
    var lastValues: [String: String] = [:]
    var metadata: [String: CloudPreferenceMetadata] = [:]
    var pending: [String: CloudPreferenceRecord] = [:]

    mutating func makePending(
        field: CloudPreferenceField,
        value: String,
        modifiedAt: Date
    ) -> CloudPreferenceRecord {
        let record = CloudPreferenceRecord(
            field: field,
            value: value,
            modifiedAt: modifiedAt,
            revision: nextRevision
        )
        if nextRevision < Int64.max {
            nextRevision += 1
        }
        pending[field.rawValue] = record
        lastValues[field.rawValue] = value
        return record
    }

    func validated() -> CloudPreferencesPersistedState? {
        guard version == Self.currentVersion,
              nextRevision >= 1,
              pending.allSatisfy({ key, record in
                  key == record.field.rawValue && record.isValid
              }),
              metadata.allSatisfy({ key, value in
                  CloudPreferenceField(rawValue: key) != nil
                      && value.revision >= 1
              }) else {
            return nil
        }
        return self
    }
}
