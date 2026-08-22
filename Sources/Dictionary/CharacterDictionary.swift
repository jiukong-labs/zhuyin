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
    let cnsPlane: Int

    init(
        text: String,
        sourceOrder: Int64,
        cnsPlane: Int = 1
    ) {
        self.text = text
        self.sourceOrder = sourceOrder
        self.cnsPlane = cnsPlane
    }

    var character: String {
        text
    }

    /// CNS planes 1 and 2 are the standard's common and less-common everyday
    /// repertoires. Later planes contain rare, variant, administrative, and
    /// other specialized characters that are opt-in candidates.
    var isInGeneralCandidateRepertoire: Bool {
        (1 ... 2).contains(cnsPlane)
    }
}

struct DictionaryPhrase: Equatable {
    let text: String
    let pronunciationSequence: [String]
    let sourceOrder: Int64
}

/// Versioned, UTF-8 length-prefixed key for exact built-in phrase lookup.
///
/// The encoding is deliberately owned by the runtime dictionary rather than
/// shared with user-data persistence: either format may evolve independently.
enum DictionaryPronunciationSequenceKey {
    static let currentVersion = 1
    static let allowedUnitCount = 2 ... 64

    static func encode(_ pronunciationSequence: [String]) -> String? {
        guard allowedUnitCount.contains(pronunciationSequence.count) else {
            return nil
        }

        let normalizedReadings = pronunciationSequence.map {
            $0.precomposedStringWithCanonicalMapping
        }
        guard normalizedReadings.allSatisfy({ !$0.isEmpty }) else {
            return nil
        }

        return "v\(currentVersion)|" + normalizedReadings.map { reading in
            "\(reading.utf8.count):\(reading)"
        }.joined()
    }
}

/// Canonical spelling accepted by both built-in and user-created phrases.
/// This mirrors `BopomofoSyllable.text` without coupling persistence or the
/// standalone dictionary builder to parser state.
enum CanonicalBopomofoReading {
    private static let initials = Set("ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙ")
    private static let medials = Set("ㄧㄨㄩ")
    private static let finals = Set("ㄚㄛㄜㄝㄞㄟㄠㄡㄢㄣㄤㄥㄦ")
    private static let suffixTones = Set("ˊˇˋ")
    private static let neutralTone: Character = "˙"

    static func isValid(_ reading: String) -> Bool {
        var components = Array(reading)
        guard !components.isEmpty else {
            return false
        }

        if components.first == neutralTone {
            components.removeFirst()
        } else if let last = components.last, suffixTones.contains(last) {
            components.removeLast()
        }
        guard !components.isEmpty else {
            return false
        }

        var previousSlot = -1
        for component in components {
            let slot: Int
            if initials.contains(component) {
                slot = 0
            } else if medials.contains(component) {
                slot = 1
            } else if finals.contains(component) {
                slot = 2
            } else {
                return false
            }
            guard slot > previousSlot else {
                return false
            }
            previousSlot = slot
        }
        return true
    }
}

final class CharacterDictionary {
    static let resourceName = "JiukongZhuyin"
    static let resourceExtension = "sqlite3"
    static let applicationID: Int64 = 0x4A4B5A59
    static let schemaVersion = 2

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
                "SELECT character, source_order, cns_code FROM dictionary_entries LIMIT 0"
            )
            _ = try database.prepare(
                "SELECT pronunciation, source_order FROM dictionary_entries LIMIT 0"
            )
            _ = try database.prepare(
                "SELECT pronunciation_key, phrase, source_order FROM phrase_entries LIMIT 0"
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
            SELECT character, source_order, cns_code
            FROM dictionary_entries
            WHERE pronunciation = ?
            ORDER BY source_order, character
            """
        )
        try statement.bind(pronunciation, at: 1)

        var values: [DictionaryCharacter] = []
        while try statement.step() == .row {
            let cnsCode = try statement.text(at: 2)
            values.append(
                DictionaryCharacter(
                    text: try statement.text(at: 0),
                    sourceOrder: statement.integer(at: 1),
                    cnsPlane: try cnsPlane(from: cnsCode)
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

    func phraseEntries(
        for pronunciationSequence: [String]
    ) throws -> [DictionaryPhrase] {
        guard let pronunciationKey = DictionaryPronunciationSequenceKey.encode(
            pronunciationSequence
        ) else {
            return []
        }

        let normalizedReadings = pronunciationSequence.map {
            $0.precomposedStringWithCanonicalMapping
        }
        let statement = try database.prepare(
            """
            SELECT phrase, source_order
            FROM phrase_entries
            WHERE pronunciation_key = ?
            ORDER BY source_order, phrase
            """
        )
        try statement.bind(pronunciationKey, at: 1)

        var values: [DictionaryPhrase] = []
        while try statement.step() == .row {
            values.append(
                DictionaryPhrase(
                    text: try statement.text(at: 0),
                    pronunciationSequence: normalizedReadings,
                    sourceOrder: statement.integer(at: 1)
                )
            )
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

    private func cnsPlane(from cnsCode: String) throws -> Int {
        guard let separator = cnsCode.firstIndex(of: "-"),
              let plane = Int(cnsCode[..<separator]),
              plane > 0 else {
            throw CharacterDictionaryError.invalidSchema(
                "dictionary entry has an invalid CNS code"
            )
        }
        return plane
    }
}
