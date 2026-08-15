import Foundation
import SQLite3
import XCTest

final class CharacterDictionaryTests: XCTestCase {
    func testWoThirdToneHasWoAsItsFirstCandidate() throws {
        let dictionary = try makeDictionary()
        let candidates = try dictionary.candidates(for: "ㄨㄛˇ")

        XCTAssertEqual(candidates.first, "我")
        XCTAssertEqual(candidates.count, 34)
    }

    func testCandidateEntriesExposeSourceOrderWithoutChangingStringAPI() throws {
        let dictionary = try makeDictionary()
        let entries = try dictionary.candidateEntries(for: "ㄨㄛˇ")

        XCTAssertEqual(
            entries.prefix(3),
            [
                DictionaryCharacter(text: "我", sourceOrder: 827),
                DictionaryCharacter(text: "倭", sourceOrder: 2_092),
                DictionaryCharacter(text: "婑", sourceOrder: 9_357),
            ]
        )
        XCTAssertEqual(
            entries.map(\.text),
            try dictionary.candidates(for: "ㄨㄛˇ")
        )
    }

    func testJianFourthToneContainsCommonHomophones() throws {
        let candidates = Set(
            try makeDictionary().candidates(for: "ㄐㄧㄢˋ")
        )

        for expected in ["件", "見", "建", "健", "薦", "鍵"] {
            XCTAssertTrue(candidates.contains(expected), "Missing \(expected)")
        }
    }

    func testReverseLookupPreservesMultiplePronunciations() throws {
        let dictionary = try makeDictionary()

        XCTAssertEqual(
            try dictionary.pronunciations(for: "行"),
            ["ㄏㄤˊ", "ㄏㄤˋ", "ㄒㄧㄥˊ", "ㄒㄧㄥˋ"]
        )
        XCTAssertEqual(
            try dictionary.pronunciations(for: "樂"),
            ["ㄌㄜˋ", "ㄌㄠˋ", "ㄧㄠˋ", "ㄩㄝˋ"]
        )
    }

    func testUnknownQueriesReturnNoResults() throws {
        let dictionary = try makeDictionary()

        XCTAssertEqual(try dictionary.candidates(for: "not-zhuyin"), [])
        XCTAssertEqual(try dictionary.pronunciations(for: "不存在的詞"), [])
    }

    func testBundledArtifactHasPinnedMetadataAndPassesQuickCheck() throws {
        let dictionary = try makeDictionary()

        XCTAssertEqual(try dictionary.metadataValue(for: "source_version"), "20260805")
        XCTAssertEqual(try dictionary.metadataValue(for: "dictionary_entries"), "94708")
        XCTAssertEqual(try dictionary.metadataValue(for: "unique_characters"), "76373")
        XCTAssertEqual(
            try dictionary.metadataValue(for: "sha256_Properties.zip"),
            "3d56ef14cc8099893245dac58fe4718d2fa64812b9159352a98a4588ad3efa5c"
        )

        let database = try SQLiteDatabase(
            url: databaseURL,
            flags: SQLITE_OPEN_READONLY
        )
        let statement = try database.prepare("PRAGMA quick_check")
        XCTAssertEqual(try statement.step(), .row)
        XCTAssertEqual(try statement.text(at: 0), "ok")
    }

    func testRejectsSQLiteFileWithWrongApplicationID() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let invalidURL = temporaryDirectory.appendingPathComponent("wrong.sqlite3")
        do {
            let database = try SQLiteDatabase(
                url: invalidURL,
                flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
            )
            try database.execute("PRAGMA application_id = 1")
            try database.execute("PRAGMA user_version = 1")
        }

        XCTAssertThrowsError(try CharacterDictionary(databaseURL: invalidURL)) { error in
            guard case CharacterDictionaryError.invalidApplicationID = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testRejectsDatabaseWithCorrectIdentityButMissingSchema() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let invalidURL = temporaryDirectory.appendingPathComponent("missing.sqlite3")
        do {
            let database = try SQLiteDatabase(
                url: invalidURL,
                flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
            )
            try database.execute(
                "PRAGMA application_id = \(CharacterDictionary.applicationID)"
            )
            try database.execute(
                "PRAGMA user_version = \(CharacterDictionary.schemaVersion)"
            )
        }

        XCTAssertThrowsError(try CharacterDictionary(databaseURL: invalidURL)) { error in
            guard case CharacterDictionaryError.invalidSchema = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testSQLiteTextRoundTripsEmbeddedNull() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let database = try SQLiteDatabase(
            url: temporaryDirectory.appendingPathComponent("text.sqlite3"),
            flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        )
        try database.execute("CREATE TABLE values_table (value TEXT NOT NULL)")
        let insert = try database.prepare("INSERT INTO values_table VALUES (?)")
        try insert.bind("before\0after", at: 1)
        XCTAssertEqual(try insert.step(), .done)

        let select = try database.prepare("SELECT value FROM values_table")
        XCTAssertEqual(try select.step(), .row)
        XCTAssertEqual(try select.text(at: 0), "before\0after")
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

    private func makeDictionary() throws -> CharacterDictionary {
        try CharacterDictionary(databaseURL: databaseURL)
    }
}
