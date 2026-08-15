import Foundation
import SQLite3

enum CharacterDictionaryError: LocalizedError {
    case missingBundledDatabase
    case invalidApplicationID(expected: Int64, actual: Int64)
    case invalidSchema(String)
    case unsupportedSchema(expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .missingBundledDatabase:
            return "The bundled Jiukong Zhuyin character database is missing."
        case let .invalidApplicationID(expected, actual):
            return "Invalid character database application ID \(actual); expected \(expected)."
        case let .invalidSchema(message):
            return "Invalid character database schema: \(message)"
        case let .unsupportedSchema(expected, actual):
            return "Unsupported character database schema \(actual); expected \(expected)."
        }
    }
}

struct DictionaryCharacter: Equatable {
    let text: String
    let sourceOrder: Int64

    var character: String {
        text
    }
}

final class CharacterDictionary {
    static let resourceName = "JiukongZhuyin"
    static let resourceExtension = "sqlite3"
    static let applicationID: Int64 = 0x4A4B5A59
    static let schemaVersion = 1

    private let database: SQLiteDatabase

    convenience init(bundle: Bundle) throws {
        guard let databaseURL = bundle.url(
            forResource: Self.resourceName,
            withExtension: Self.resourceExtension
        ) else {
            throw CharacterDictionaryError.missingBundledDatabase
        }

        try self.init(databaseURL: databaseURL)
    }

    init(databaseURL: URL) throws {
        database = try SQLiteDatabase(
            url: databaseURL,
            flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        )

        let applicationID = try pragmaInteger("application_id")
        guard applicationID == Self.applicationID else {
            throw CharacterDictionaryError.invalidApplicationID(
                expected: Self.applicationID,
                actual: applicationID
            )
        }

        let actualVersion = Int(try pragmaInteger("user_version"))
        guard actualVersion == Self.schemaVersion else {
            throw CharacterDictionaryError.unsupportedSchema(
                expected: Self.schemaVersion,
                actual: actualVersion
            )
        }

        do {
            _ = try database.prepare(
                "SELECT character, source_order FROM dictionary_entries LIMIT 0"
            )
            _ = try database.prepare(
                "SELECT pronunciation, source_order FROM dictionary_entries LIMIT 0"
            )
            _ = try database.prepare("SELECT value FROM metadata LIMIT 0")
        } catch {
            throw CharacterDictionaryError.invalidSchema(
                error.localizedDescription
            )
        }

        try database.execute("PRAGMA query_only = ON")
    }

    func candidates(for pronunciation: String) throws -> [String] {
        try candidateEntries(for: pronunciation).map(\.text)
    }

    func candidateEntries(
        for pronunciation: String
    ) throws -> [DictionaryCharacter] {
        let statement = try database.prepare(
            """
            SELECT character, source_order
            FROM dictionary_entries
            WHERE pronunciation = ?
            ORDER BY source_order, character
            """
        )
        try statement.bind(pronunciation, at: 1)

        var values: [DictionaryCharacter] = []
        while try statement.step() == .row {
            values.append(
                DictionaryCharacter(
                    text: try statement.text(at: 0),
                    sourceOrder: statement.integer(at: 1)
                )
            )
        }
        return values
    }

    func pronunciations(for character: String) throws -> [String] {
        let statement = try database.prepare(
            """
            SELECT pronunciation
            FROM dictionary_entries
            WHERE character = ?
            ORDER BY source_order, pronunciation
            """
        )
        try statement.bind(character, at: 1)

        var values: [String] = []
        while try statement.step() == .row {
            values.append(try statement.text(at: 0))
        }
        return values
    }

    func metadataValue(for key: String) throws -> String? {
        let statement = try database.prepare(
            "SELECT value FROM metadata WHERE key = ?"
        )
        try statement.bind(key, at: 1)

        guard try statement.step() == .row else {
            return nil
        }
        return try statement.text(at: 0)
    }

    private func pragmaInteger(_ name: String) throws -> Int64 {
        let statement = try database.prepare("PRAGMA \(name)")
        guard try statement.step() == .row else {
            return 0
        }
        return statement.integer(at: 0)
    }
}
