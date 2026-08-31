import Foundation
import SQLite3
import XCTest

final class UserPhraseStoreTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
        try super.tearDownWithError()
    }

    func testFreshSchemaUsesVersionThreeAndEnablesForeignKeys() throws {
        let (location, store) = try makeStore()

        XCTAssertEqual(UserLearningStore.schemaVersion, 3)
        XCTAssertTrue(store.foreignKeyEnforcementEnabled)

        let database = try openDatabase(at: location.databaseURL)
        XCTAssertEqual(try pragma("user_version", database: database), 3)
        XCTAssertEqual(
            try userTables(database: database),
            [
                "character_learning",
                "user_phrase_readings",
                "user_phrases",
            ]
        )

        let foreignKey = try database.prepare(
            "PRAGMA foreign_key_list(user_phrase_readings)"
        )
        XCTAssertEqual(try foreignKey.step(), .row)
        XCTAssertEqual(try foreignKey.text(at: 2), "user_phrases")
        XCTAssertEqual(try foreignKey.text(at: 3), "phrase_id")
        XCTAssertEqual(try foreignKey.text(at: 4), "phrase_id")
        XCTAssertEqual(try foreignKey.text(at: 6).uppercased(), "CASCADE")
        XCTAssertEqual(try foreignKey.step(), .done)
    }

    func testAtomicallyMigratesVersionOneAndPreservesCharacterRows() throws {
        let root = try makeTemporaryDirectory()
        let location = UserDataLocation(applicationSupportRootURL: root)
        try installVersionOneDatabase(
            at: location,
            character: "鍵",
            pronunciation: "ㄐㄧㄢˋ"
        )

        let store = try UserLearningStore(location: location)

        XCTAssertTrue(store.foreignKeyEnforcementEnabled)
        let character = try XCTUnwrap(
            store.records(for: "ㄐㄧㄢˋ")["鍵"]
        )
        XCTAssertEqual(character.selectionCount, 7)
        XCTAssertEqual(
            character.lastSelectedAt,
            Date(timeIntervalSince1970: 1_700_000_000.125)
        )
        XCTAssertTrue(character.pinned)
        XCTAssertEqual(
            try store.phraseRecords(for: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"]),
            []
        )

        let database = try openDatabase(at: location.databaseURL)
        XCTAssertEqual(try pragma("user_version", database: database), 3)
        XCTAssertEqual(
            try userTables(database: database),
            [
                "character_learning",
                "user_phrase_readings",
                "user_phrases",
            ]
        )
    }

    func testFailedMigrationRollsBackTablesVersionAndCharacterData() throws {
        let root = try makeTemporaryDirectory()
        let location = UserDataLocation(applicationSupportRootURL: root)
        try installVersionOneDatabase(
            at: location,
            character: "我",
            pronunciation: "ㄨㄛˇ"
        )
        do {
            let database = try openDatabase(at: location.databaseURL)
            try database.execute(
                """
                CREATE INDEX user_phrases_exact_lookup
                ON character_learning(pronunciation, character)
                """
            )
        }

        XCTAssertThrowsError(try UserLearningStore(location: location)) { error in
            guard case UserLearningStoreError.invalidSchema = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        let database = try openDatabase(at: location.databaseURL)
        XCTAssertEqual(try pragma("user_version", database: database), 1)
        XCTAssertEqual(try userTables(database: database), ["character_learning"])
        let row = try database.prepare(
            """
            SELECT selection_count, pinned
            FROM character_learning
            WHERE pronunciation = 'ㄨㄛˇ' AND character = '我'
            """
        )
        XCTAssertEqual(try row.step(), .row)
        XCTAssertEqual(row.integer(at: 0), 7)
        XCTAssertEqual(row.integer(at: 1), 1)
    }

    func testAddIsNFCNormalizedAndIdempotent() throws {
        let (_, store) = try makeStore()
        let originalCreatedAt = Date(timeIntervalSince1970: 100.125)
        try store.addPhrase(
            phrase: "e\u{301}好",
            pronunciationSequence: ["ㄟˊ", "ㄏㄠˇ"],
            createdAt: originalCreatedAt
        )
        try store.addPhrase(
            phrase: "é好",
            pronunciationSequence: ["ㄟˊ", "ㄏㄠˇ"],
            createdAt: Date(timeIntervalSince1970: 999)
        )

        let records = try store.phraseRecords(for: ["ㄟˊ", "ㄏㄠˇ"])
        XCTAssertEqual(records.count, 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.phrase, "é好")
        XCTAssertEqual(record.pronunciationSequence, ["ㄟˊ", "ㄏㄠˇ"])
        XCTAssertEqual(record.createdAt, originalCreatedAt)
        XCTAssertNil(record.lastUsedAt)
        XCTAssertEqual(record.selectionCount, 0)
        XCTAssertFalse(record.pinned)
    }

    func testExactLookupUsesLengthPrefixedSequenceIdentity() throws {
        let (_, store) = try makeStore()
        let firstReadings = ["ㄅ", "ㄧㄚ"]
        let secondReadings = ["ㄅㄧ", "ㄚ"]
        XCTAssertEqual(firstReadings.joined(), secondReadings.joined())

        try store.addPhrase(
            phrase: "甲乙",
            pronunciationSequence: firstReadings,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        try store.addPhrase(
            phrase: "丙丁",
            pronunciationSequence: secondReadings,
            createdAt: Date(timeIntervalSince1970: 2)
        )

        XCTAssertEqual(
            try store.phraseRecords(for: firstReadings).map(\.phrase),
            ["甲乙"]
        )
        XCTAssertEqual(
            try store.phraseRecords(for: secondReadings).map(\.phrase),
            ["丙丁"]
        )
    }

    func testPhraseUsageSaturatesKeepsNewestTimeAndPreservesPin() throws {
        let (location, store) = try makeStore()
        let readings = ["ㄐㄧㄡˇ", "ㄎㄨㄥ"]
        try store.addPhrase(
            phrase: "久空",
            pronunciationSequence: readings,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        try store.setPhrasePinned(
            true,
            phrase: "久空",
            pronunciationSequence: readings
        )
        do {
            let database = try openDatabase(at: location.databaseURL)
            try database.execute("PRAGMA busy_timeout = 1000")
            let update = try database.prepare(
                """
                UPDATE user_phrases
                SET selection_count = ?, last_used_at = ?
                WHERE phrase = ?
                """
            )
            try update.bind(Int64.max, at: 1)
            try update.bind(Int64(2_000_000), at: 2)
            try update.bind("久空", at: 3)
            XCTAssertEqual(try update.step(), .done)
        }

        try store.recordPhraseSelection(
            phrase: "久空",
            pronunciationSequence: readings,
            at: Date(timeIntervalSince1970: 1_000)
        )
        var record = try XCTUnwrap(store.phraseRecords(for: readings).first)
        XCTAssertEqual(record.selectionCount, Int64.max)
        XCTAssertEqual(record.lastUsedAt, Date(timeIntervalSince1970: 2_000))
        XCTAssertTrue(record.pinned)

        try store.recordPhraseSelection(
            phrase: "久空",
            pronunciationSequence: readings,
            at: Date(timeIntervalSince1970: 3_000)
        )
        record = try XCTUnwrap(store.phraseRecords(for: readings).first)
        XCTAssertEqual(record.selectionCount, Int64.max)
        XCTAssertEqual(record.lastUsedAt, Date(timeIntervalSince1970: 3_000))
        XCTAssertTrue(record.pinned)
    }

    func testUnknownUsageAndPinDoNotCreatePhrase() throws {
        let (_, store) = try makeStore()
        let readings = ["ㄅ", "ㄆ"]

        try store.recordPhraseSelection(
            phrase: "甲乙",
            pronunciationSequence: readings,
            at: Date(timeIntervalSince1970: 1)
        )
        try store.setPhrasePinned(
            true,
            phrase: "甲乙",
            pronunciationSequence: readings
        )

        XCTAssertEqual(try store.phraseRecords(for: readings), [])
    }

    func testOrderedReadingsCascadeWhenParentIsDeleted() throws {
        let (location, store) = try makeStore()
        let readings = ["ㄩㄢˊ", "ㄗ"]
        try store.addPhrase(
            phrase: "原資",
            pronunciationSequence: readings,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let phraseID = try XCTUnwrap(
            store.phraseRecords(for: readings).first?.phraseID
        )

        let database = try openDatabase(at: location.databaseURL)
        try database.execute("PRAGMA foreign_keys = ON")
        let delete = try database.prepare(
            "DELETE FROM user_phrases WHERE phrase_id = ?"
        )
        try delete.bind(phraseID, at: 1)
        XCTAssertEqual(try delete.step(), .done)

        let count = try database.prepare(
            """
            SELECT count(*)
            FROM user_phrase_readings
            WHERE phrase_id = \(phraseID)
            """
        )
        XCTAssertEqual(try count.step(), .row)
        XCTAssertEqual(count.integer(at: 0), 0)
        XCTAssertEqual(try store.phraseRecords(for: readings), [])
    }

    func testConcurrentMultiStepAddsAreIdempotentAndUsageIsAtomic() throws {
        let (_, store) = try makeStore()
        let readings = ["ㄐㄧㄡˇ", "ㄎㄨㄥ"]
        let failures = PhraseLockedErrors()

        DispatchQueue.concurrentPerform(iterations: 80) { index in
            do {
                try store.addPhrase(
                    phrase: "久空",
                    pronunciationSequence: readings,
                    createdAt: Date(timeIntervalSince1970: TimeInterval(index))
                )
            } catch {
                failures.append(error)
            }
        }
        XCTAssertTrue(failures.values.isEmpty, "\(failures.values)")
        XCTAssertEqual(try store.phraseRecords(for: readings).count, 1)

        DispatchQueue.concurrentPerform(iterations: 200) { index in
            do {
                try store.recordPhraseSelection(
                    phrase: "久空",
                    pronunciationSequence: readings,
                    at: Date(timeIntervalSince1970: TimeInterval(index))
                )
            } catch {
                failures.append(error)
            }
        }
        XCTAssertTrue(failures.values.isEmpty, "\(failures.values)")
        let record = try XCTUnwrap(store.phraseRecords(for: readings).first)
        XCTAssertEqual(record.selectionCount, 200)
        XCTAssertEqual(record.lastUsedAt, Date(timeIntervalSince1970: 199))
    }

    func testConcurrentConnectionsDoNotDuplicatePhraseOrReadings() throws {
        let root = try makeTemporaryDirectory()
        let location = UserDataLocation(applicationSupportRootURL: root)
        let stores = try (0 ..< 8).map { _ in
            try UserLearningStore(location: location)
        }
        let readings = ["ㄇㄚˇ", "ㄐㄧㄝ"]
        let failures = PhraseLockedErrors()

        DispatchQueue.concurrentPerform(iterations: stores.count) { index in
            do {
                try stores[index].addPhrase(
                    phrase: "馬偕",
                    pronunciationSequence: readings,
                    createdAt: Date(timeIntervalSince1970: TimeInterval(index))
                )
            } catch {
                failures.append(error)
            }
        }

        XCTAssertTrue(failures.values.isEmpty, "\(failures.values)")
        let records = try stores[0].phraseRecords(for: readings)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.pronunciationSequence, readings)
    }

    private func makeStore() throws -> (UserDataLocation, UserLearningStore) {
        let root = try makeTemporaryDirectory()
        let location = UserDataLocation(applicationSupportRootURL: root)
        return (location, try UserLearningStore(location: location))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: false
        )
        temporaryDirectories.append(url)
        return url
    }

    private func openDatabase(at url: URL) throws -> SQLiteDatabase {
        try SQLiteDatabase(
            url: url,
            flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        )
    }

    private func installVersionOneDatabase(
        at location: UserDataLocation,
        character: String,
        pronunciation: String
    ) throws {
        try location.prepareDirectory()
        let database = try SQLiteDatabase(
            url: location.databaseURL,
            flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        )
        try database.execute(
            """
            CREATE TABLE character_learning (
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
        let insert = try database.prepare(
            """
            INSERT INTO character_learning (
                pronunciation, character, selection_count,
                last_selected_at, pinned
            ) VALUES (?, ?, 7, 1700000000125, 1)
            """
        )
        try insert.bind(pronunciation, at: 1)
        try insert.bind(character, at: 2)
        XCTAssertEqual(try insert.step(), .done)
        try database.execute(
            "PRAGMA application_id = \(UserLearningStore.applicationID)"
        )
        try database.execute("PRAGMA user_version = 1")
    }

    private func pragma(
        _ name: String,
        database: SQLiteDatabase
    ) throws -> Int64 {
        let statement = try database.prepare("PRAGMA \(name)")
        XCTAssertEqual(try statement.step(), .row)
        return statement.integer(at: 0)
    }

    private func userTables(database: SQLiteDatabase) throws -> Set<String> {
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
}

private final class PhraseLockedErrors {
    private let lock = NSLock()
    private var storage: [Error] = []

    var values: [Error] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ error: Error) {
        lock.lock()
        storage.append(error)
        lock.unlock()
    }
}
