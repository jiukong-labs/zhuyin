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
    static let schemaVersion = 2

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
        let identity = try UserPhraseValidator.validate(
            phrase: phrase,
            pronunciationSequence: pronunciationSequence
        )

        try withOperationLock {
            try withImmediateTransaction {
                if let phraseID = try phraseIDLocked(for: identity) {
                    guard try phraseReadingsLocked(phraseID: phraseID)
                        == identity.pronunciationSequence else {
                        throw UserLearningStoreError.invalidSchema(
                            "an existing user phrase has inconsistent readings"
                        )
                    }
                    return
                }

                let insertPhrase = try database.prepare(
                    """
                    INSERT INTO user_phrases (
                        phrase,
                        pronunciation_key,
                        created_at,
                        last_used_at,
                        selection_count,
                        pinned
                    ) VALUES (?, ?, ?, NULL, 0, 0)
                    """
                )
                try insertPhrase.bind(identity.phrase, at: 1)
                try insertPhrase.bind(identity.pronunciationKey, at: 2)
                try insertPhrase.bind(
                    Self.milliseconds(since1970: createdAt),
                    at: 3
                )
                guard try insertPhrase.step() == .done else {
                    throw UserLearningStoreError.invalidSchema(
                        "user phrase insertion returned an unexpected row"
                    )
                }

                let phraseIDStatement = try database.prepare(
                    "SELECT last_insert_rowid()"
                )
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

    private func validateSchema() throws {
        let expectedTables: Set<String> = [
            "character_learning",
            "user_phrases",
            "user_phrase_readings",
        ]
        guard try existingUserTables() == expectedTables else {
            throw UserLearningStoreError.invalidSchema(
                "the user database has unexpected tables"
            )
        }
        try validateCharacterSchema()
        try validatePhraseSchema()
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

    private func validatePhraseSchema() throws {
        let phraseColumns = try columnDefinitions(for: "user_phrases")
        let expectedPhraseColumns: [String: ColumnDefinition] = [
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

        _ = try database.prepare(
            """
            SELECT p.phrase_id, p.phrase, p.pronunciation_key,
                   p.created_at, p.last_used_at, p.selection_count, p.pinned,
                   r.reading_index, r.pronunciation
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

    private func phraseRecordsLocked(
        pronunciationKey: String
    ) throws -> [UserPhraseRecord] {
        let statement = try database.prepare(
            """
            SELECT p.phrase_id, p.phrase, p.created_at, p.last_used_at,
                   p.selection_count, p.pinned,
                   r.reading_index, r.pronunciation
            FROM user_phrases AS p
            LEFT JOIN user_phrase_readings AS r
                ON r.phrase_id = p.phrase_id
            WHERE p.pronunciation_key = ?
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
        try statement.bind(pronunciationKey, at: 1)

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
                    pinned: statement.integer(at: 5) == 1
                )
                orderedPhraseIDs.append(phraseID)
                readingsByID[phraseID] = []
            }

            guard !statement.isNull(at: 6), !statement.isNull(at: 7) else {
                throw UserLearningStoreError.invalidSchema(
                    "a user phrase has no readings"
                )
            }
            let readingIndex = statement.integer(at: 6)
            let expectedIndex = Int64(readingsByID[phraseID]?.count ?? 0)
            guard readingIndex == expectedIndex else {
                throw UserLearningStoreError.invalidSchema(
                    "user phrase readings are not contiguous"
                )
            }
            readingsByID[phraseID, default: []].append(
                try statement.text(at: 7)
            )
        }

        return try orderedPhraseIDs.map { phraseID in
            guard let metadata = metadataByID[phraseID],
                  let readings = readingsByID[phraseID] else {
                throw UserLearningStoreError.invalidSchema(
                    "a user phrase query returned incomplete data"
                )
            }
            let identity = try UserPhraseValidator.validate(
                phrase: metadata.phrase,
                pronunciationSequence: readings
            )
            guard identity.phrase == metadata.phrase,
                  identity.pronunciationSequence == readings,
                  identity.pronunciationKey == pronunciationKey else {
                throw UserLearningStoreError.invalidSchema(
                    "a user phrase is not stored in canonical form"
                )
            }
            return UserPhraseRecord(
                phraseID: metadata.phraseID,
                phrase: metadata.phrase,
                pronunciationSequence: readings,
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
}
