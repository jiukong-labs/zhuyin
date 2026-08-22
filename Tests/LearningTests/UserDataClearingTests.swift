import Foundation
import SQLite3
import XCTest

final class UserDataClearingTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
        try super.tearDownWithError()
    }

    func testClearingCharactersKeepsUserPhrases() throws {
        let (_, store) = try makePopulatedStore()

        try store.clearCharacterLearning()

        XCTAssertEqual(try store.records(for: "ㄐㄧㄢˋ"), [:])
        XCTAssertEqual(
            try store.phraseRecords(for: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"]).map(\.phrase),
            ["久空"]
        )
    }

    func testClearingPhrasesRemovesOrderedReadingsAndKeepsCharacters() throws {
        let (location, store) = try makePopulatedStore()

        try store.clearUserPhrases()

        XCTAssertEqual(try store.phraseRecords(for: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"]), [])
        XCTAssertEqual(try store.records(for: "ㄐㄧㄢˋ").count, 1)

        let database = try openDatabase(at: location.databaseURL)
        XCTAssertEqual(try rowCount("user_phrases", database: database), 0)
        XCTAssertEqual(
            try rowCount("user_phrase_readings", database: database),
            0
        )
    }

    func testClearingEverythingEmptiesBothDataSets() throws {
        let (location, store) = try makePopulatedStore()

        try store.clearAllUserData()

        XCTAssertEqual(try store.records(for: "ㄐㄧㄢˋ"), [:])
        XCTAssertEqual(try store.phraseRecords(for: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"]), [])

        let database = try openDatabase(at: location.databaseURL)
        XCTAssertEqual(
            try rowCount("character_learning", database: database),
            0
        )
        XCTAssertEqual(try rowCount("user_phrases", database: database), 0)
    }

    func testClearingKeepsTheSchemaUsableWithoutReopening() throws {
        let (location, store) = try makePopulatedStore()

        try store.clearAllUserData()
        try store.recordSelection(
            character: "鍵",
            pronunciation: "ㄐㄧㄢˋ",
            at: Date(timeIntervalSince1970: 5_000)
        )
        try store.addPhrase(
            phrase: "久空",
            pronunciationSequence: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"],
            createdAt: Date(timeIntervalSince1970: 5_000)
        )

        XCTAssertEqual(
            try store.records(for: "ㄐㄧㄢˋ")["鍵"]?.selectionCount,
            1
        )
        XCTAssertEqual(
            try store.phraseRecords(for: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"])
                .map(\.selectionCount),
            [0]
        )

        let database = try openDatabase(at: location.databaseURL)
        XCTAssertEqual(try pragma("user_version", database: database), 2)
        XCTAssertEqual(
            try pragma("application_id", database: database),
            UserLearningStore.applicationID
        )
        XCTAssertEqual(
            try userTables(database: database),
            ["character_learning", "user_phrase_readings", "user_phrases"]
        )
    }

    func testClearingResetsRankingToTheBaseDictionaryOrder() throws {
        let (_, store) = try makePopulatedStore()
        let service = UserLearningService(store: store)
        let dictionary = try CharacterDictionary(databaseURL: databaseURL)
        let provider = CharacterCandidateProvider(
            dictionary: dictionary,
            learning: service
        )

        XCTAssertEqual(
            try provider.candidates(for: "ㄐㄧㄢˋ").first?.text,
            "鍵"
        )
        XCTAssertTrue(service.clearAllUserData())

        XCTAssertEqual(
            try provider.candidates(for: "ㄐㄧㄢˋ").map(\.text),
            try dictionary.candidateEntries(for: "ㄐㄧㄢˋ")
                .filter(\.isInGeneralCandidateRepertoire)
                .map(\.text)
        )
    }

    func testServiceReportsFailureWithoutStorage() {
        let service = UserLearningService(store: nil)

        XCTAssertFalse(service.clearCharacterLearning())
        XCTAssertFalse(service.clearUserPhrases())
        XCTAssertFalse(service.clearAllUserData())
    }

    private func makePopulatedStore() throws -> (
        UserDataLocation,
        UserLearningStore
    ) {
        let root = try makeTemporaryDirectory()
        let location = UserDataLocation(applicationSupportRootURL: root)
        let store = try UserLearningStore(location: location)
        let date = Date(timeIntervalSince1970: 1_000)

        for _ in 0 ..< 6 {
            try store.recordSelection(
                character: "鍵",
                pronunciation: "ㄐㄧㄢˋ",
                at: date
            )
        }
        try store.addPhrase(
            phrase: "久空",
            pronunciationSequence: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"],
            createdAt: date
        )
        return (location, store)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var databaseURL: URL {
        repositoryRoot
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("Dictionary", isDirectory: true)
            .appendingPathComponent("JiukongZhuyin.sqlite3")
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

    private func rowCount(
        _ table: String,
        database: SQLiteDatabase
    ) throws -> Int64 {
        let statement = try database.prepare("SELECT count(*) FROM \(table)")
        XCTAssertEqual(try statement.step(), .row)
        return statement.integer(at: 0)
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
