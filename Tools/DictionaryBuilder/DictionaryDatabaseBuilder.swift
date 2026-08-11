import Darwin
import Foundation
import SQLite3

struct DictionaryBuildSummary {
    let outputURL: URL
    let statistics: CNS11643Statistics
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
        outputURL: URL
    ) throws -> DictionaryBuildSummary {
        try validateOutputURL(
            outputURL,
            sourceDirectory: sourceDirectory
        )
        let manifest = try CNS11643Manifest.load(from: sourceDirectory)
        let dataset = try CNS11643Parser.parse(
            sourceDirectory: sourceDirectory,
            manifest: manifest
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
                dataset: dataset
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
            statistics: dataset.statistics
        )
    }

    private static func writeDatabase(
        at outputURL: URL,
        manifest: CNS11643Manifest,
        dataset: CNS11643Dataset
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

            let insertMetadata = try database.prepare(
                "INSERT INTO metadata (key, value) VALUES (?, ?)"
            )
            for (key, value) in metadata(
                manifest: manifest,
                statistics: dataset.statistics
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
        statistics: CNS11643Statistics
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
            "duplicate_entries_removed": String(statistics.duplicateEntryCount)
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
        sourceDirectory: URL
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
