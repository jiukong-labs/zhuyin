import Darwin
import Foundation
import SQLite3

struct DictionaryBuildSummary {
    let outputURL: URL
    let statistics: CNS11643Statistics
    let characterStatistics: JiukongCharacterStatistics
    let phraseStatistics: JiukongPhraseStatistics
    let frequencyTierStatistics: JiukongFrequencyTierStatistics
    let phraseAttestationStatistics: JiukongPhraseAttestationStatistics
}

struct JiukongCharacterEntry: Equatable {
    let character: String
    let pronunciation: String
}

struct JiukongCharacterStatistics: Equatable {
    let entryCount: Int
    let uniqueCharacterCount: Int

    static let empty = JiukongCharacterStatistics(
        entryCount: 0,
        uniqueCharacterCount: 0
    )
}

struct JiukongCharacterDataset {
    let entries: [JiukongCharacterEntry]
    let statistics: JiukongCharacterStatistics

    static let empty = JiukongCharacterDataset(
        entries: [],
        statistics: .empty
    )
}

enum JiukongCharacterParserError: LocalizedError, Equatable {
    case invalidTextEncoding(file: String)
    case malformedLine(line: Int)
    case invalidEntry(line: Int, reason: String)
    case duplicateEntry(line: Int, character: String)
    case emptyDataset

    var errorDescription: String? {
        switch self {
        case let .invalidTextEncoding(file):
            return "The Jiukong character source is not valid UTF-8: \(file)"
        case let .malformedLine(line):
            return "Malformed Jiukong character TSV row at line \(line)."
        case let .invalidEntry(line, reason):
            return "Invalid Jiukong character reading at line \(line): \(reason)"
        case let .duplicateEntry(line, character):
            return "Duplicate Jiukong character reading at line \(line): \(character)"
        case .emptyDataset:
            return "The Jiukong character source produced an empty supplement."
        }
    }
}

enum JiukongCharacterParser {
    private struct Identity: Hashable {
        let character: String
        let pronunciation: String
    }

    static func parse(sourceURL: URL) throws -> JiukongCharacterDataset {
        guard let source = try? String(contentsOf: sourceURL, encoding: .utf8) else {
            throw JiukongCharacterParserError.invalidTextEncoding(
                file: sourceURL.lastPathComponent
            )
        }

        var entries: [JiukongCharacterEntry] = []
        var identities: Set<Identity> = []
        let lines = source.split(
            separator: "\n",
            omittingEmptySubsequences: false
        )
        for (offset, rawLine) in lines.enumerated() {
            let lineNumber = offset + 1
            let line = rawLine.last == "\r" ? rawLine.dropLast() : rawLine[...]
            if line.isEmpty || line.first == "#" {
                continue
            }

            let fields = line.split(
                separator: "\t",
                omittingEmptySubsequences: false
            )
            guard fields.count == 2 else {
                throw JiukongCharacterParserError.malformedLine(line: lineNumber)
            }

            let character = String(fields[0])
                .precomposedStringWithCanonicalMapping
            let pronunciation = String(fields[1])
                .precomposedStringWithCanonicalMapping
            guard character.count == 1 else {
                throw JiukongCharacterParserError.invalidEntry(
                    line: lineNumber,
                    reason: "the text must contain exactly one character"
                )
            }
            guard CanonicalBopomofoReading.isValid(pronunciation) else {
                throw JiukongCharacterParserError.invalidEntry(
                    line: lineNumber,
                    reason: "the reading is not canonical Bopomofo"
                )
            }

            let identity = Identity(
                character: character,
                pronunciation: pronunciation
            )
            guard identities.insert(identity).inserted else {
                throw JiukongCharacterParserError.duplicateEntry(
                    line: lineNumber,
                    character: character
                )
            }
            entries.append(
                JiukongCharacterEntry(
                    character: character,
                    pronunciation: pronunciation
                )
            )
        }

        guard !entries.isEmpty else {
            throw JiukongCharacterParserError.emptyDataset
        }
        return JiukongCharacterDataset(
            entries: entries,
            statistics: JiukongCharacterStatistics(
                entryCount: entries.count,
                uniqueCharacterCount: Set(entries.map(\.character)).count
            )
        )
    }
}

enum JiukongCharacterMergerError: LocalizedError, Equatable {
    case characterMissingFromCNS(String)
    case readingAlreadyExists(character: String, pronunciation: String)

    var errorDescription: String? {
        switch self {
        case let .characterMissingFromCNS(character):
            return "Supplemental Jiukong character is missing from CNS11643: \(character)"
        case let .readingAlreadyExists(character, pronunciation):
            return "Supplemental Jiukong reading already exists in CNS11643: \(character) \(pronunciation)"
        }
    }
}

enum JiukongCharacterMerger {
    private struct Identity: Hashable {
        let character: String
        let pronunciation: String
    }

    static func merge(
        _ supplement: JiukongCharacterDataset,
        into dataset: CNS11643Dataset
    ) throws -> CNS11643Dataset {
        guard !supplement.entries.isEmpty else {
            return dataset
        }

        let entriesByCharacter = Dictionary(
            grouping: dataset.entries,
            by: \.character
        )
        var identities = Set(dataset.entries.map {
            Identity(
                character: $0.character,
                pronunciation: $0.pronunciation
            )
        })
        var entries = dataset.entries

        for supplementalEntry in supplement.entries {
            guard let representative = entriesByCharacter[
                supplementalEntry.character
            ]?.min(by: { $0.sourceOrder < $1.sourceOrder }) else {
                throw JiukongCharacterMergerError.characterMissingFromCNS(
                    supplementalEntry.character
                )
            }
            let identity = Identity(
                character: supplementalEntry.character,
                pronunciation: supplementalEntry.pronunciation
            )
            guard identities.insert(identity).inserted else {
                throw JiukongCharacterMergerError.readingAlreadyExists(
                    character: supplementalEntry.character,
                    pronunciation: supplementalEntry.pronunciation
                )
            }
            entries.append(
                DictionarySourceEntry(
                    pronunciation: supplementalEntry.pronunciation,
                    character: supplementalEntry.character,
                    cnsCode: representative.cnsCode,
                    sourceOrder: representative.sourceOrder
                )
            )
        }

        let pronunciationsByCharacter = Dictionary(
            grouping: entries,
            by: \.character
        )
        return CNS11643Dataset(
            entries: entries,
            statistics: CNS11643Statistics(
                phoneticRowCount: dataset.statistics.phoneticRowCount,
                uniqueCNSCodeCount: dataset.statistics.uniqueCNSCodeCount,
                excludedPrivateUseRowCount: dataset.statistics.excludedPrivateUseRowCount,
                duplicateEntryCount: dataset.statistics.duplicateEntryCount,
                dictionaryEntryCount: entries.count,
                uniqueCharacterCount: pronunciationsByCharacter.count,
                pronunciationCount: Set(entries.map(\.pronunciation)).count,
                multiPronunciationCharacterCount: pronunciationsByCharacter.values
                    .filter { Set($0.map(\.pronunciation)).count > 1 }
                    .count
            )
        )
    }
}

struct JiukongFrequencyTierStatistics: Equatable {
    let commonCharacterCount: Int
    let semiCommonCharacterCount: Int
    let heteronymOverrideCount: Int

    static let empty = JiukongFrequencyTierStatistics(
        commonCharacterCount: 0,
        semiCommonCharacterCount: 0,
        heteronymOverrideCount: 0
    )
}

/// A first-party, manually reviewed override for one (character, reading)
/// pair. The CNS plane tier classifies a character as a whole, so this table
/// can lower an uncommon reading without changing the character's ordinary
/// readings. Every row is verified against the pinned CNS snapshot.
struct JiukongHeteronymTierEntry: Equatable {
    let character: String
    let pronunciation: String
    let tier: Int
}

enum JiukongHeteronymTierParserError: LocalizedError, Equatable {
    case invalidTextEncoding(file: String)
    case malformedLine(line: Int)
    case invalidEntry(line: Int, reason: String)
    case duplicateEntry(line: Int, character: String, pronunciation: String)
    case emptyDataset

    var errorDescription: String? {
        switch self {
        case let .invalidTextEncoding(file):
            return "The Jiukong heteronym tier source is not valid UTF-8: \(file)"
        case let .malformedLine(line):
            return "Malformed Jiukong heteronym tier TSV row at line \(line)."
        case let .invalidEntry(line, reason):
            return "Invalid Jiukong heteronym tier entry at line \(line): \(reason)"
        case let .duplicateEntry(line, character, pronunciation):
            return "Duplicate Jiukong heteronym tier entry at line \(line): \(character) \(pronunciation)"
        case .emptyDataset:
            return "The Jiukong heteronym tier source produced an empty override set."
        }
    }
}

enum JiukongHeteronymTierParser {
    private struct Identity: Hashable {
        let character: String
        let pronunciation: String
    }

    static func parse(sourceURL: URL) throws -> [JiukongHeteronymTierEntry] {
        guard let source = try? String(contentsOf: sourceURL, encoding: .utf8) else {
            throw JiukongHeteronymTierParserError.invalidTextEncoding(
                file: sourceURL.lastPathComponent
            )
        }

        var entries: [JiukongHeteronymTierEntry] = []
        var identities: Set<Identity> = []
        let lines = source.split(
            separator: "\n",
            omittingEmptySubsequences: false
        )
        for (offset, rawLine) in lines.enumerated() {
            let lineNumber = offset + 1
            let line = rawLine.last == "\r" ? rawLine.dropLast() : rawLine[...]
            if line.isEmpty || line.first == "#" {
                continue
            }

            let fields = line.split(
                separator: "\t",
                omittingEmptySubsequences: false
            )
            guard fields.count == 3 else {
                throw JiukongHeteronymTierParserError.malformedLine(line: lineNumber)
            }

            let character = String(fields[0]).precomposedStringWithCanonicalMapping
            let pronunciation = String(fields[1]).precomposedStringWithCanonicalMapping
            guard character.count == 1 else {
                throw JiukongHeteronymTierParserError.invalidEntry(
                    line: lineNumber,
                    reason: "the text must contain exactly one character"
                )
            }
            guard CanonicalBopomofoReading.isValid(pronunciation) else {
                throw JiukongHeteronymTierParserError.invalidEntry(
                    line: lineNumber,
                    reason: "the reading is not canonical Bopomofo"
                )
            }
            guard let tier = Int(fields[2]), (0 ... 2).contains(tier) else {
                throw JiukongHeteronymTierParserError.invalidEntry(
                    line: lineNumber,
                    reason: "the tier must be 0, 1, or 2"
                )
            }

            let identity = Identity(character: character, pronunciation: pronunciation)
            guard identities.insert(identity).inserted else {
                throw JiukongHeteronymTierParserError.duplicateEntry(
                    line: lineNumber,
                    character: character,
                    pronunciation: pronunciation
                )
            }
            entries.append(
                JiukongHeteronymTierEntry(
                    character: character,
                    pronunciation: pronunciation,
                    tier: tier
                )
            )
        }

        guard !entries.isEmpty else {
            throw JiukongHeteronymTierParserError.emptyDataset
        }
        return entries
    }
}

enum FrequencyTierResolverError: LocalizedError, Equatable {
    case overrideNotFoundInDictionary(character: String, pronunciation: String)

    var errorDescription: String? {
        switch self {
        case let .overrideNotFoundInDictionary(character, pronunciation):
            return "Heteronym tier override does not match any dictionary entry: \(character) \(pronunciation)"
        }
    }
}

/// Resolves the final per-entry usage tier: a manually reviewed heteronym
/// override wins; otherwise the character uses its pinned CNS plane tier.
struct FrequencyTierResolver {
    private struct Key: Hashable {
        let character: String
        let pronunciation: String
    }

    private let characterTiers: [String: Int]
    private let overrides: [Key: Int]
    let statistics: JiukongFrequencyTierStatistics

    static let empty = FrequencyTierResolver(
        characterTiers: [:],
        overrides: [:],
        statistics: .empty
    )

    private init(
        characterTiers: [String: Int],
        overrides: [Key: Int],
        statistics: JiukongFrequencyTierStatistics
    ) {
        self.characterTiers = characterTiers
        self.overrides = overrides
        self.statistics = statistics
    }

    static func make(
        characterTiers: [String: Int],
        characterTierStatistics: JiukongFrequencyTierStatistics,
        heteronymOverrides: [JiukongHeteronymTierEntry],
        validatingAgainst dataset: CNS11643Dataset
    ) throws -> FrequencyTierResolver {
        guard !heteronymOverrides.isEmpty else {
            return FrequencyTierResolver(
                characterTiers: characterTiers,
                overrides: [:],
                statistics: characterTierStatistics
            )
        }

        let knownPairs = Set(dataset.entries.map {
            Key(character: $0.character, pronunciation: $0.pronunciation)
        })
        var overrides: [Key: Int] = [:]
        for override in heteronymOverrides {
            let key = Key(
                character: override.character,
                pronunciation: override.pronunciation
            )
            guard knownPairs.contains(key) else {
                throw FrequencyTierResolverError.overrideNotFoundInDictionary(
                    character: override.character,
                    pronunciation: override.pronunciation
                )
            }
            overrides[key] = override.tier
        }

        return FrequencyTierResolver(
            characterTiers: characterTiers,
            overrides: overrides,
            statistics: JiukongFrequencyTierStatistics(
                commonCharacterCount: characterTierStatistics.commonCharacterCount,
                semiCommonCharacterCount: characterTierStatistics.semiCommonCharacterCount,
                heteronymOverrideCount: overrides.count
            )
        )
    }

    func tier(character: String, pronunciation: String) -> Int {
        if let override = overrides[Key(character: character, pronunciation: pronunciation)] {
            return override
        }
        return characterTiers[character] ?? 2
    }
}

struct JiukongPhraseEntry: Equatable {
    let phrase: String
    let pronunciationSequence: [String]
    let pronunciationKey: String
    let sourceOrder: Int64
}

struct JiukongPhraseStatistics: Equatable {
    let entryCount: Int
    let uniquePhraseCount: Int
    let pronunciationSequenceCount: Int

    static let empty = JiukongPhraseStatistics(
        entryCount: 0,
        uniquePhraseCount: 0,
        pronunciationSequenceCount: 0
    )
}

struct JiukongPhraseDataset {
    let entries: [JiukongPhraseEntry]
    let statistics: JiukongPhraseStatistics

    static let empty = JiukongPhraseDataset(
        entries: [],
        statistics: .empty
    )
}

struct JiukongPhraseAttestationStatistics: Equatable {
    let distinctCharacterReadingCount: Int
    let totalCharacterReadingCount: Int64

    static let empty = JiukongPhraseAttestationStatistics(
        distinctCharacterReadingCount: 0,
        totalCharacterReadingCount: 0
    )
}

/// Counts character-reading pairs only in Jiukong's manually maintained
/// first-party phrase lexicon. Government-sourced phrase datasets are never
/// included, so candidate ranking does not derive a frequency signal from an
/// outside dictionary or corpus.
struct FirstPartyPhraseAttestationResolver {
    private struct Key: Hashable {
        let character: String
        let pronunciation: String
    }

    private let counts: [Key: Int64]
    let statistics: JiukongPhraseAttestationStatistics

    static let empty = FirstPartyPhraseAttestationResolver(
        phraseDataset: .empty
    )

    init(phraseDataset: JiukongPhraseDataset) {
        var counts: [Key: Int64] = [:]
        var totalCharacterReadingCount: Int64 = 0
        for entry in phraseDataset.entries {
            for (character, pronunciation) in zip(
                entry.phrase,
                entry.pronunciationSequence
            ) {
                let key = Key(
                    character: String(character),
                    pronunciation: pronunciation
                )
                counts[key, default: 0] += 1
                totalCharacterReadingCount += 1
            }
        }
        self.counts = counts
        statistics = JiukongPhraseAttestationStatistics(
            distinctCharacterReadingCount: counts.count,
            totalCharacterReadingCount: totalCharacterReadingCount
        )
    }

    func count(character: String, pronunciation: String) -> Int64 {
        counts[
            Key(character: character, pronunciation: pronunciation),
            default: 0
        ]
    }
}

enum JiukongPhraseParserError: LocalizedError, Equatable {
    case invalidTextEncoding(file: String)
    case malformedLine(line: Int)
    case invalidPhrase(line: Int, reason: String)
    case duplicateEntry(line: Int, phrase: String)
    case emptyDataset

    var errorDescription: String? {
        switch self {
        case let .invalidTextEncoding(file):
            return "The Jiukong phrase source is not valid UTF-8: \(file)"
        case let .malformedLine(line):
            return "Malformed Jiukong phrase TSV row at line \(line)."
        case let .invalidPhrase(line, reason):
            return "Invalid Jiukong phrase at line \(line): \(reason)"
        case let .duplicateEntry(line, phrase):
            return "Duplicate Jiukong phrase entry at line \(line): \(phrase)"
        case .emptyDataset:
            return "The Jiukong phrase source produced an empty lexicon."
        }
    }
}

enum JiukongPhraseParser {
    private struct Identity: Hashable {
        let phrase: String
        let pronunciationKey: String
    }

    static func parse(sourceURL: URL) throws -> JiukongPhraseDataset {
        guard let source = try? String(contentsOf: sourceURL, encoding: .utf8) else {
            throw JiukongPhraseParserError.invalidTextEncoding(
                file: sourceURL.lastPathComponent
            )
        }

        var entries: [JiukongPhraseEntry] = []
        var identities: Set<Identity> = []
        let lines = source.split(
            separator: "\n",
            omittingEmptySubsequences: false
        )
        for (offset, rawLine) in lines.enumerated() {
            let lineNumber = offset + 1
            let line = rawLine.last == "\r" ? rawLine.dropLast() : rawLine[...]
            if line.isEmpty || line.first == "#" {
                continue
            }

            let fields = line.split(
                separator: "\t",
                omittingEmptySubsequences: false
            )
            guard fields.count == 2 else {
                throw JiukongPhraseParserError.malformedLine(line: lineNumber)
            }

            let phrase = String(fields[0]).precomposedStringWithCanonicalMapping
            let readings = fields[1].split(
                separator: " ",
                omittingEmptySubsequences: true
            ).map {
                String($0).precomposedStringWithCanonicalMapping
            }
            guard !phrase.isEmpty else {
                throw JiukongPhraseParserError.invalidPhrase(
                    line: lineNumber,
                    reason: "the phrase is empty"
                )
            }
            guard phrase.count == readings.count else {
                throw JiukongPhraseParserError.invalidPhrase(
                    line: lineNumber,
                    reason: "\(phrase.count) text units do not match \(readings.count) readings"
                )
            }
            guard readings.allSatisfy(CanonicalBopomofoReading.isValid) else {
                throw JiukongPhraseParserError.invalidPhrase(
                    line: lineNumber,
                    reason: "a reading is not canonical Bopomofo"
                )
            }
            guard let pronunciationKey = DictionaryPronunciationSequenceKey.encode(
                readings
            ) else {
                throw JiukongPhraseParserError.invalidPhrase(
                    line: lineNumber,
                    reason: "the phrase must contain 2 through 64 readings"
                )
            }

            let identity = Identity(
                phrase: phrase,
                pronunciationKey: pronunciationKey
            )
            guard identities.insert(identity).inserted else {
                throw JiukongPhraseParserError.duplicateEntry(
                    line: lineNumber,
                    phrase: phrase
                )
            }

            entries.append(
                JiukongPhraseEntry(
                    phrase: phrase,
                    pronunciationSequence: readings,
                    pronunciationKey: pronunciationKey,
                    sourceOrder: Int64(entries.count)
                )
            )
        }

        guard !entries.isEmpty else {
            throw JiukongPhraseParserError.emptyDataset
        }
        return JiukongPhraseDataset(
            entries: entries,
            statistics: JiukongPhraseStatistics(
                entryCount: entries.count,
                uniquePhraseCount: Set(entries.map(\.phrase)).count,
                pronunciationSequenceCount: Set(
                    entries.map(\.pronunciationKey)
                ).count
            )
        )
    }
}


enum DictionaryDatabaseBuilderError: LocalizedError {
    case integrityCheckFailed(String)
    case unsafeOutput(path: String, reason: String)
    case outputReplacementFailed(path: String, message: String)

    var errorDescription: String? {
        switch self {
        case let .integrityCheckFailed(message):
            return "Generated dictionary failed SQLite integrity_check: \(message)"
        case let .unsafeOutput(path, reason):
            return "Refusing unsafe dictionary output at \(path): \(reason)"
        case let .outputReplacementFailed(path, message):
            return "Could not atomically replace dictionary at \(path): \(message)"
        }
    }
}

enum DictionaryDatabaseBuilder {
    private static func cnsUsageTiers(
        in dataset: CNS11643Dataset
    ) -> ([String: Int], JiukongFrequencyTierStatistics) {
        var tiers: [String: Int] = [:]
        for entry in dataset.entries {
            let plane = entry.cnsCode.split(separator: "-", maxSplits: 1)
                .first
                .flatMap { Int($0) }
            let tier: Int
            switch plane {
            case 1:
                tier = 0
            case 2:
                tier = 1
            default:
                tier = 2
            }
            tiers[entry.character] = min(tiers[entry.character] ?? 2, tier)
        }

        return (
            tiers,
            JiukongFrequencyTierStatistics(
                commonCharacterCount: tiers.values.filter { $0 == 0 }.count,
                semiCommonCharacterCount: tiers.values.filter { $0 == 1 }.count,
                heteronymOverrideCount: 0
            )
        )
    }

    static func build(
        sourceDirectory: URL,
        characterSourceURL: URL? = nil,
        phraseSourceURL: URL? = nil,
        heteronymTierURL: URL? = nil,
        outputURL: URL
    ) throws -> DictionaryBuildSummary {
        try validateOutputURL(
            outputURL,
            sourceDirectory: sourceDirectory,
            characterSourceURL: characterSourceURL,
            phraseSourceURL: phraseSourceURL
        )
        let manifest = try CNS11643Manifest.load(from: sourceDirectory)
        let dataset = try CNS11643Parser.parse(
            sourceDirectory: sourceDirectory,
            manifest: manifest
        )
        let characterDataset: JiukongCharacterDataset
        if let characterSourceURL {
            characterDataset = try JiukongCharacterParser.parse(
                sourceURL: characterSourceURL
            )
        } else {
            characterDataset = .empty
        }
        let mergedDataset = try JiukongCharacterMerger.merge(
            characterDataset,
            into: dataset
        )

        let (characterTiers, characterTierStatistics) = cnsUsageTiers(
            in: mergedDataset
        )
        let heteronymOverrides: [JiukongHeteronymTierEntry]
        if let heteronymTierURL {
            heteronymOverrides = try JiukongHeteronymTierParser.parse(
                sourceURL: heteronymTierURL
            )
        } else {
            heteronymOverrides = []
        }
        let frequencyTierResolver = try FrequencyTierResolver.make(
            characterTiers: characterTiers,
            characterTierStatistics: characterTierStatistics,
            heteronymOverrides: heteronymOverrides,
            validatingAgainst: mergedDataset
        )

        let phraseDataset: JiukongPhraseDataset
        if let phraseSourceURL {
            phraseDataset = try JiukongPhraseParser.parse(
                sourceURL: phraseSourceURL
            )
        } else {
            phraseDataset = .empty
        }
        let phraseAttestationResolver = FirstPartyPhraseAttestationResolver(
            phraseDataset: phraseDataset
        )
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let temporaryURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent(".\(outputURL.lastPathComponent).\(UUID().uuidString).tmp")

        do {
            try writeDatabase(
                at: temporaryURL,
                manifest: manifest,
                dataset: mergedDataset,
                characterDataset: characterDataset,
                phraseDataset: phraseDataset,
                phraseStatistics: phraseDataset.statistics,
                frequencyTierResolver: frequencyTierResolver,
                phraseAttestationResolver: phraseAttestationResolver
            )
            guard Darwin.rename(temporaryURL.path, outputURL.path) == 0 else {
                throw DictionaryDatabaseBuilderError.outputReplacementFailed(
                    path: outputURL.path,
                    message: String(cString: strerror(errno))
                )
            }
        } catch {
            _ = Darwin.unlink(temporaryURL.path)
            throw error
        }

        return DictionaryBuildSummary(
            outputURL: outputURL,
            statistics: mergedDataset.statistics,
            characterStatistics: characterDataset.statistics,
            phraseStatistics: phraseDataset.statistics,
            frequencyTierStatistics: frequencyTierResolver.statistics,
            phraseAttestationStatistics: phraseAttestationResolver.statistics
        )
    }

    private static func writeDatabase(
        at outputURL: URL,
        manifest: CNS11643Manifest,
        dataset: CNS11643Dataset,
        characterDataset: JiukongCharacterDataset,
        phraseDataset: JiukongPhraseDataset,
        phraseStatistics: JiukongPhraseStatistics,
        frequencyTierResolver: FrequencyTierResolver,
        phraseAttestationResolver: FirstPartyPhraseAttestationResolver
    ) throws {
        let fileDescriptor = Darwin.open(
            outputURL.path,
            O_RDWR | O_CREAT | O_EXCL,
            S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH
        )
        guard fileDescriptor >= 0 else {
            throw DictionaryDatabaseBuilderError.outputReplacementFailed(
                path: outputURL.path,
                message: String(cString: strerror(errno))
            )
        }
        guard Darwin.close(fileDescriptor) == 0 else {
            throw DictionaryDatabaseBuilderError.outputReplacementFailed(
                path: outputURL.path,
                message: String(cString: strerror(errno))
            )
        }

        let database = try SQLiteDatabase(
            url: outputURL,
            flags: SQLITE_OPEN_READWRITE
                | SQLITE_OPEN_CREATE
                | SQLITE_OPEN_FULLMUTEX
        )
        try database.execute("PRAGMA page_size = 4096")
        try database.execute("PRAGMA journal_mode = OFF")
        try database.execute("PRAGMA synchronous = OFF")
        try database.execute("PRAGMA locking_mode = EXCLUSIVE")
        try database.execute("PRAGMA auto_vacuum = NONE")
        try database.execute("PRAGMA encoding = 'UTF-8'")
        try database.execute("PRAGMA application_id = \(CharacterDictionary.applicationID)")
        try database.execute("PRAGMA user_version = \(CharacterDictionary.schemaVersion)")
        try database.execute(
            """
            CREATE TABLE metadata (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            ) WITHOUT ROWID;

            CREATE TABLE dictionary_entries (
                pronunciation TEXT NOT NULL,
                character TEXT NOT NULL,
                source_order INTEGER NOT NULL CHECK(source_order >= 0),
                cns_code TEXT NOT NULL,
                usage_tier INTEGER NOT NULL CHECK(usage_tier IN (0, 1, 2)),
                first_party_phrase_count INTEGER NOT NULL
                    CHECK(first_party_phrase_count >= 0),
                PRIMARY KEY (pronunciation, character)
            ) WITHOUT ROWID;

            CREATE TABLE phrase_entries (
                pronunciation_key TEXT NOT NULL,
                phrase TEXT NOT NULL,
                source_order INTEGER NOT NULL CHECK(source_order >= 0),
                PRIMARY KEY (pronunciation_key, phrase)
            ) WITHOUT ROWID;
            """
        )

        try database.execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            let insertEntry = try database.prepare(
                """
                INSERT INTO dictionary_entries (
                    pronunciation,
                    character,
                    source_order,
                    cns_code,
                    usage_tier,
                    first_party_phrase_count
                ) VALUES (?, ?, ?, ?, ?, ?)
                """
            )
            for entry in dataset.entries {
                try insertEntry.bind(entry.pronunciation, at: 1)
                try insertEntry.bind(entry.character, at: 2)
                try insertEntry.bind(entry.sourceOrder, at: 3)
                try insertEntry.bind(entry.cnsCode, at: 4)
                try insertEntry.bind(
                    Int64(frequencyTierResolver.tier(
                        character: entry.character,
                        pronunciation: entry.pronunciation
                    )),
                    at: 5
                )
                try insertEntry.bind(
                    phraseAttestationResolver.count(
                        character: entry.character,
                        pronunciation: entry.pronunciation
                    ),
                    at: 6
                )
                guard try insertEntry.step() == .done else {
                    throw SQLiteDatabaseError.operation(
                        sql: "INSERT INTO dictionary_entries",
                        message: "unexpected row result"
                    )
                }
                try insertEntry.reset()
            }

            let insertPhrase = try database.prepare(
                """
                INSERT INTO phrase_entries (
                    pronunciation_key,
                    phrase,
                    source_order
                ) VALUES (?, ?, ?)
                """
            )
            for entry in phraseDataset.entries {
                try insertPhrase.bind(entry.pronunciationKey, at: 1)
                try insertPhrase.bind(entry.phrase, at: 2)
                try insertPhrase.bind(entry.sourceOrder, at: 3)
                guard try insertPhrase.step() == .done else {
                    throw SQLiteDatabaseError.operation(
                        sql: "INSERT INTO phrase_entries",
                        message: "unexpected row result"
                    )
                }
                try insertPhrase.reset()
            }

            let insertMetadata = try database.prepare(
                "INSERT INTO metadata (key, value) VALUES (?, ?)"
            )
            for (key, value) in metadata(
                manifest: manifest,
                statistics: dataset.statistics,
                characterStatistics: characterDataset.statistics,
                phraseStatistics: phraseStatistics,
                frequencyTierStatistics: frequencyTierResolver.statistics,
                phraseAttestationStatistics: phraseAttestationResolver.statistics
            ).sorted(by: { $0.key < $1.key }) {
                try insertMetadata.bind(key, at: 1)
                try insertMetadata.bind(value, at: 2)
                guard try insertMetadata.step() == .done else {
                    throw SQLiteDatabaseError.operation(
                        sql: "INSERT INTO metadata",
                        message: "unexpected row result"
                    )
                }
                try insertMetadata.reset()
            }

            try database.execute("COMMIT")
        } catch {
            try? database.execute("ROLLBACK")
            throw error
        }

        try database.execute(
            """
            CREATE INDEX candidates_by_pronunciation
            ON dictionary_entries(pronunciation, source_order, character);

            CREATE INDEX readings_by_character
            ON dictionary_entries(character, source_order, pronunciation);

            CREATE INDEX phrases_by_pronunciation
            ON phrase_entries(pronunciation_key, source_order, phrase);
            """
        )
        try database.execute("VACUUM")

        let integrityCheck = try database.prepare("PRAGMA integrity_check")
        guard try integrityCheck.step() == .row else {
            throw DictionaryDatabaseBuilderError.integrityCheckFailed(
                "no result"
            )
        }
        let result = try integrityCheck.text(at: 0)
        guard result == "ok" else {
            throw DictionaryDatabaseBuilderError.integrityCheckFailed(result)
        }
    }

    private static func metadata(
        manifest: CNS11643Manifest,
        statistics: CNS11643Statistics,
        characterStatistics: JiukongCharacterStatistics,
        phraseStatistics: JiukongPhraseStatistics,
        frequencyTierStatistics: JiukongFrequencyTierStatistics,
        phraseAttestationStatistics: JiukongPhraseAttestationStatistics
    ) -> [String: String] {
        var values: [String: String] = [
            "dataset_name": manifest.datasetName,
            "dataset_url": manifest.datasetURL,
            "excluded_private_use_rows": String(statistics.excludedPrivateUseRowCount),
            "license_name": manifest.licenseName,
            "license_url": manifest.licenseURL,
            "multi_pronunciation_characters": String(statistics.multiPronunciationCharacterCount),
            "phonetic_rows": String(statistics.phoneticRowCount),
            "pronunciations": String(statistics.pronunciationCount),
            "provider": manifest.provider,
            "retrieved_at": manifest.retrievedAt,
            "source_version": manifest.version,
            "transformation": "Joined phonetic and Unicode mappings; excluded Unicode private-use scalars; deduplicated pronunciation-character pairs; preserved source order.",
            "unique_characters": String(statistics.uniqueCharacterCount),
            "unique_cns_codes": String(statistics.uniqueCNSCodeCount),
            "dictionary_entries": String(statistics.dictionaryEntryCount),
            "duplicate_entries_removed": String(statistics.duplicateEntryCount),
            "first_party_character_dataset_name": "Jiukong first-party character readings",
            "first_party_character_entries": String(characterStatistics.entryCount),
            "first_party_unique_characters": String(characterStatistics.uniqueCharacterCount),
            "first_party_character_transformation": "Validated original TSV rows; reused each character's pinned CNS code and source position; rejected duplicate CNS readings.",
            "phrase_dataset_name": "Jiukong first-party phrase lexicon",
            "phrase_entries": String(phraseStatistics.entryCount),
            "phrase_pronunciation_sequences": String(
                phraseStatistics.pronunciationSequenceCount
            ),
            "phrase_transformation": "Validated original TSV rows; encoded exact pronunciation sequences; preserved repository source order; no imported frequency data.",
            "unique_phrases": String(phraseStatistics.uniquePhraseCount),
            "first_party_attested_character_readings": String(
                phraseAttestationStatistics.distinctCharacterReadingCount
            ),
            "first_party_character_reading_attestations": String(
                phraseAttestationStatistics.totalCharacterReadingCount
            ),
            "first_party_attestation_transformation": "Counted exact (character, reading) occurrences only in Jiukong's manually authored phrase TSV. Used only as a within-tier candidate-order signal, not represented as corpus frequency.",
            "frequency_tier_dataset_name": "Pinned CNS11643 planes + Jiukong first-party heteronym overrides",
            "frequency_tier_plane_1_characters": String(frequencyTierStatistics.commonCharacterCount),
            "frequency_tier_plane_2_characters": String(frequencyTierStatistics.semiCommonCharacterCount),
            "frequency_tier_heteronym_overrides": String(frequencyTierStatistics.heteronymOverrideCount),
            "frequency_tier_transformation": "CNS plane 1 maps to tier 0, plane 2 to tier 1, and later planes to tier 2; a manually reviewed (character, reading) override, verified against this snapshot, wins over the character tier. No outside dictionary, corpus, or frequency data."
        ]
        for (archiveName, hash) in manifest.archiveSHA256 {
            values["sha256_\(archiveName)"] = hash
        }
        for sourceFile in manifest.sourceFiles {
            values["sha256_source_\(sourceFile.name)"] = sourceFile.sha256
        }
        return values
    }

    private static func validateOutputURL(
        _ outputURL: URL,
        sourceDirectory: URL,
        characterSourceURL: URL?,
        phraseSourceURL: URL?
    ) throws {
        let sourcePath = sourceDirectory.standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        let outputPath = outputURL.deletingLastPathComponent()
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .appendingPathComponent(outputURL.lastPathComponent)
            .path
        if outputPath == sourcePath
            || outputPath.hasPrefix(sourcePath + "/") {
            throw DictionaryDatabaseBuilderError.unsafeOutput(
                path: outputURL.path,
                reason: "the output is the source directory or one of its descendants"
            )
        }

        if let characterSourceURL {
            let characterSourcePath = characterSourceURL.standardizedFileURL
                .resolvingSymlinksInPath()
                .path
            if outputPath == characterSourcePath {
                throw DictionaryDatabaseBuilderError.unsafeOutput(
                    path: outputURL.path,
                    reason: "the output is the character source file"
                )
            }
        }


        if let phraseSourceURL {
            let phraseSourcePath = phraseSourceURL.standardizedFileURL
                .resolvingSymlinksInPath()
                .path
            if outputPath == phraseSourcePath {
                throw DictionaryDatabaseBuilderError.unsafeOutput(
                    path: outputURL.path,
                    reason: "the output is the phrase source file"
                )
            }
        }

        var fileStatus = stat()
        if Darwin.lstat(outputURL.path, &fileStatus) == 0 {
            guard fileStatus.st_mode & S_IFMT == S_IFREG else {
                throw DictionaryDatabaseBuilderError.unsafeOutput(
                    path: outputURL.path,
                    reason: "an existing output must be a regular file"
                )
            }
        } else if errno != ENOENT {
            throw DictionaryDatabaseBuilderError.unsafeOutput(
                path: outputURL.path,
                reason: String(cString: strerror(errno))
            )
        }
    }
}
