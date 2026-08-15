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
    static let schemaVersion = 1

    private static let maximumSelectionCount = Int64.max

    let databaseURL: URL

    private let database: SQLiteDatabase
    private let fileManager: FileManager

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
        try configureOrValidateSchema()
        try configureConnection()
        try secureDatabaseFiles()
    }

    func records(
        for pronunciation: String
    ) throws -> [String: CharacterLearningRecord] {
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

    func recordSelection(
        character: String,
        pronunciation: String,
        at date: Date = Date()
    ) throws {
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

    func setPinned(
        _ pinned: Bool,
        character: String,
        pronunciation: String
    ) throws {
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

    private func configureOrValidateSchema() throws {
        let applicationID = try pragmaInteger("application_id")
        let schemaVersion = Int(try pragmaInteger("user_version"))
        let userTables = try existingUserTables()

        if applicationID == 0, schemaVersion == 0, userTables.isEmpty {
            try installSchema(setApplicationID: true)
        } else if applicationID == Self.applicationID, schemaVersion == 0 {
            guard userTables.isSubset(of: ["character_learning"]) else {
                throw UserLearningStoreError.invalidSchema(
                    "version 0 contains unknown tables"
                )
            }
            try installSchema(setApplicationID: false)
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
            guard schemaVersion == Self.schemaVersion else {
                throw UserLearningStoreError.invalidSchema(
                    "no migration is available for version \(schemaVersion)"
                )
            }
        }

        try validateSchema()
    }

    private func installSchema(setApplicationID: Bool) throws {
        try database.execute("BEGIN IMMEDIATE")
        do {
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
            try validateSchema()
            if setApplicationID {
                try database.execute(
                    "PRAGMA application_id = \(Self.applicationID)"
                )
            }
            try database.execute("PRAGMA user_version = \(Self.schemaVersion)")
            try database.execute("COMMIT")
        } catch {
            try? database.execute("ROLLBACK")
            throw error
        }
    }

    private func validateSchema() throws {
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

    private func configureConnection() throws {
        try database.execute("PRAGMA foreign_keys = ON")
        let foreignKeys = try pragmaInteger("foreign_keys")
        guard foreignKeys == 1 else {
            throw UserLearningStoreError.invalidSchema(
                "foreign key enforcement could not be enabled"
            )
        }

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
