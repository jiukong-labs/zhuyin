import Darwin
import Foundation
import SQLite3

struct DictionaryBuildSummary {
    let outputURL: URL
    let statistics: CNS11643Statistics
    let phraseStatistics: JiukongPhraseStatistics
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
    static func build(
        sourceDirectory: URL,
        phraseSourceURL: URL? = nil,
        outputURL: URL
    ) throws -> DictionaryBuildSummary {
        try validateOutputURL(
            outputURL,
            sourceDirectory: sourceDirectory,
            phraseSourceURL: phraseSourceURL
        )
        let manifest = try CNS11643Manifest.load(from: sourceDirectory)
        let dataset = try CNS11643Parser.parse(
            sourceDirectory: sourceDirectory,
            manifest: manifest
        )
        let phraseDataset: JiukongPhraseDataset
        if let phraseSourceURL {
            phraseDataset = try JiukongPhraseParser.parse(
                sourceURL: phraseSourceURL
            )
        } else {
            phraseDataset = .empty
        }

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
                dataset: dataset,
                phraseDataset: phraseDataset
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
            statistics: dataset.statistics,
            phraseStatistics: phraseDataset.statistics
        )
    }

    private static func writeDatabase(
        at outputURL: URL,
        manifest: CNS11643Manifest,
        dataset: CNS11643Dataset,
        phraseDataset: JiukongPhraseDataset
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
                    cns_code
                ) VALUES (?, ?, ?, ?)
                """
            )
            for entry in dataset.entries {
                try insertEntry.bind(entry.pronunciation, at: 1)
                try insertEntry.bind(entry.character, at: 2)
                try insertEntry.bind(entry.sourceOrder, at: 3)
                try insertEntry.bind(entry.cnsCode, at: 4)
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
                phraseStatistics: phraseDataset.statistics
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
        phraseStatistics: JiukongPhraseStatistics
    ) -> [String: String] {
        var values = [
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
            "phrase_dataset_name": "Jiukong first-party phrase lexicon",
            "phrase_entries": String(phraseStatistics.entryCount),
            "phrase_pronunciation_sequences": String(
                phraseStatistics.pronunciationSequenceCount
            ),
            "phrase_transformation": "Validated original TSV rows; encoded exact pronunciation sequences; preserved repository source order; no imported frequency data.",
            "unique_phrases": String(phraseStatistics.uniquePhraseCount)
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
