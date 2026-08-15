import Foundation
import SQLite3
import XCTest

final class UserLearningStoreTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
        try super.tearDownWithError()
    }

    func testCreatesIdentifiedVersionedWALDatabaseWithPrivatePermissions() throws {
        let (location, store) = try makeStore()
        _ = store

        XCTAssertEqual(try permissions(at: location.directoryURL), 0o700)
        XCTAssertEqual(try permissions(at: location.databaseURL), 0o600)

        let database = try SQLiteDatabase(
            url: location.databaseURL,
            flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        )
        XCTAssertEqual(
            try pragmaInteger("application_id", database: database),
            UserLearningStore.applicationID
        )
        XCTAssertEqual(
            try pragmaInteger("user_version", database: database),
            Int64(UserLearningStore.schemaVersion)
        )

        let journal = try database.prepare("PRAGMA journal_mode")
        XCTAssertEqual(try journal.step(), .row)
        XCTAssertEqual(try journal.text(at: 0).lowercased(), "wal")

        let schema = try database.prepare(
            "SELECT sql FROM sqlite_master WHERE name = 'character_learning'"
        )
        XCTAssertEqual(try schema.step(), .row)
        XCTAssertTrue(
            try schema.text(at: 0).uppercased().contains("WITHOUT ROWID")
        )

        for suffix in ["-wal", "-shm"] {
            let url = URL(fileURLWithPath: location.databaseURL.path + suffix)
            if FileManager.default.fileExists(atPath: url.path) {
                XCTAssertEqual(try permissions(at: url), 0o600)
            }
        }
    }

    func testRecordsSelectionsAndKeepsNewestTimestamp() throws {
        let (_, store) = try makeStore()
        let newer = Date(timeIntervalSince1970: 1_700_000_000.125)
        let older = newer.addingTimeInterval(-86_400)

        try store.recordSelection(
            character: "鍵",
            pronunciation: "ㄐㄧㄢˋ",
            at: newer
        )
        try store.recordSelection(
            character: "鍵",
            pronunciation: "ㄐㄧㄢˋ",
            at: older
        )

        let record = try XCTUnwrap(
            store.records(for: "ㄐㄧㄢˋ")["鍵"]
        )
        XCTAssertEqual(record.selectionCount, 2)
        XCTAssertEqual(record.lastSelectedAt, newer)
        XCTAssertFalse(record.pinned)
    }

    func testRecordsAreIsolatedByPronunciationAndCharacter() throws {
        let (_, store) = try makeStore()
        let date = Date(timeIntervalSince1970: 123)
        try store.recordSelection(
            character: "行",
            pronunciation: "ㄒㄧㄥˊ",
            at: date
        )
        try store.recordSelection(
            character: "行",
            pronunciation: "ㄏㄤˊ",
            at: date
        )
        try store.recordSelection(
            character: "型",
            pronunciation: "ㄒㄧㄥˊ",
            at: date
        )

        XCTAssertEqual(
            Set(try store.records(for: "ㄒㄧㄥˊ").keys),
            ["行", "型"]
        )
        XCTAssertEqual(
            Set(try store.records(for: "ㄏㄤˊ").keys),
            ["行"]
        )
    }

    func testSelectionCountSaturatesWithoutOverflow() throws {
        let (location, store) = try makeStore()
        do {
            let database = try SQLiteDatabase(
                url: location.databaseURL,
                flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
            )
            let insert = try database.prepare(
                """
                INSERT INTO character_learning
                    (pronunciation, character, selection_count,
                     last_selected_at, pinned)
                VALUES (?, ?, ?, NULL, 0)
                """
            )
            try insert.bind("ㄨㄛˇ", at: 1)
            try insert.bind("我", at: 2)
            try insert.bind(Int64.max, at: 3)
            XCTAssertEqual(try insert.step(), .done)
        }

        try store.recordSelection(
            character: "我",
            pronunciation: "ㄨㄛˇ",
            at: Date(timeIntervalSince1970: 1)
        )
        XCTAssertEqual(
            try store.records(for: "ㄨㄛˇ")["我"]?.selectionCount,
            Int64.max
        )
    }

    func testPinCanCreateARecordAndSelectionPreservesIt() throws {
        let (_, store) = try makeStore()
        try store.setPinned(
            true,
            character: "鍵",
            pronunciation: "ㄐㄧㄢˋ"
        )

        var record = try XCTUnwrap(
            store.records(for: "ㄐㄧㄢˋ")["鍵"]
        )
        XCTAssertTrue(record.pinned)
        XCTAssertEqual(record.selectionCount, 0)
        XCTAssertNil(record.lastSelectedAt)

        try store.recordSelection(
            character: "鍵",
            pronunciation: "ㄐㄧㄢˋ",
            at: Date(timeIntervalSince1970: 50)
        )
        record = try XCTUnwrap(store.records(for: "ㄐㄧㄢˋ")["鍵"])
        XCTAssertTrue(record.pinned)
        XCTAssertEqual(record.selectionCount, 1)

        try store.setPinned(
            false,
            character: "鍵",
            pronunciation: "ㄐㄧㄢˋ"
        )
        XCTAssertFalse(
            try XCTUnwrap(store.records(for: "ㄐㄧㄢˋ")["鍵"]).pinned
        )
    }

    func testUnpinningUnknownRecordDoesNotCreateIt() throws {
        let (_, store) = try makeStore()
        try store.setPinned(
            false,
            character: "無",
            pronunciation: "ㄨˊ"
        )
        XCTAssertTrue(try store.records(for: "ㄨˊ").isEmpty)
    }

    func testPersistsAcrossStoreReopen() throws {
        let root = try makeTemporaryDirectory()
        let location = UserDataLocation(applicationSupportRootURL: root)
        do {
            let store = try UserLearningStore(location: location)
            try store.recordSelection(
                character: "我",
                pronunciation: "ㄨㄛˇ",
                at: Date(timeIntervalSince1970: 42)
            )
        }

        let reopened = try UserLearningStore(location: location)
        let record = try XCTUnwrap(reopened.records(for: "ㄨㄛˇ")["我"])
        XCTAssertEqual(record.selectionCount, 1)
        XCTAssertEqual(
            record.lastSelectedAt,
            Date(timeIntervalSince1970: 42)
        )
    }

    func testConcurrentUpdatesAreAtomic() throws {
        let (_, store) = try makeStore()
        let iterations = 400
        let failures = LockedErrors()

        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            do {
                try store.recordSelection(
                    character: "鍵",
                    pronunciation: "ㄐㄧㄢˋ",
                    at: Date(timeIntervalSince1970: TimeInterval(index))
                )
            } catch {
                failures.append(error)
            }
        }

        XCTAssertTrue(failures.values.isEmpty, "\(failures.values)")
        let record = try XCTUnwrap(
            store.records(for: "ㄐㄧㄢˋ")["鍵"]
        )
        XCTAssertEqual(record.selectionCount, Int64(iterations))
        XCTAssertEqual(
            record.lastSelectedAt,
            Date(timeIntervalSince1970: TimeInterval(iterations - 1))
        )
    }

    func testConcurrentConnectionsDoNotLoseUpdates() throws {
        let root = try makeTemporaryDirectory()
        let location = UserDataLocation(applicationSupportRootURL: root)
        let stores = try (0 ..< 8).map { _ in
            try UserLearningStore(location: location)
        }
        let updatesPerStore = 100
        let failures = LockedErrors()

        DispatchQueue.concurrentPerform(iterations: stores.count) { index in
            for offset in 0 ..< updatesPerStore {
                do {
                    try stores[index].recordSelection(
                        character: "鍵",
                        pronunciation: "ㄐㄧㄢˋ",
                        at: Date(
                            timeIntervalSince1970: TimeInterval(
                                index * updatesPerStore + offset
                            )
                        )
                    )
                } catch {
                    failures.append(error)
                }
            }
        }

        XCTAssertTrue(failures.values.isEmpty, "\(failures.values)")
        let record = try XCTUnwrap(
            stores[0].records(for: "ㄐㄧㄢˋ")["鍵"]
        )
        XCTAssertEqual(
            record.selectionCount,
            Int64(stores.count * updatesPerStore)
        )
        XCTAssertEqual(
            record.lastSelectedAt,
            Date(
                timeIntervalSince1970: TimeInterval(
                    stores.count * updatesPerStore - 1
                )
            )
        )
    }

    func testMigratesOwnedEmptyVersionZeroDatabase() throws {
        let root = try makeTemporaryDirectory()
        let location = UserDataLocation(applicationSupportRootURL: root)
        try location.prepareDirectory()
        do {
            let database = try SQLiteDatabase(
                url: location.databaseURL,
                flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
            )
            try database.execute(
                "PRAGMA application_id = \(UserLearningStore.applicationID)"
            )
        }

        _ = try UserLearningStore(location: location)
        let database = try SQLiteDatabase(
            url: location.databaseURL,
            flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        )
        XCTAssertEqual(
            try pragmaInteger("user_version", database: database),
            1
        )
        _ = try database.prepare("SELECT * FROM character_learning LIMIT 0")
    }

    func testRejectsWrongApplicationIDWithoutReplacingIt() throws {
        let root = try makeTemporaryDirectory()
        let location = UserDataLocation(applicationSupportRootURL: root)
        try location.prepareDirectory()
        do {
            let database = try SQLiteDatabase(
                url: location.databaseURL,
                flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
            )
            try database.execute("PRAGMA application_id = 12345")
            try database.execute("PRAGMA user_version = 1")
        }
        let originalData = try Data(contentsOf: location.databaseURL)

        XCTAssertThrowsError(try UserLearningStore(location: location)) { error in
            guard case UserLearningStoreError.invalidApplicationID = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: location.databaseURL), originalData)

        let database = try SQLiteDatabase(
            url: location.databaseURL,
            flags: SQLITE_OPEN_READONLY
        )
        XCTAssertEqual(
            try pragmaInteger("application_id", database: database),
            12345
        )
    }

    func testRejectsFutureSchemaVersion() throws {
        let root = try makeTemporaryDirectory()
        let location = UserDataLocation(applicationSupportRootURL: root)
        try location.prepareDirectory()
        do {
            let database = try SQLiteDatabase(
                url: location.databaseURL,
                flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
            )
            try database.execute(
                "PRAGMA application_id = \(UserLearningStore.applicationID)"
            )
            try database.execute("PRAGMA user_version = 99")
        }
        let originalData = try Data(contentsOf: location.databaseURL)

        XCTAssertThrowsError(try UserLearningStore(location: location)) { error in
            guard case UserLearningStoreError.unsupportedSchema = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: location.databaseURL), originalData)
    }

    func testRejectsMalformedVersionZeroWithoutStampingMigration() throws {
        let root = try makeTemporaryDirectory()
        let location = UserDataLocation(applicationSupportRootURL: root)
        try location.prepareDirectory()
        do {
            let database = try SQLiteDatabase(
                url: location.databaseURL,
                flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
            )
            try database.execute(
                "PRAGMA application_id = \(UserLearningStore.applicationID)"
            )
            try database.execute(
                "CREATE TABLE character_learning (pronunciation TEXT)"
            )
        }

        XCTAssertThrowsError(try UserLearningStore(location: location)) { error in
            guard case UserLearningStoreError.invalidSchema = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        let database = try SQLiteDatabase(
            url: location.databaseURL,
            flags: SQLITE_OPEN_READONLY
        )
        XCTAssertEqual(
            try pragmaInteger("user_version", database: database),
            0
        )
    }

    func testRejectsVersionOneDatabaseMissingRequiredTable() throws {
        let root = try makeTemporaryDirectory()
        let location = UserDataLocation(applicationSupportRootURL: root)
        try location.prepareDirectory()
        do {
            let database = try SQLiteDatabase(
                url: location.databaseURL,
                flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
            )
            try database.execute(
                "PRAGMA application_id = \(UserLearningStore.applicationID)"
            )
            try database.execute("PRAGMA user_version = 1")
        }
        let originalData = try Data(contentsOf: location.databaseURL)

        XCTAssertThrowsError(try UserLearningStore(location: location)) { error in
            guard case UserLearningStoreError.invalidSchema = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: location.databaseURL), originalData)
    }

    func testRejectsDatabaseSymbolicLinkWithoutReadingOrChangingTarget() throws {
        let root = try makeTemporaryDirectory()
        let location = UserDataLocation(applicationSupportRootURL: root)
        try location.prepareDirectory()
        let target = root.appendingPathComponent("target.sqlite")
        let originalData = Data("must remain untouched".utf8)
        XCTAssertTrue(
            FileManager.default.createFile(
                atPath: target.path,
                contents: originalData
            )
        )
        try FileManager.default.createSymbolicLink(
            at: location.databaseURL,
            withDestinationURL: target
        )

        XCTAssertThrowsError(try UserLearningStore(location: location)) { error in
            guard case UserDataLocationError.unsafeDatabaseFile = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: target), originalData)
    }

    func testRejectsNonRegularDatabasePathBeforeSQLiteOpen() throws {
        let root = try makeTemporaryDirectory()
        let location = UserDataLocation(applicationSupportRootURL: root)
        try location.prepareDirectory()
        try FileManager.default.createDirectory(
            at: location.databaseURL,
            withIntermediateDirectories: false
        )

        XCTAssertThrowsError(try UserLearningStore(location: location)) { error in
            guard case UserDataLocationError.unsafeDatabaseFile = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        var isDirectory: ObjCBool = false
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: location.databaseURL.path,
                isDirectory: &isDirectory
            )
        )
        XCTAssertTrue(isDirectory.boolValue)
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

    private func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let number = try XCTUnwrap(
            attributes[.posixPermissions] as? NSNumber
        )
        return number.intValue & 0o777
    }

    private func pragmaInteger(
        _ name: String,
        database: SQLiteDatabase
    ) throws -> Int64 {
        let statement = try database.prepare("PRAGMA \(name)")
        XCTAssertEqual(try statement.step(), .row)
        return statement.integer(at: 0)
    }
}

private final class LockedErrors {
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
