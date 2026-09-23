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
    let usageTier: Int
    let firstPartyPhraseCount: Int64
    let defaultSelectionCount: Int64

    init(
        text: String,
        sourceOrder: Int64,
        cnsPlane: Int = 1,
        usageTier: Int = 2,
        firstPartyPhraseCount: Int64 = 0,
        defaultSelectionCount: Int64 = 0
    ) {
        self.text = text
        self.sourceOrder = sourceOrder
        self.cnsPlane = cnsPlane
        self.usageTier = usageTier
        self.firstPartyPhraseCount = firstPartyPhraseCount
        self.defaultSelectionCount = defaultSelectionCount
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
    let defaultSelectionCount: Int64
    let outputPattern: PhraseOutputPattern

    init(
        text: String,
        pronunciationSequence: [String],
        sourceOrder: Int64,
        defaultSelectionCount: Int64 = 0,
        outputPattern: PhraseOutputPattern? = nil
    ) {
        self.text = text
        self.pronunciationSequence = pronunciationSequence
        self.sourceOrder = sourceOrder
        self.defaultSelectionCount = defaultSelectionCount
        self.outputPattern = outputPattern
            ?? PhraseOutputPattern.inferred(
                from: text,
                readingCount: pronunciationSequence.count
            )!
    }
}

/// Versioned, UTF-8 length-prefixed key for exact built-in phrase lookup.
///
/// The encoding is deliberately owned by the runtime dictionary rather than
/// shared with user-data persistence: either format may evolve independently.
enum DictionaryPronunciationSequenceKey {
    static let currentVersion = 1
    static let allowedUnitCount = 1 ... 64

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

    /// The body of a neutral-tone reading (its leading `˙` stripped), or nil
    /// if `reading` isn't itself marked neutral tone.
    static func neutralToneBody(of reading: String) -> String? {
        guard reading.first == neutralTone else {
            return nil
        }
        return String(reading.dropFirst())
    }

    /// `reading` itself, if it is already an unmarked first-tone body (no
    /// leading `˙`, no trailing tone mark), or nil otherwise.
    static func firstToneBody(of reading: String) -> String? {
        guard let first = reading.first, first != neutralTone,
              let last = reading.last, !suffixTones.contains(last),
              isValid(reading) else {
            return nil
        }
        return reading
    }

    /// `body` spelled with every one of the five tones, first tone (unmarked)
    /// first.
    static func tonedReadings(forBody body: String) -> [String] {
        [body, String(neutralTone) + body]
            + suffixToneMarks.map { body + String($0) }
    }

    private static let suffixToneMarks: [Character] = ["ˊ", "ˇ", "ˋ"]
}

final class CharacterDictionary {
    static let resourceName = "JiukongZhuyin"
    static let resourceExtension = "sqlite3"
    static let applicationID: Int64 = 0x4A4B5A59
    static let schemaVersion = 6

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
                "SELECT character, source_order, cns_code, usage_tier, first_party_phrase_count, default_selection_count FROM dictionary_entries LIMIT 0"
            )
            _ = try database.prepare(
                "SELECT pronunciation, source_order FROM dictionary_entries LIMIT 0"
            )
            _ = try database.prepare(
                "SELECT pronunciation_key, phrase, source_order, default_selection_count, unit_pattern FROM phrase_entries LIMIT 0"
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
            SELECT character, source_order, cns_code, usage_tier,
                   first_party_phrase_count, default_selection_count
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
                    cnsPlane: try cnsPlane(from: cnsCode),
                    usageTier: Int(statement.integer(at: 3)),
                    firstPartyPhraseCount: statement.integer(at: 4),
                    defaultSelectionCount: statement.integer(at: 5)
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

    /// The CNS plane 1/2 character repertoire used as the default Traditional
    /// Chinese gate for other input engines. This keeps a phonetic data source
    /// from silently introducing Simplified or specialist variants into the
    /// normal candidate list.
    func generalCandidateCharacterTexts() throws -> Set<String> {
        let statement = try database.prepare(
            """
            SELECT character, cns_code
            FROM dictionary_entries
            ORDER BY source_order, character
            """
        )

        var values: Set<String> = []
        while try statement.step() == .row {
            let character = try statement.text(at: 0)
            let cnsCode = try statement.text(at: 1)
            if (1 ... 2).contains(try cnsPlane(from: cnsCode)) {
                values.insert(character)
            }
        }
        return values
    }

    /// Whether this dictionary carries the exact phrase identity: the same
    /// text under the same ordered readings.
    func containsPhrase(
        _ phrase: String,
        pronunciationSequence: [String]
    ) throws -> Bool {
        let normalizedReadings = pronunciationSequence.map {
            $0.precomposedStringWithCanonicalMapping
        }
        return try phraseEntries(for: pronunciationSequence).contains {
            $0.text == phrase
                && $0.pronunciationSequence == normalizedReadings
        }
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
            SELECT phrase, source_order, default_selection_count, unit_pattern
            FROM phrase_entries
            WHERE pronunciation_key = ?
            ORDER BY source_order, phrase
            """
        )
        try statement.bind(pronunciationKey, at: 1)

        var values: [DictionaryPhrase] = []
        while try statement.step() == .row {
            guard let outputPattern = PhraseOutputPattern(
                rawValue: try statement.text(at: 3)
            ), outputPattern.validates(
                text: try statement.text(at: 0),
                readingCount: normalizedReadings.count
            ) else {
                throw CharacterDictionaryError.invalidSchema(
                    "a phrase has an invalid output pattern"
                )
            }
            values.append(
                DictionaryPhrase(
                    text: try statement.text(at: 0),
                    pronunciationSequence: normalizedReadings,
                    sourceOrder: statement.integer(at: 1),
                    defaultSelectionCount: statement.integer(at: 2),
                    outputPattern: outputPattern
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


enum CantoneseDictionaryError: LocalizedError {
    case missingBundledData
    case unreadableBundledData
    case malformedHeader

    var errorDescription: String? {
        switch self {
        case .missingBundledData:
            return "The bundled Cantonese Jyutping character data is missing."
        case .unreadableBundledData:
            return "The bundled Cantonese Jyutping character data is unreadable."
        case .malformedHeader:
            return "The bundled Cantonese Jyutping character data has an invalid header."
        }
    }
}

struct CantoneseDictionaryEntry: Equatable {
    let text: String
    let reading: String
    let sourceOrder: Int
    let weight: Double
}

/// Read-only Jyutping character lookup owned by Jiukong.
///
/// The runtime parser is intentionally small and independent. It reads only
/// the explicitly approved Rime Cantonese character-to-Jyutping data file; it
/// does not embed Rime, load a Rime schema, or reuse another input method's
/// composition/ranking implementation.
final class CantoneseDictionary {
    static let resourceName = "jyut6ping3.chars.dict"
    static let resourceExtension = "yaml"

    private let fullReadingIndex: [String: [CantoneseDictionaryEntry]]
    private let tonelessReadingIndex: [String: [CantoneseDictionaryEntry]]

    convenience init(
        bundle: Bundle,
        allowedCharacters: Set<String>
    ) throws {
        guard let url = bundle.url(
            forResource: Self.resourceName,
            withExtension: Self.resourceExtension
        ) else {
            throw CantoneseDictionaryError.missingBundledData
        }
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            throw CantoneseDictionaryError.unreadableBundledData
        }
        try self.init(contents: contents, allowedCharacters: allowedCharacters)
    }

    init(
        contents: String,
        allowedCharacters: Set<String>
    ) throws {
        var didReachEntries = false
        var sourceOrder = 0
        var seen: Set<String> = []
        var full: [String: [CantoneseDictionaryEntry]] = [:]
        var toneless: [String: [CantoneseDictionaryEntry]] = [:]

        for rawLine in contents.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if !didReachEntries {
                if line == "..." {
                    didReachEntries = true
                }
                continue
            }
            guard !line.isEmpty, !line.hasPrefix("#") else {
                continue
            }

            let fields = line.split(
                separator: "\t",
                omittingEmptySubsequences: false
            )
            guard fields.count >= 2 else {
                continue
            }

            let text = String(fields[0])
                .precomposedStringWithCanonicalMapping
            let reading = String(fields[1])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard text.count == 1,
                  allowedCharacters.contains(text),
                  let tonelessReading = Self.tonelessReading(from: reading) else {
                continue
            }

            let identity = text + "\u{0}" + reading
            guard seen.insert(identity).inserted else {
                continue
            }

            let entry = CantoneseDictionaryEntry(
                text: text,
                reading: reading,
                sourceOrder: sourceOrder,
                weight: Self.weight(fields.count >= 3 ? fields[2] : nil)
            )
            sourceOrder += 1
            full[reading, default: []].append(entry)
            toneless[tonelessReading, default: []].append(entry)
        }

        guard didReachEntries else {
            throw CantoneseDictionaryError.malformedHeader
        }

        fullReadingIndex = full.mapValues(Self.sorted)
        tonelessReadingIndex = toneless.mapValues(Self.sorted)
    }

    func entries(
        for rawQuery: String,
        limit: Int = 81
    ) -> [CantoneseDictionaryEntry] {
        guard limit > 0,
              let query = Self.normalizedQuery(rawQuery) else {
            return []
        }
        let values: [CantoneseDictionaryEntry]
        if query.last?.isNumber == true {
            values = fullReadingIndex[query] ?? []
        } else {
            values = tonelessReadingIndex[query] ?? []
        }

        var seenText: Set<String> = []
        return Array(values.lazy.filter {
            seenText.insert($0.text).inserted
        }.prefix(limit))
    }

    static func normalizedQuery(_ rawQuery: String) -> String? {
        let query = rawQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !query.isEmpty else {
            return nil
        }

        var bytes = Array(query.utf8)
        if let last = bytes.last, (48 ... 57).contains(last) {
            guard (49 ... 54).contains(last) else {
                return nil
            }
            bytes.removeLast()
        }
        guard !bytes.isEmpty,
              bytes.allSatisfy({ (97 ... 122).contains($0) }) else {
            return nil
        }
        return query
    }

    private static func tonelessReading(from reading: String) -> String? {
        guard let normalized = normalizedQuery(reading),
              let last = normalized.utf8.last,
              (49 ... 54).contains(last) else {
            return nil
        }
        return String(normalized.dropLast())
    }

    private static func weight(_ field: Substring?) -> Double {
        guard let field else {
            return 1
        }
        let text = field.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasSuffix("%"),
           let percent = Double(text.dropLast()) {
            return percent / 100
        }
        return Double(text) ?? 1
    }

    private static func sorted(
        _ entries: [CantoneseDictionaryEntry]
    ) -> [CantoneseDictionaryEntry] {
        entries.sorted {
            if $0.weight != $1.weight {
                return $0.weight > $1.weight
            }
            if $0.sourceOrder != $1.sourceOrder {
                return $0.sourceOrder < $1.sourceOrder
            }
            return $0.text < $1.text
        }
    }
}
