import Foundation
import SQLite3
import XCTest

/// Removing a built-in phrase has to survive an app update, so the tombstone
/// lives in the user's own database rather than in the bundled dictionary.
final class SuppressedPhraseStoreTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
        try super.tearDownWithError()
    }

    func testSuppressingAPhraseRecordsItForItsExactReadingSequence() throws {
        let (_, store) = try makeStore()

        try store.suppressPhrase(
            phrase: "測試",
            pronunciationSequence: ["ㄘㄜˋ", "ㄕˋ"],
            at: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(
            try store.suppressedPhrases(for: ["ㄘㄜˋ", "ㄕˋ"]),
            ["測試"]
        )
        XCTAssertEqual(
            try store.suppressedPhrases(for: ["ㄘㄜˋ", "ㄕ"]),
            []
        )
        XCTAssertEqual(
            try store.allSuppressedPhrases(),
            [
                SuppressedPhraseRecord(
                    phrase: "測試",
                    pronunciationSequence: ["ㄘㄜˋ", "ㄕˋ"],
                    suppressedAt: Date(timeIntervalSince1970: 100)
                ),
            ]
        )
    }

    func testSuppressingTwiceKeepsTheEarliestTimeAndOneRow() throws {
        let (_, store) = try makeStore()

        try store.suppressPhrase(
            phrase: "測試",
            pronunciationSequence: ["ㄘㄜˋ", "ㄕˋ"],
            at: Date(timeIntervalSince1970: 100)
        )
        try store.suppressPhrase(
            phrase: "測試",
            pronunciationSequence: ["ㄘㄜˋ", "ㄕˋ"],
            at: Date(timeIntervalSince1970: 900)
        )

        XCTAssertEqual(
            try store.allSuppressedPhrases().map(\.suppressedAt),
            [Date(timeIntervalSince1970: 100)]
        )
    }

    func testRestoringRemovesOnlyTheNamedIdentity() throws {
        let (_, store) = try makeStore()
        try store.suppressPhrase(
            phrase: "測試",
            pronunciationSequence: ["ㄘㄜˋ", "ㄕˋ"],
            at: Date(timeIntervalSince1970: 100)
        )
        try store.suppressPhrase(
            phrase: "測試中",
            pronunciationSequence: ["ㄘㄜˋ", "ㄕˋ", "ㄓㄨㄥ"],
            at: Date(timeIntervalSince1970: 200)
        )

        try store.restorePhrase(
            phrase: "測試",
            pronunciationSequence: ["ㄘㄜˋ", "ㄕˋ"]
        )

        XCTAssertEqual(
            try store.allSuppressedPhrases().map(\.phrase),
            ["測試中"]
        )
    }

    func testRestoringAPhraseThatWasNeverRemovedChangesNothing() throws {
        let (_, store) = try makeStore()

        try store.restorePhrase(
            phrase: "測試",
            pronunciationSequence: ["ㄘㄜˋ", "ㄕˋ"]
        )

        XCTAssertEqual(try store.allSuppressedPhrases(), [])
    }

    func testSuppressionRejectsAnIdentityThatCouldNotHaveBeenACandidate() throws {
        let (_, store) = try makeStore()

        XCTAssertThrowsError(
            try store.suppressPhrase(
                phrase: "測試",
                pronunciationSequence: ["ASCII", "ㄕˋ"],
                at: Date(timeIntervalSince1970: 100)
            )
        )
        XCTAssertEqual(try store.allSuppressedPhrases(), [])
    }

    func testPunctuatedShortcutIdentityRoundTrips() throws {
        let (_, store) = try makeStore()

        try store.suppressPhrase(
            phrase: "嗎？",
            pronunciationSequence: ["˙ㄇㄚ"],
            at: Date(timeIntervalSince1970: 100)
        )

        let record = try XCTUnwrap(try store.allSuppressedPhrases().first)
        XCTAssertEqual(record.phrase, "嗎？")
        XCTAssertEqual(record.pronunciationSequence, ["˙ㄇㄚ"])
        XCTAssertEqual(record.outputPattern.rawValue, "RP")
    }

    func testClearingUserPhrasesKeepsRemovedBuiltInPhrases() throws {
        let (_, store) = try makeStore()
        try store.addPhrase(
            phrase: "久空",
            pronunciationSequence: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"],
            createdAt: Date(timeIntervalSince1970: 10)
        )
        try store.suppressPhrase(
            phrase: "測試",
            pronunciationSequence: ["ㄘㄜˋ", "ㄕˋ"],
            at: Date(timeIntervalSince1970: 100)
        )

        try store.clearUserPhrases()

        XCTAssertEqual(try store.allPhraseRecords(), [])
        XCTAssertEqual(
            try store.allSuppressedPhrases().map(\.phrase),
            ["測試"]
        )
    }

    func testClearingAllUserDataRestoresEveryRemovedBuiltInPhrase() throws {
        let (_, store) = try makeStore()
        try store.suppressPhrase(
            phrase: "測試",
            pronunciationSequence: ["ㄘㄜˋ", "ㄕˋ"],
            at: Date(timeIntervalSince1970: 100)
        )

        try store.clearAllUserData()

        XCTAssertEqual(try store.allSuppressedPhrases(), [])
    }

    func testClearingOnlySuppressionsKeepsCharactersAndUserPhrases() throws {
        let (_, store) = try makeStore()
        try store.recordSelection(
            character: "鍵",
            pronunciation: "ㄐㄧㄢˋ",
            at: Date(timeIntervalSince1970: 5)
        )
        try store.addPhrase(
            phrase: "久空",
            pronunciationSequence: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"],
            createdAt: Date(timeIntervalSince1970: 10)
        )
        try store.suppressPhrase(
            phrase: "測試",
            pronunciationSequence: ["ㄘㄜˋ", "ㄕˋ"],
            at: Date(timeIntervalSince1970: 100)
        )

        try store.clearSuppressedPhrases()

        XCTAssertEqual(try store.allSuppressedPhrases(), [])
        XCTAssertEqual(try store.allCharacterRecords().count, 1)
        XCTAssertEqual(try store.allPhraseRecords().map(\.phrase), ["久空"])
    }

    func testMigratingFromVersionThreeAddsTheTableAndKeepsLearningData() throws {
        let root = try makeTemporaryDirectory()
        let location = UserDataLocation(applicationSupportRootURL: root)
        do {
            let store = try UserLearningStore(location: location)
            try store.recordSelection(
                character: "鍵",
                pronunciation: "ㄐㄧㄢˋ",
                at: Date(timeIntervalSince1970: 5)
            )
            try store.addPhrase(
                phrase: "久空",
                pronunciationSequence: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"],
                createdAt: Date(timeIntervalSince1970: 10)
            )
        }
        do {
            // Roll the file back to exactly what version 3 shipped.
            let database = try SQLiteDatabase(
                url: location.databaseURL,
                flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
            )
            try database.execute("DROP TABLE suppressed_phrases")
            try database.execute("PRAGMA user_version = 3")
        }

        let store = try UserLearningStore(location: location)

        XCTAssertEqual(try store.allSuppressedPhrases(), [])
        XCTAssertEqual(try store.allCharacterRecords().map(\.character), ["鍵"])
        XCTAssertEqual(try store.allPhraseRecords().map(\.phrase), ["久空"])
        try store.suppressPhrase(
            phrase: "測試",
            pronunciationSequence: ["ㄘㄜˋ", "ㄕˋ"],
            at: Date(timeIntervalSince1970: 100)
        )
        XCTAssertEqual(
            try store.allSuppressedPhrases().map(\.phrase),
            ["測試"]
        )
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
}
