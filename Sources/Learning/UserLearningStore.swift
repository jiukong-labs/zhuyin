import Foundation
import SQLite3
import Darwin

enum UserLearningStoreError: LocalizedError {
    case invalidApplicationID(expected: Int64, actual: Int64)
    case unsupportedSchema(maximumSupported: Int, actual: Int)
    case invalidSchema(String)

    var errorDescription: String? {
        switch self {
        case let .invalidApplicationID(expected, actual):
            return "Invalid user database application ID \(actual); expected \(expected)."
        case let .unsupportedSchema(maximumSupported, actual):
            return "Unsupported user database schema \(actual); maximum supported is \(maximumSupported)."
        case let .invalidSchema(message):
            return "Invalid user database schema: \(message)"
        }
    }
}

final class UserLearningStore: UserLearningStoring {
    static let applicationID: Int64 = 0x4A5A5955
    static let schemaVersion = 4

    private static let maximumSelectionCount = Int64.max

    let databaseURL: URL
    private(set) var foreignKeyEnforcementEnabled = false

    private let database: SQLiteDatabase
    private let fileManager: FileManager
    private let operationLock = NSRecursiveLock()

    convenience init(
        location: UserDataLocation,
        fileManager: FileManager = .default
    ) throws {
        try location.prepareDirectory(fileManager: fileManager)
        try self.init(databaseURL: location.databaseURL, fileManager: fileManager)
    }

    init(
        databaseURL: URL,
        fileManager: FileManager = .default
    ) throws {
        self.databaseURL = databaseURL
        self.fileManager = fileManager

        let parentDirectory = databaseURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        if !fileManager.fileExists(
            atPath: parentDirectory.path,
            isDirectory: &isDirectory
        ) {
            try fileManager.createDirectory(
                at: parentDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } else if !isDirectory.boolValue {
            throw UserDataLocationError.unsafeDirectory(parentDirectory)
        }

        try Self.validateExistingDatabaseFile(at: databaseURL)

        database = try SQLiteDatabase(
            url: databaseURL,
            flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        )

        try database.execute("PRAGMA busy_timeout = 1000")
        try enableForeignKeys()
        try configureOrValidateSchema()
        try configureJournalAndSynchronousMode()
        try secureDatabaseFiles()
    }

    func records(
        for pronunciation: String
    ) throws -> [String: CharacterLearningRecord] {
        try withOperationLock {
            let statement = try database.prepare(
                """
                SELECT character, pronunciation, selection_count,
                       last_selected_at, pinned
                FROM character_learning
                WHERE pronunciation = ?
                ORDER BY character
                """
            )
            try statement.bind(pronunciation, at: 1)

            var result: [String: CharacterLearningRecord] = [:]
            while try statement.step() == .row {
                let record = try makeRecord(from: statement)
                result[record.character] = record
            }
            return result
        }
    }

    func recordSelection(
        character: String,
        pronunciation: String,
        at date: Date = Date()
    ) throws {
        try withOperationLock {
            let statement = try database.prepare(
                """
                INSERT INTO character_learning (
                    pronunciation,
                    character,
                    selection_count,
                    last_selected_at,
                    pinned
                ) VALUES (?, ?, 1, ?, 0)
                ON CONFLICT(pronunciation, character) DO UPDATE SET
                    selection_count = CASE
                        WHEN character_learning.selection_count < \(Self.maximumSelectionCount)
                        THEN character_learning.selection_count + 1
                        ELSE \(Self.maximumSelectionCount)
                    END,
                    last_selected_at = CASE
                        WHEN character_learning.last_selected_at IS NULL
                        THEN excluded.last_selected_at
                        WHEN excluded.last_selected_at > character_learning.last_selected_at
                        THEN excluded.last_selected_at
                        ELSE character_learning.last_selected_at
                    END
                """
            )
            try statement.bind(pronunciation, at: 1)
            try statement.bind(character, at: 2)
            try statement.bind(Self.milliseconds(since1970: date), at: 3)
            guard try statement.step() == .done else {
                throw UserLearningStoreError.invalidSchema(
                    "selection update returned an unexpected row"
                )
            }
            try secureDatabaseSidecars()
        }
    }

    func setPinned(
        _ pinned: Bool,
        character: String,
        pronunciation: String
    ) throws {
        try withOperationLock {
            let sql: String
            if pinned {
                sql =
                    """
                    INSERT INTO character_learning (
                        pronunciation,
                        character,
                        selection_count,
                        last_selected_at,
                        pinned
                    ) VALUES (?, ?, 0, NULL, 1)
                    ON CONFLICT(pronunciation, character) DO UPDATE SET
                        pinned = 1
                    """
            } else {
                sql =
                    """
                    UPDATE character_learning
                    SET pinned = 0
                    WHERE pronunciation = ? AND character = ?
                    """
            }
            let statement = try database.prepare(sql)
            try statement.bind(pronunciation, at: 1)
            try statement.bind(character, at: 2)
            guard try statement.step() == .done else {
                throw UserLearningStoreError.invalidSchema(
                    "pin update returned an unexpected row"
                )
            }
            try secureDatabaseSidecars()
        }
    }

    func phraseRecords(
        for pronunciationSequence: [String]
    ) throws -> [UserPhraseRecord] {
        let pronunciationKey = try UserPhrasePronunciationKey.encode(
            pronunciationSequence
        )
        return try withOperationLock {
            try phraseRecordsLocked(pronunciationKey: pronunciationKey)
        }
    }

    func addPhrase(
        phrase: String,
        pronunciationSequence: [String],
        createdAt: Date = Date()
    ) throws {
        guard let outputPattern = PhraseOutputPattern.inferred(
            from: phrase,
            readingCount: pronunciationSequence.count
        ) else {
            throw UserPhraseValidationError.invalidOutputPattern
        }
        try addPhrase(
            phrase: phrase,
            pronunciationSequence: pronunciationSequence,
            outputPattern: outputPattern,
            createdAt: createdAt
        )
    }

    func addPhrase(
        phrase: String,
        pronunciationSequence: [String],
        outputPattern: PhraseOutputPattern,
        createdAt: Date = Date()
    ) throws {
        let identity = try UserPhraseValidator.validate(
            phrase: phrase,
            pronunciationSequence: pronunciationSequence,
            outputPattern: outputPattern
        )

        try withOperationLock {
            try withImmediateTransaction {
                if let phraseID = try phraseIDLocked(for: identity) {
                    guard try phraseReadingsLocked(phraseID: phraseID)
                        == identity.pronunciationSequence,
                          try phrasePatternLocked(phraseID: phraseID)
                            == identity.outputPattern else {
                        throw UserLearningStoreError.invalidSchema(
                            "an existing user phrase has inconsistent readings"
                        )
                    }
                    return
                }

                try insertPhraseLocked(
                    identity: identity,
                    createdAtMilliseconds: Self.milliseconds(
                        since1970: createdAt
                    )
                )
            }
            try secureDatabaseSidecars()
        }
    }

    func recordPhraseSelection(
        phrase: String,
        pronunciationSequence: [String],
        at date: Date = Date()
    ) throws {
        let identity = try UserPhraseValidator.validate(
            phrase: phrase,
            pronunciationSequence: pronunciationSequence
        )
        try withOperationLock {
            let statement = try database.prepare(
                """
                UPDATE user_phrases
                SET selection_count = CASE
                        WHEN selection_count < \(Self.maximumSelectionCount)
                        THEN selection_count + 1
                        ELSE \(Self.maximumSelectionCount)
                    END,
                    last_used_at = CASE
                        WHEN last_used_at IS NULL THEN ?
                        WHEN ? > last_used_at THEN ?
                        ELSE last_used_at
                    END
                WHERE pronunciation_key = ? AND phrase = ?
                """
            )
            let timestamp = Self.milliseconds(since1970: date)
            try statement.bind(timestamp, at: 1)
            try statement.bind(timestamp, at: 2)
            try statement.bind(timestamp, at: 3)
            try statement.bind(identity.pronunciationKey, at: 4)
            try statement.bind(identity.phrase, at: 5)
            guard try statement.step() == .done else {
                throw UserLearningStoreError.invalidSchema(
                    "user phrase selection update returned an unexpected row"
                )
            }
            try secureDatabaseSidecars()
        }
    }

    func setPhrasePinned(
        _ pinned: Bool,
        phrase: String,
        pronunciationSequence: [String]
    ) throws {
        let identity = try UserPhraseValidator.validate(
            phrase: phrase,
            pronunciationSequence: pronunciationSequence
        )
        try withOperationLock {
            let statement = try database.prepare(
                """
                UPDATE user_phrases
                SET pinned = ?
                WHERE pronunciation_key = ? AND phrase = ?
                """
            )
            try statement.bind(pinned ? 1 : 0, at: 1)
            try statement.bind(identity.pronunciationKey, at: 2)
            try statement.bind(identity.phrase, at: 3)
            guard try statement.step() == .done else {
                throw UserLearningStoreError.invalidSchema(
                    "user phrase pin update returned an unexpected row"
                )
            }
            try secureDatabaseSidecars()
        }
    }

    /// Every learned character, ordered the way the settings list shows them:
    /// pinned first, then most used, then most recent, then deterministically.
    func allCharacterRecords() throws -> [CharacterLearningRecord] {
        try withOperationLock {
            let statement = try database.prepare(
                """
                SELECT character, pronunciation, selection_count,
                       last_selected_at, pinned
                FROM character_learning
                ORDER BY pinned DESC,
                         selection_count DESC,
                         last_selected_at IS NULL,
                         last_selected_at DESC,
                         pronunciation,
                         character
                """
            )

            var result: [CharacterLearningRecord] = []
            while try statement.step() == .row {
                result.append(try makeRecord(from: statement))
            }
            return result
        }
    }

    func allPhraseRecords() throws -> [UserPhraseRecord] {
        try withOperationLock {
            try phraseRecordsLocked(pronunciationKey: nil)
        }
    }

    /// Removes one learned character. A missing row is not an error, so the
    /// settings list stays usable when two windows delete the same entry.
    func deleteCharacterRecord(
        character: String,
        pronunciation: String
    ) throws {
        try withOperationLock {
            let statement = try database.prepare(
                """
                DELETE FROM character_learning
                WHERE pronunciation = ? AND character = ?
                """
            )
            try statement.bind(pronunciation, at: 1)
            try statement.bind(character, at: 2)
            guard try statement.step() == .done else {
                throw UserLearningStoreError.invalidSchema(
                    "character deletion returned an unexpected row"
                )
            }
            try secureDatabaseSidecars()
        }
    }

    /// Removes one user phrase and its ordered readings.
    func deletePhrase(
        phrase: String,
        pronunciationSequence: [String]
    ) throws {
        let identity = try UserPhraseValidator.validate(
            phrase: phrase,
            pronunciationSequence: pronunciationSequence
        )
        try withOperationLock {
            try withImmediateTransaction {
                guard let phraseID = try phraseIDLocked(for: identity) else {
                    return
                }
                try deletePhraseLocked(phraseID: phraseID)
            }
            try secureDatabaseSidecars()
        }
    }

    /// Hides one built-in dictionary phrase from the candidate window.
    ///
    /// The row is a tombstone in the user's own database rather than an edit
    /// to the bundled dictionary, so a dictionary shipped with a later app
    /// update cannot restore the phrase. Suppressing an identity twice keeps
    /// the first timestamp, which makes an import or a cloud merge idempotent.
    func suppressPhrase(
        phrase: String,
        pronunciationSequence: [String],
        at date: Date = Date()
    ) throws {
        let identity = try UserPhraseValidator.validate(
            phrase: phrase,
            pronunciationSequence: pronunciationSequence
        )
        try withOperationLock {
            let statement = try database.prepare(
                """
                INSERT INTO suppressed_phrases (
                    pronunciation_key,
                    phrase,
                    suppressed_at
                ) VALUES (?, ?, ?)
                ON CONFLICT(pronunciation_key, phrase) DO UPDATE SET
                    suppressed_at = MIN(
                        suppressed_phrases.suppressed_at,
                        excluded.suppressed_at
                    )
                """
            )
            try statement.bind(identity.pronunciationKey, at: 1)
            try statement.bind(identity.phrase, at: 2)
            try statement.bind(Self.milliseconds(since1970: date), at: 3)
            guard try statement.step() == .done else {
                throw UserLearningStoreError.invalidSchema(
                    "a phrase suppression returned an unexpected row"
                )
            }
            try secureDatabaseSidecars()
        }
    }

    /// Lets a previously removed built-in phrase appear again.
    func restorePhrase(
        phrase: String,
        pronunciationSequence: [String]
    ) throws {
        let identity = try UserPhraseValidator.validate(
            phrase: phrase,
            pronunciationSequence: pronunciationSequence
        )
        try withOperationLock {
            let statement = try database.prepare(
                """
                DELETE FROM suppressed_phrases
                WHERE pronunciation_key = ? AND phrase = ?
                """
            )
            try statement.bind(identity.pronunciationKey, at: 1)
            try statement.bind(identity.phrase, at: 2)
            guard try statement.step() == .done else {
                throw UserLearningStoreError.invalidSchema(
                    "a phrase restoration returned an unexpected row"
                )
            }
            try secureDatabaseSidecars()
        }
    }

    /// The phrase texts removed for exactly this reading sequence. Candidate
    /// lookup needs nothing else, so the hot path stays one indexed read.
    func suppressedPhrases(
        for pronunciationSequence: [String]
    ) throws -> Set<String> {
        let pronunciationKey = try UserPhrasePronunciationKey.encode(
            pronunciationSequence
        )
        return try withOperationLock {
            let statement = try database.prepare(
                """
                SELECT phrase
                FROM suppressed_phrases
                WHERE pronunciation_key = ?
                """
            )
            try statement.bind(pronunciationKey, at: 1)
            var result: Set<String> = []
            while try statement.step() == .row {
                result.insert(try statement.text(at: 0))
            }
            return result
        }
    }

    func allSuppressedPhrases() throws -> [SuppressedPhraseRecord] {
        try withOperationLock {
            let statement = try database.prepare(
                """
                SELECT pronunciation_key, phrase, suppressed_at
                FROM suppressed_phrases
                ORDER BY suppressed_at, phrase, pronunciation_key
                """
            )
            var result: [SuppressedPhraseRecord] = []
            while try statement.step() == .row {
                let key = try statement.text(at: 0)
                let phrase = try statement.text(at: 1)
                // A row whose key or pattern cannot be read back would have to
                // predate this schema. Skipping it keeps the settings list and
                // an export usable instead of failing the whole read.
                guard let readings = try? UserPhrasePronunciationKey.decode(key),
                      let pattern = PhraseOutputPattern.inferred(
                          from: phrase,
                          readingCount: readings.count
                      ) else {
                    continue
                }
                result.append(
                    SuppressedPhraseRecord(
                        phrase: phrase,
                        pronunciationSequence: readings,
                        outputPattern: pattern,
                        suppressedAt: Self.date(
                            millisecondsSince1970: statement.integer(at: 2)
                        )
                    )
                )
            }
            return result
        }
    }

    /// Merges an imported archive into the existing data in one transaction.
    ///
    /// Merging is idempotent: counts and timestamps take the larger value, pins
    /// are combined, and a phrase keeps the earliest creation time, so
    /// importing the same file twice changes nothing the second time.
    @discardableResult
    func merge(_ archive: UserDataArchive) throws -> UserDataMergeSummary {
        var summary = UserDataMergeSummary()
        try withOperationLock {
            try withImmediateTransaction {
                for entry in archive.characters {
                    try mergeCharacterLocked(entry)
                    summary.mergedCharacters += 1
                }
                for entry in archive.phrases {
                    try mergePhraseLocked(entry)
                    summary.mergedPhrases += 1
                }
                for entry in archive.suppressions {
                    try mergeSuppressionLocked(entry)
                    summary.mergedSuppressions += 1
                }
            }
            try secureDatabaseSidecars()
        }
        return summary
    }

    /// Removes every learned character row and leaves user phrases intact.
    func clearCharacterLearning() throws {
        try clear(statements: ["DELETE FROM character_learning"])
    }

    /// Removes every user phrase. Readings are deleted explicitly so the result
    /// is identical whether or not foreign keys are enforced.
    func clearUserPhrases() throws {
        try clear(
            statements: [
                "DELETE FROM user_phrase_readings",
                "DELETE FROM user_phrases",
            ]
        )
    }

    /// Restores every removed built-in phrase and leaves the rest untouched.
    func clearSuppressedPhrases() throws {
        try clear(statements: ["DELETE FROM suppressed_phrases"])
    }

    /// Empties every data set in one transaction, so a failure can never leave
    /// characters cleared while phrases survive.
    func clearAllUserData() throws {
        try clear(
            statements: [
                "DELETE FROM user_phrase_readings",
                "DELETE FROM user_phrases",
                "DELETE FROM character_learning",
                "DELETE FROM suppressed_phrases",
            ]
        )
    }

    /// Clearing keeps the schema, application ID, and version in place. The
    /// database file remains usable for the next selection without reopening.
    private func clear(statements: [String]) throws {
        try withOperationLock {
            try withImmediateTransaction {
                for statement in statements {
                    try database.execute(statement)
                }
                try validateSchema()
            }
            try secureDatabaseSidecars()
        }
    }

    private func configureOrValidateSchema() throws {
        let applicationID = try pragmaInteger("application_id")
        let schemaVersion = Int(try pragmaInteger("user_version"))
        let userTables = try existingUserTables()

        if applicationID == 0, schemaVersion == 0, userTables.isEmpty {
            try installCurrentSchema(setApplicationID: true)
        } else if applicationID == Self.applicationID, schemaVersion == 0 {
            guard userTables.isSubset(of: ["character_learning"]) else {
                throw UserLearningStoreError.invalidSchema(
                    "version 0 contains unknown tables"
                )
            }
            try installCurrentSchema(setApplicationID: false)
        } else {
            guard applicationID == Self.applicationID else {
                throw UserLearningStoreError.invalidApplicationID(
                    expected: Self.applicationID,
                    actual: applicationID
                )
            }
            guard schemaVersion <= Self.schemaVersion else {
                throw UserLearningStoreError.unsupportedSchema(
                    maximumSupported: Self.schemaVersion,
                    actual: schemaVersion
                )
            }
            switch schemaVersion {
            case 1:
                guard userTables == ["character_learning"] else {
                    throw UserLearningStoreError.invalidSchema(
                        "version 1 contains unexpected tables"
                    )
                }
                try validateCharacterSchema()
                try migrateVersionOneToCurrent()
            case 2:
                guard userTables == [
                    "character_learning",
                    "user_phrases",
                    "user_phrase_readings",
                ] else {
                    throw UserLearningStoreError.invalidSchema(
                        "version 2 contains unexpected tables"
                    )
                }
                try validateCharacterSchema()
                try validatePhraseSchema(expectsOutputPattern: false)
                try migrateVersionTwoToCurrent()
            case 3:
                guard userTables == [
                    "character_learning",
                    "user_phrases",
                    "user_phrase_readings",
                ] else {
                    throw UserLearningStoreError.invalidSchema(
                        "version 3 contains unexpected tables"
                    )
                }
                try validateCharacterSchema()
                try validatePhraseSchema(expectsOutputPattern: true)
                try migrateVersionThreeToCurrent()
            case Self.schemaVersion:
                try validateSchema()
            default:
                throw UserLearningStoreError.invalidSchema(
                    "no migration is available for version \(schemaVersion)"
                )
            }
        }

        try validateSchema()
    }

    private func installCurrentSchema(setApplicationID: Bool) throws {
        try withImmediateTransaction {
            try createCharacterSchema()
            try createPhraseSchema()
            try createSuppressionSchema()
            try validateSchema()
            if setApplicationID {
                try database.execute(
                    "PRAGMA application_id = \(Self.applicationID)"
                )
            }
            try database.execute("PRAGMA user_version = \(Self.schemaVersion)")
        }
    }

    private func migrateVersionOneToCurrent() throws {
        try withImmediateTransaction {
            try createPhraseSchema()
            try createSuppressionSchema()
            try validateSchema()
            try database.execute("PRAGMA user_version = \(Self.schemaVersion)")
        }
    }

    private func migrateVersionTwoToCurrent() throws {
        try withImmediateTransaction {
            try database.execute(
                "ALTER TABLE user_phrases ADD COLUMN unit_pattern TEXT NOT NULL DEFAULT ''"
            )
            let select = try database.prepare(
                "SELECT phrase_id, phrase FROM user_phrases ORDER BY phrase_id"
            )
            let update = try database.prepare(
                "UPDATE user_phrases SET unit_pattern = ? WHERE phrase_id = ?"
            )
            while try select.step() == .row {
                let phraseID = select.integer(at: 0)
                let phrase = try select.text(at: 1)
                guard let pattern = PhraseOutputPattern.allReadings(
                    count: phrase.count
                ) else {
                    throw UserLearningStoreError.invalidSchema(
                        "a version 2 phrase cannot be migrated"
                    )
                }
                try update.bind(pattern.rawValue, at: 1)
                try update.bind(phraseID, at: 2)
                guard try update.step() == .done else {
                    throw UserLearningStoreError.invalidSchema(
                        "a version 2 phrase pattern could not be migrated"
                    )
                }
                try update.reset()
            }
            try createSuppressionSchema()
            try validateSchema()
            try database.execute("PRAGMA user_version = \(Self.schemaVersion)")
        }
    }

    /// Version 3 stored characters and phrases but had nowhere to record that
    /// the user removed a built-in phrase. Only the new table is added, so an
    /// upgrade never rewrites existing learning data.
    private func migrateVersionThreeToCurrent() throws {
        try withImmediateTransaction {
            try createSuppressionSchema()
            try validateSchema()
            try database.execute("PRAGMA user_version = \(Self.schemaVersion)")
        }
    }

    private func createCharacterSchema() throws {
        try database.execute(
            """
            CREATE TABLE IF NOT EXISTS character_learning (
                pronunciation TEXT NOT NULL CHECK(length(pronunciation) > 0),
                character TEXT NOT NULL CHECK(length(character) > 0),
                selection_count INTEGER NOT NULL DEFAULT 0
                    CHECK(selection_count >= 0),
                last_selected_at INTEGER,
                pinned INTEGER NOT NULL DEFAULT 0
                    CHECK(pinned IN (0, 1)),
                PRIMARY KEY (pronunciation, character)
            ) WITHOUT ROWID
            """
        )
    }

    private func createPhraseSchema() throws {
        try database.execute(
            """
            CREATE TABLE IF NOT EXISTS user_phrases (
                phrase_id INTEGER PRIMARY KEY,
                phrase TEXT NOT NULL CHECK(length(phrase) > 0),
                pronunciation_key TEXT NOT NULL
                    CHECK(length(pronunciation_key) > 0),
                unit_pattern TEXT NOT NULL CHECK(length(unit_pattern) > 0),
                created_at INTEGER NOT NULL,
                last_used_at INTEGER,
                selection_count INTEGER NOT NULL DEFAULT 0
                    CHECK(selection_count >= 0),
                pinned INTEGER NOT NULL DEFAULT 0
                    CHECK(pinned IN (0, 1)),
                UNIQUE (pronunciation_key, phrase)
            )
            """
        )
        try database.execute(
            """
            CREATE TABLE IF NOT EXISTS user_phrase_readings (
                phrase_id INTEGER NOT NULL,
                reading_index INTEGER NOT NULL CHECK(reading_index >= 0),
                pronunciation TEXT NOT NULL CHECK(length(pronunciation) > 0),
                PRIMARY KEY (phrase_id, reading_index),
                FOREIGN KEY (phrase_id) REFERENCES user_phrases(phrase_id)
                    ON DELETE CASCADE
            ) WITHOUT ROWID
            """
        )
        try database.execute(
            """
            CREATE INDEX IF NOT EXISTS user_phrases_exact_lookup
            ON user_phrases (
                pronunciation_key,
                pinned DESC,
                selection_count DESC,
                last_used_at DESC,
                created_at,
                phrase
            )
            """
        )
    }

    private func createSuppressionSchema() throws {
        try database.execute(
            """
            CREATE TABLE IF NOT EXISTS suppressed_phrases (
                pronunciation_key TEXT NOT NULL
                    CHECK(length(pronunciation_key) > 0),
                phrase TEXT NOT NULL CHECK(length(phrase) > 0),
                suppressed_at INTEGER NOT NULL,
                PRIMARY KEY (pronunciation_key, phrase)
            ) WITHOUT ROWID
            """
        )
    }

    private func validateSchema() throws {
        let expectedTables: Set<String> = [
            "character_learning",
            "user_phrases",
            "user_phrase_readings",
            "suppressed_phrases",
        ]
        guard try existingUserTables() == expectedTables else {
            throw UserLearningStoreError.invalidSchema(
                "the user database has unexpected tables"
            )
        }
        try validateCharacterSchema()
        try validatePhraseSchema(expectsOutputPattern: true)
        try validateSuppressionSchema()
    }

    private func validateSuppressionSchema() throws {
        let expected: [String: ColumnDefinition] = [
            "pronunciation_key": ColumnDefinition(
                type: "TEXT",
                isNotNull: true,
                primaryKeyPosition: 1
            ),
            "phrase": ColumnDefinition(
                type: "TEXT",
                isNotNull: true,
                primaryKeyPosition: 2
            ),
            "suppressed_at": ColumnDefinition(
                type: "INTEGER",
                isNotNull: true,
                primaryKeyPosition: 0
            ),
        ]
        guard try columnDefinitions(for: "suppressed_phrases") == expected else {
            throw UserLearningStoreError.invalidSchema(
                "the suppressed phrase table has unexpected columns"
            )
        }
    }

    private func validateCharacterSchema() throws {
        let statement = try database.prepare(
            "PRAGMA table_info(character_learning)"
        )
        var columns: [String: ColumnDefinition] = [:]
        while try statement.step() == .row {
            let name = try statement.text(at: 1)
            columns[name] = ColumnDefinition(
                type: try statement.text(at: 2).uppercased(),
                isNotNull: statement.integer(at: 3) == 1,
                primaryKeyPosition: statement.integer(at: 5)
            )
        }

        let expected: [String: ColumnDefinition] = [
            "pronunciation": ColumnDefinition(
                type: "TEXT",
                isNotNull: true,
                primaryKeyPosition: 1
            ),
            "character": ColumnDefinition(
                type: "TEXT",
                isNotNull: true,
                primaryKeyPosition: 2
            ),
            "selection_count": ColumnDefinition(
                type: "INTEGER",
                isNotNull: true,
                primaryKeyPosition: 0
            ),
            "last_selected_at": ColumnDefinition(
                type: "INTEGER",
                isNotNull: false,
                primaryKeyPosition: 0
            ),
            "pinned": ColumnDefinition(
                type: "INTEGER",
                isNotNull: true,
                primaryKeyPosition: 0
            ),
        ]
        guard columns == expected else {
            throw UserLearningStoreError.invalidSchema(
                "character_learning has unexpected columns"
            )
        }

        let schemaStatement = try database.prepare(
            """
            SELECT sql
            FROM sqlite_master
            WHERE type = 'table' AND name = 'character_learning'
            """
        )
        guard try schemaStatement.step() == .row,
              try schemaStatement.text(at: 0)
                .uppercased()
                .contains("WITHOUT ROWID") else {
            throw UserLearningStoreError.invalidSchema(
                "character_learning must use WITHOUT ROWID"
            )
        }

        _ = try database.prepare(
            """
            SELECT pronunciation, character, selection_count,
                   last_selected_at, pinned
            FROM character_learning
            LIMIT 0
            """
        )
    }

    private func validatePhraseSchema(
        expectsOutputPattern: Bool
    ) throws {
        let phraseColumns = try columnDefinitions(for: "user_phrases")
        var expectedPhraseColumns: [String: ColumnDefinition] = [
            "phrase_id": ColumnDefinition(
                type: "INTEGER",
                isNotNull: false,
                primaryKeyPosition: 1
            ),
            "phrase": ColumnDefinition(
                type: "TEXT",
                isNotNull: true,
                primaryKeyPosition: 0
            ),
            "pronunciation_key": ColumnDefinition(
                type: "TEXT",
                isNotNull: true,
                primaryKeyPosition: 0
            ),
            "created_at": ColumnDefinition(
                type: "INTEGER",
                isNotNull: true,
                primaryKeyPosition: 0
            ),
            "last_used_at": ColumnDefinition(
                type: "INTEGER",
                isNotNull: false,
                primaryKeyPosition: 0
            ),
            "selection_count": ColumnDefinition(
                type: "INTEGER",
                isNotNull: true,
                primaryKeyPosition: 0
            ),
            "pinned": ColumnDefinition(
                type: "INTEGER",
                isNotNull: true,
                primaryKeyPosition: 0
            ),
        ]
        if expectsOutputPattern {
            expectedPhraseColumns["unit_pattern"] = ColumnDefinition(
                type: "TEXT",
                isNotNull: true,
                primaryKeyPosition: 0
            )
        }
        guard phraseColumns == expectedPhraseColumns else {
            throw UserLearningStoreError.invalidSchema(
                "user_phrases has unexpected columns"
            )
        }

        let readingColumns = try columnDefinitions(
            for: "user_phrase_readings"
        )
        let expectedReadingColumns: [String: ColumnDefinition] = [
            "phrase_id": ColumnDefinition(
                type: "INTEGER",
                isNotNull: true,
                primaryKeyPosition: 1
            ),
            "reading_index": ColumnDefinition(
                type: "INTEGER",
                isNotNull: true,
                primaryKeyPosition: 2
            ),
            "pronunciation": ColumnDefinition(
                type: "TEXT",
                isNotNull: true,
                primaryKeyPosition: 0
            ),
        ]
        guard readingColumns == expectedReadingColumns else {
            throw UserLearningStoreError.invalidSchema(
                "user_phrase_readings has unexpected columns"
            )
        }

        let readingSchema = try database.prepare(
            """
            SELECT sql
            FROM sqlite_master
            WHERE type = 'table' AND name = 'user_phrase_readings'
            """
        )
        guard try readingSchema.step() == .row,
              try readingSchema.text(at: 0)
                .uppercased()
                .contains("WITHOUT ROWID") else {
            throw UserLearningStoreError.invalidSchema(
                "user_phrase_readings must use WITHOUT ROWID"
            )
        }

        let foreignKey = try database.prepare(
            "PRAGMA foreign_key_list(user_phrase_readings)"
        )
        guard try foreignKey.step() == .row,
              try foreignKey.text(at: 2) == "user_phrases",
              try foreignKey.text(at: 3) == "phrase_id",
              try foreignKey.text(at: 4) == "phrase_id",
              try foreignKey.text(at: 6).uppercased() == "CASCADE",
              try foreignKey.step() == .done else {
            throw UserLearningStoreError.invalidSchema(
                "user phrase readings require one cascading foreign key"
            )
        }

        guard try hasUniquePhraseIdentityIndex() else {
            throw UserLearningStoreError.invalidSchema(
                "user phrases require a unique exact identity"
            )
        }
        guard try hasExactPhraseLookupIndex() else {
            throw UserLearningStoreError.invalidSchema(
                "user phrases require the exact-lookup index"
            )
        }

        let patternColumn = expectsOutputPattern ? ", p.unit_pattern" : ""
        _ = try database.prepare(
            """
            SELECT p.phrase_id, p.phrase, p.pronunciation_key,
                   p.created_at, p.last_used_at, p.selection_count, p.pinned,
                   r.reading_index, r.pronunciation\(patternColumn)
            FROM user_phrases AS p
            JOIN user_phrase_readings AS r ON r.phrase_id = p.phrase_id
            LIMIT 0
            """
        )
    }

    private func columnDefinitions(
        for table: String
    ) throws -> [String: ColumnDefinition] {
        let statement = try database.prepare("PRAGMA table_info(\(table))")
        var columns: [String: ColumnDefinition] = [:]
        while try statement.step() == .row {
            let name = try statement.text(at: 1)
            columns[name] = ColumnDefinition(
                type: try statement.text(at: 2).uppercased(),
                isNotNull: statement.integer(at: 3) == 1,
                primaryKeyPosition: statement.integer(at: 5)
            )
        }
        return columns
    }

    private func hasUniquePhraseIdentityIndex() throws -> Bool {
        let indexes = try database.prepare("PRAGMA index_list(user_phrases)")
        while try indexes.step() == .row {
            guard indexes.integer(at: 2) == 1 else {
                continue
            }
            let indexName = try indexes.text(at: 1)
                .replacingOccurrences(of: "'", with: "''")
            let columns = try database.prepare(
                "PRAGMA index_info('\(indexName)')"
            )
            var names: [String] = []
            while try columns.step() == .row {
                names.append(try columns.text(at: 2))
            }
            if names == ["pronunciation_key", "phrase"] {
                return true
            }
        }
        return false
    }

    private func hasExactPhraseLookupIndex() throws -> Bool {
        let statement = try database.prepare(
            "PRAGMA index_info('user_phrases_exact_lookup')"
        )
        var names: [String] = []
        while try statement.step() == .row {
            names.append(try statement.text(at: 2))
        }
        return names == [
            "pronunciation_key",
            "pinned",
            "selection_count",
            "last_used_at",
            "created_at",
            "phrase",
        ]
    }

    private func enableForeignKeys() throws {
        try database.execute("PRAGMA foreign_keys = ON")
        let foreignKeys = try pragmaInteger("foreign_keys")
        guard foreignKeys == 1 else {
            throw UserLearningStoreError.invalidSchema(
                "foreign key enforcement could not be enabled"
            )
        }
        foreignKeyEnforcementEnabled = true
    }

    private func configureJournalAndSynchronousMode() throws {
        let journalStatement = try database.prepare("PRAGMA journal_mode = WAL")
        guard try journalStatement.step() == .row,
              try journalStatement.text(at: 0).lowercased() == "wal" else {
            throw UserLearningStoreError.invalidSchema(
                "WAL journal mode could not be enabled"
            )
        }
        try database.execute("PRAGMA synchronous = NORMAL")
    }

    private func existingUserTables() throws -> Set<String> {
        let statement = try database.prepare(
            """
            SELECT name
            FROM sqlite_master
            WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
            """
        )
        var result: Set<String> = []
        while try statement.step() == .row {
            result.insert(try statement.text(at: 0))
        }
        return result
    }

    private func pragmaInteger(_ name: String) throws -> Int64 {
        let statement = try database.prepare("PRAGMA \(name)")
        guard try statement.step() == .row else {
            return 0
        }
        return statement.integer(at: 0)
    }

    /// A `nil` key lists every stored phrase, which the settings window needs.
    private func phraseRecordsLocked(
        pronunciationKey: String?
    ) throws -> [UserPhraseRecord] {
        let statement = try database.prepare(
            """
            SELECT p.phrase_id, p.phrase, p.created_at, p.last_used_at,
                   p.selection_count, p.pinned, p.unit_pattern,
                   r.reading_index, r.pronunciation
            FROM user_phrases AS p
            LEFT JOIN user_phrase_readings AS r
                ON r.phrase_id = p.phrase_id
            \(pronunciationKey == nil ? "" : "WHERE p.pronunciation_key = ?")
            ORDER BY p.pinned DESC,
                     p.selection_count DESC,
                     p.last_used_at IS NULL,
                     p.last_used_at DESC,
                     p.created_at,
                     p.phrase,
                     p.phrase_id,
                     r.reading_index
            """
        )
        if let pronunciationKey {
            try statement.bind(pronunciationKey, at: 1)
        }

        var orderedPhraseIDs: [Int64] = []
        var metadataByID: [Int64: PhraseRowMetadata] = [:]
        var readingsByID: [Int64: [String]] = [:]
        while try statement.step() == .row {
            let phraseID = statement.integer(at: 0)
            if metadataByID[phraseID] == nil {
                metadataByID[phraseID] = PhraseRowMetadata(
                    phraseID: phraseID,
                    phrase: try statement.text(at: 1),
                    createdAtMilliseconds: statement.integer(at: 2),
                    lastUsedAtMilliseconds: statement.isNull(at: 3)
                        ? nil
                        : statement.integer(at: 3),
                    selectionCount: statement.integer(at: 4),
                    pinned: statement.integer(at: 5) == 1,
                    outputPatternRawValue: try statement.text(at: 6)
                )
                orderedPhraseIDs.append(phraseID)
                readingsByID[phraseID] = []
            }

            guard !statement.isNull(at: 7), !statement.isNull(at: 8) else {
                throw UserLearningStoreError.invalidSchema(
                    "a user phrase has no readings"
                )
            }
            let readingIndex = statement.integer(at: 7)
            let expectedIndex = Int64(readingsByID[phraseID]?.count ?? 0)
            guard readingIndex == expectedIndex else {
                throw UserLearningStoreError.invalidSchema(
                    "user phrase readings are not contiguous"
                )
            }
            readingsByID[phraseID, default: []].append(
                try statement.text(at: 8)
            )
        }

        return try orderedPhraseIDs.map { phraseID in
            guard let metadata = metadataByID[phraseID],
                  let readings = readingsByID[phraseID] else {
                throw UserLearningStoreError.invalidSchema(
                    "a user phrase query returned incomplete data"
                )
            }
            guard let outputPattern = PhraseOutputPattern(
                rawValue: metadata.outputPatternRawValue
            ) else {
                throw UserLearningStoreError.invalidSchema(
                    "a user phrase has an invalid output pattern"
                )
            }
            let identity = try UserPhraseValidator.validate(
                phrase: metadata.phrase,
                pronunciationSequence: readings,
                outputPattern: outputPattern
            )
            guard identity.phrase == metadata.phrase,
                  identity.pronunciationSequence == readings,
                  identity.outputPattern == outputPattern,
                  pronunciationKey == nil
                    || identity.pronunciationKey == pronunciationKey else {
                throw UserLearningStoreError.invalidSchema(
                    "a user phrase is not stored in canonical form"
                )
            }
            return UserPhraseRecord(
                phraseID: metadata.phraseID,
                phrase: metadata.phrase,
                pronunciationSequence: readings,
                outputPattern: outputPattern,
                createdAt: Self.date(
                    millisecondsSince1970: metadata.createdAtMilliseconds
                ),
                lastUsedAt: metadata.lastUsedAtMilliseconds.map {
                    Self.date(millisecondsSince1970: $0)
                },
                selectionCount: metadata.selectionCount,
                pinned: metadata.pinned
            )
        }
    }

    @discardableResult
    private func insertPhraseLocked(
        identity: ValidatedUserPhrase,
        createdAtMilliseconds: Int64,
        lastUsedAtMilliseconds: Int64? = nil,
        selectionCount: Int64 = 0,
        pinned: Bool = false
    ) throws -> Int64 {
        let insertPhrase = try database.prepare(
            """
            INSERT INTO user_phrases (
                phrase,
                pronunciation_key,
                unit_pattern,
                created_at,
                last_used_at,
                selection_count,
                pinned
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """
        )
        try insertPhrase.bind(identity.phrase, at: 1)
        try insertPhrase.bind(identity.pronunciationKey, at: 2)
        try insertPhrase.bind(identity.outputPattern.rawValue, at: 3)
        try insertPhrase.bind(createdAtMilliseconds, at: 4)
        if let lastUsedAtMilliseconds {
            try insertPhrase.bind(lastUsedAtMilliseconds, at: 5)
        } else {
            try insertPhrase.bindNull(at: 5)
        }
        try insertPhrase.bind(max(0, selectionCount), at: 6)
        try insertPhrase.bind(pinned ? 1 : 0, at: 7)
        guard try insertPhrase.step() == .done else {
            throw UserLearningStoreError.invalidSchema(
                "user phrase insertion returned an unexpected row"
            )
        }

        let phraseIDStatement = try database.prepare("SELECT last_insert_rowid()")
        guard try phraseIDStatement.step() == .row else {
            throw UserLearningStoreError.invalidSchema(
                "a user phrase identifier was not returned"
            )
        }
        let phraseID = phraseIDStatement.integer(at: 0)

        let insertReading = try database.prepare(
            """
            INSERT INTO user_phrase_readings (
                phrase_id,
                reading_index,
                pronunciation
            ) VALUES (?, ?, ?)
            """
        )
        for (index, reading) in identity.pronunciationSequence.enumerated() {
            try insertReading.bind(phraseID, at: 1)
            try insertReading.bind(Int64(index), at: 2)
            try insertReading.bind(reading, at: 3)
            guard try insertReading.step() == .done else {
                throw UserLearningStoreError.invalidSchema(
                    "user phrase reading insertion returned an unexpected row"
                )
            }
            try insertReading.reset()
        }
        return phraseID
    }

    private func deletePhraseLocked(phraseID: Int64) throws {
        for sql in [
            "DELETE FROM user_phrase_readings WHERE phrase_id = ?",
            "DELETE FROM user_phrases WHERE phrase_id = ?",
        ] {
            let statement = try database.prepare(sql)
            try statement.bind(phraseID, at: 1)
            guard try statement.step() == .done else {
                throw UserLearningStoreError.invalidSchema(
                    "user phrase deletion returned an unexpected row"
                )
            }
        }
    }

    private func mergeCharacterLocked(_ entry: ArchivedCharacter) throws {
        let statement = try database.prepare(
            """
            INSERT INTO character_learning (
                pronunciation,
                character,
                selection_count,
                last_selected_at,
                pinned
            ) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(pronunciation, character) DO UPDATE SET
                selection_count = max(
                    character_learning.selection_count,
                    excluded.selection_count
                ),
                last_selected_at = CASE
                    WHEN character_learning.last_selected_at IS NULL
                    THEN excluded.last_selected_at
                    WHEN excluded.last_selected_at IS NULL
                    THEN character_learning.last_selected_at
                    ELSE max(
                        character_learning.last_selected_at,
                        excluded.last_selected_at
                    )
                END,
                pinned = max(character_learning.pinned, excluded.pinned)
            """
        )
        try statement.bind(entry.pronunciation, at: 1)
        try statement.bind(entry.character, at: 2)
        try statement.bind(max(0, entry.selectionCount), at: 3)
        if let lastSelectedAt = entry.lastSelectedAt {
            try statement.bind(lastSelectedAt, at: 4)
        } else {
            try statement.bindNull(at: 4)
        }
        try statement.bind(entry.pinned ? 1 : 0, at: 5)
        guard try statement.step() == .done else {
            throw UserLearningStoreError.invalidSchema(
                "character merge returned an unexpected row"
            )
        }
    }

    private func mergePhraseLocked(_ entry: ArchivedPhrase) throws {
        let outputPattern = entry.unitPattern.flatMap(
            PhraseOutputPattern.init(rawValue:)
        ) ?? PhraseOutputPattern.inferred(
            from: entry.phrase,
            readingCount: entry.readings.count
        )
        guard let outputPattern else {
            throw UserPhraseValidationError.invalidOutputPattern
        }
        let identity = try UserPhraseValidator.validate(
            phrase: entry.phrase,
            pronunciationSequence: entry.readings,
            outputPattern: outputPattern
        )
        guard let phraseID = try phraseIDLocked(for: identity) else {
            try insertPhraseLocked(
                identity: identity,
                createdAtMilliseconds: entry.createdAt,
                lastUsedAtMilliseconds: entry.lastUsedAt,
                selectionCount: entry.selectionCount,
                pinned: entry.pinned
            )
            return
        }

        guard try phraseReadingsLocked(phraseID: phraseID)
            == identity.pronunciationSequence,
              try phrasePatternLocked(phraseID: phraseID)
                == identity.outputPattern else {
            throw UserLearningStoreError.invalidSchema(
                "an existing user phrase has inconsistent readings"
            )
        }

        let statement = try database.prepare(
            """
            UPDATE user_phrases
            SET selection_count = max(selection_count, ?),
                created_at = min(created_at, ?),
                last_used_at = CASE
                    WHEN last_used_at IS NULL THEN ?
                    WHEN ? IS NULL THEN last_used_at
                    ELSE max(last_used_at, ?)
                END,
                pinned = max(pinned, ?)
            WHERE phrase_id = ?
            """
        )
        try statement.bind(max(0, entry.selectionCount), at: 1)
        try statement.bind(entry.createdAt, at: 2)
        for index in 3 ... 5 {
            if let lastUsedAt = entry.lastUsedAt {
                try statement.bind(lastUsedAt, at: Int32(index))
            } else {
                try statement.bindNull(at: Int32(index))
            }
        }
        try statement.bind(entry.pinned ? 1 : 0, at: 6)
        try statement.bind(phraseID, at: 7)
        guard try statement.step() == .done else {
            throw UserLearningStoreError.invalidSchema(
                "user phrase merge returned an unexpected row"
            )
        }
    }

    /// Merging keeps the earliest suppression time, so importing the same
    /// document twice, or merging the same cloud record again, changes nothing.
    private func mergeSuppressionLocked(
        _ entry: ArchivedSuppressedPhrase
    ) throws {
        let identity = try UserPhraseValidator.validate(
            phrase: entry.phrase,
            pronunciationSequence: entry.readings
        )
        let statement = try database.prepare(
            """
            INSERT INTO suppressed_phrases (
                pronunciation_key,
                phrase,
                suppressed_at
            ) VALUES (?, ?, ?)
            ON CONFLICT(pronunciation_key, phrase) DO UPDATE SET
                suppressed_at = MIN(
                    suppressed_phrases.suppressed_at,
                    excluded.suppressed_at
                )
            """
        )
        try statement.bind(identity.pronunciationKey, at: 1)
        try statement.bind(identity.phrase, at: 2)
        try statement.bind(entry.suppressedAt, at: 3)
        guard try statement.step() == .done else {
            throw UserLearningStoreError.invalidSchema(
                "a phrase suppression merge returned an unexpected row"
            )
        }
    }

    private func phraseIDLocked(
        for identity: ValidatedUserPhrase
    ) throws -> Int64? {
        let statement = try database.prepare(
            """
            SELECT phrase_id
            FROM user_phrases
            WHERE pronunciation_key = ? AND phrase = ?
            """
        )
        try statement.bind(identity.pronunciationKey, at: 1)
        try statement.bind(identity.phrase, at: 2)
        guard try statement.step() == .row else {
            return nil
        }
        let phraseID = statement.integer(at: 0)
        guard try statement.step() == .done else {
            throw UserLearningStoreError.invalidSchema(
                "a user phrase exact identity is not unique"
            )
        }
        return phraseID
    }

    private func phraseReadingsLocked(phraseID: Int64) throws -> [String] {
        let statement = try database.prepare(
            """
            SELECT reading_index, pronunciation
            FROM user_phrase_readings
            WHERE phrase_id = ?
            ORDER BY reading_index
            """
        )
        try statement.bind(phraseID, at: 1)
        var readings: [String] = []
        while try statement.step() == .row {
            guard statement.integer(at: 0) == Int64(readings.count) else {
                throw UserLearningStoreError.invalidSchema(
                    "user phrase readings are not contiguous"
                )
            }
            readings.append(try statement.text(at: 1))
        }
        return readings
    }

    private func phrasePatternLocked(
        phraseID: Int64
    ) throws -> PhraseOutputPattern {
        let statement = try database.prepare(
            "SELECT unit_pattern FROM user_phrases WHERE phrase_id = ?"
        )
        try statement.bind(phraseID, at: 1)
        guard try statement.step() == .row,
              let pattern = PhraseOutputPattern(
                  rawValue: try statement.text(at: 0)
              ),
              try statement.step() == .done else {
            throw UserLearningStoreError.invalidSchema(
                "a user phrase has an invalid output pattern"
            )
        }
        return pattern
    }

    private func withImmediateTransaction<T>(
        _ operation: () throws -> T
    ) throws -> T {
        try database.execute("BEGIN IMMEDIATE")
        do {
            let result = try operation()
            try database.execute("COMMIT")
            return result
        } catch {
            try? database.execute("ROLLBACK")
            throw error
        }
    }

    private func withOperationLock<T>(
        _ operation: () throws -> T
    ) rethrows -> T {
        operationLock.lock()
        defer { operationLock.unlock() }
        return try operation()
    }

    private func makeRecord(
        from statement: SQLiteStatement
    ) throws -> CharacterLearningRecord {
        let milliseconds: Int64? = statement.isNull(at: 3)
            ? nil
            : statement.integer(at: 3)
        return CharacterLearningRecord(
            character: try statement.text(at: 0),
            pronunciation: try statement.text(at: 1),
            selectionCount: statement.integer(at: 2),
            lastSelectedAt: milliseconds.map {
                Date(timeIntervalSince1970: Double($0) / 1_000)
            },
            pinned: statement.integer(at: 4) == 1
        )
    }

    private func secureDatabaseFiles() throws {
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: databaseURL.path
        )
        try secureDatabaseSidecars()
    }

    private func secureDatabaseSidecars() throws {
        for suffix in ["-wal", "-shm"] {
            let path = databaseURL.path + suffix
            guard fileManager.fileExists(atPath: path) else {
                continue
            }
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: path
            )
        }
    }

    private static func milliseconds(since1970 date: Date) -> Int64 {
        let milliseconds = date.timeIntervalSince1970 * 1_000
        if milliseconds >= Double(Int64.max) {
            return Int64.max
        }
        if milliseconds <= Double(Int64.min) {
            return Int64.min
        }
        return Int64(milliseconds.rounded(.towardZero))
    }

    private static func date(millisecondsSince1970: Int64) -> Date {
        Date(timeIntervalSince1970: Double(millisecondsSince1970) / 1_000)
    }

    private static func validateExistingDatabaseFile(at url: URL) throws {
        var fileStatus = stat()
        let result = url.path.withCString { path in
            lstat(path, &fileStatus)
        }
        if result == 0 {
            guard fileStatus.st_mode & S_IFMT == S_IFREG else {
                throw UserDataLocationError.unsafeDatabaseFile(url)
            }
            return
        }
        guard errno == ENOENT else {
            throw CocoaError(
                .fileReadUnknown,
                userInfo: [NSFilePathErrorKey: url.path]
            )
        }
    }
}

private struct ColumnDefinition: Equatable {
    let type: String
    let isNotNull: Bool
    let primaryKeyPosition: Int64
}

private struct PhraseRowMetadata {
    let phraseID: Int64
    let phrase: String
    let createdAtMilliseconds: Int64
    let lastUsedAtMilliseconds: Int64?
    let selectionCount: Int64
    let pinned: Bool
    let outputPatternRawValue: String
}
