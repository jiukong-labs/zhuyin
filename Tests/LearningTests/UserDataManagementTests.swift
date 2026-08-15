import Foundation
import SQLite3
import XCTest

final class UserDataManagementTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
        try super.tearDownWithError()
    }

    func testListingOrdersPinnedThenMostUsedThenMostRecent() throws {
        let store = try makeStore()
        try store.recordSelection(
            character: "件",
            pronunciation: "ㄐㄧㄢˋ",
            at: Date(timeIntervalSince1970: 300)
        )
        for _ in 0 ..< 3 {
            try store.recordSelection(
                character: "鍵",
                pronunciation: "ㄐㄧㄢˋ",
                at: Date(timeIntervalSince1970: 100)
            )
        }
        try store.setPinned(true, character: "見", pronunciation: "ㄐㄧㄢˋ")

        XCTAssertEqual(
            try store.allCharacterRecords().map(\.character),
            ["見", "鍵", "件"]
        )
    }

    func testListingReturnsEveryPhraseWithItsOrderedReadings() throws {
        let store = try makeStore()
        try store.addPhrase(
            phrase: "久空",
            pronunciationSequence: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"],
            createdAt: Date(timeIntervalSince1970: 100)
        )
        try store.addPhrase(
            phrase: "輸入法",
            pronunciationSequence: ["ㄕㄨ", "ㄖㄨˋ", "ㄈㄚˇ"],
            createdAt: Date(timeIntervalSince1970: 200)
        )
        try store.setPhrasePinned(
            true,
            phrase: "輸入法",
            pronunciationSequence: ["ㄕㄨ", "ㄖㄨˋ", "ㄈㄚˇ"]
        )

        let records = try store.allPhraseRecords()

        XCTAssertEqual(records.map(\.phrase), ["輸入法", "久空"])
        XCTAssertEqual(
            records.first?.pronunciationSequence,
            ["ㄕㄨ", "ㄖㄨˋ", "ㄈㄚˇ"]
        )
        XCTAssertEqual(records.last?.pronunciationSequence, ["ㄐㄧㄡˇ", "ㄎㄨㄥ"])
    }

    func testDeletingOneCharacterKeepsTheOtherReadingOfTheSameText() throws {
        let store = try makeStore()
        try store.recordSelection(character: "行", pronunciation: "ㄒㄧㄥˊ")
        try store.recordSelection(character: "行", pronunciation: "ㄏㄤˊ")

        try store.deleteCharacterRecord(
            character: "行",
            pronunciation: "ㄒㄧㄥˊ"
        )

        XCTAssertEqual(try store.records(for: "ㄒㄧㄥˊ"), [:])
        XCTAssertEqual(try store.records(for: "ㄏㄤˊ").count, 1)
    }

    func testDeletingAnAbsentEntryIsNotAnError() throws {
        let store = try makeStore()

        try store.deleteCharacterRecord(character: "鍵", pronunciation: "ㄐㄧㄢˋ")
        try store.deletePhrase(
            phrase: "久空",
            pronunciationSequence: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"]
        )

        XCTAssertEqual(try store.allCharacterRecords(), [])
        XCTAssertEqual(try store.allPhraseRecords(), [])
    }

    func testDeletingAPhraseRemovesItsOrderedReadings() throws {
        let location = try makeLocation()
        let store = try UserLearningStore(location: location)
        try store.addPhrase(
            phrase: "久空",
            pronunciationSequence: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"],
            createdAt: Date(timeIntervalSince1970: 1)
        )
        try store.addPhrase(
            phrase: "輸入法",
            pronunciationSequence: ["ㄕㄨ", "ㄖㄨˋ", "ㄈㄚˇ"],
            createdAt: Date(timeIntervalSince1970: 1)
        )

        try store.deletePhrase(
            phrase: "久空",
            pronunciationSequence: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"]
        )

        XCTAssertEqual(try store.allPhraseRecords().map(\.phrase), ["輸入法"])
        let database = try openDatabase(at: location.databaseURL)
        XCTAssertEqual(
            try rowCount("user_phrase_readings", database: database),
            3
        )
    }

    func testMergeAddsNewEntriesWithTheirImportedMetadata() throws {
        let store = try makeStore()
        let archive = UserDataArchive(
            exportedAt: 0,
            characters: [
                ArchivedCharacter(
                    character: "鍵",
                    pronunciation: "ㄐㄧㄢˋ",
                    selectionCount: 5,
                    lastSelectedAt: 9_000,
                    pinned: true
                ),
            ],
            phrases: [
                ArchivedPhrase(
                    phrase: "久空",
                    readings: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"],
                    selectionCount: 4,
                    createdAt: 1_000,
                    lastUsedAt: 8_000,
                    pinned: true
                ),
            ]
        )

        let summary = try store.merge(archive)

        XCTAssertEqual(summary, UserDataMergeSummary(
            mergedCharacters: 1,
            mergedPhrases: 1
        ))
        let character = try XCTUnwrap(try store.records(for: "ㄐㄧㄢˋ")["鍵"])
        XCTAssertEqual(character.selectionCount, 5)
        XCTAssertEqual(character.lastSelectedAt?.timeIntervalSince1970, 9)
        XCTAssertTrue(character.pinned)

        let phrase = try XCTUnwrap(try store.allPhraseRecords().first)
        XCTAssertEqual(phrase.pronunciationSequence, ["ㄐㄧㄡˇ", "ㄎㄨㄥ"])
        XCTAssertEqual(phrase.selectionCount, 4)
        XCTAssertEqual(phrase.createdAt.timeIntervalSince1970, 1)
        XCTAssertEqual(phrase.lastUsedAt?.timeIntervalSince1970, 8)
        XCTAssertTrue(phrase.pinned)
    }

    func testMergeKeepsTheLargerCountNewestTimeAndCombinedPin() throws {
        let store = try makeStore()
        for _ in 0 ..< 7 {
            try store.recordSelection(
                character: "鍵",
                pronunciation: "ㄐㄧㄢˋ",
                at: Date(timeIntervalSince1970: 500)
            )
        }
        try store.setPinned(true, character: "鍵", pronunciation: "ㄐㄧㄢˋ")
        try store.addPhrase(
            phrase: "久空",
            pronunciationSequence: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"],
            createdAt: Date(timeIntervalSince1970: 500)
        )
        try store.recordPhraseSelection(
            phrase: "久空",
            pronunciationSequence: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"],
            at: Date(timeIntervalSince1970: 900)
        )

        try store.merge(
            UserDataArchive(
                exportedAt: 0,
                characters: [
                    ArchivedCharacter(
                        character: "鍵",
                        pronunciation: "ㄐㄧㄢˋ",
                        selectionCount: 2,
                        lastSelectedAt: 900_000,
                        pinned: false
                    ),
                ],
                phrases: [
                    ArchivedPhrase(
                        phrase: "久空",
                        readings: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"],
                        selectionCount: 99,
                        createdAt: 1_000,
                        lastUsedAt: 2_000,
                        pinned: false
                    ),
                ]
            )
        )

        let character = try XCTUnwrap(try store.records(for: "ㄐㄧㄢˋ")["鍵"])
        // The import is newer for the character and older for the phrase, so
        // both directions of the newest-timestamp rule are covered here.
        XCTAssertEqual(character.selectionCount, 7)
        XCTAssertEqual(character.lastSelectedAt?.timeIntervalSince1970, 900)
        XCTAssertTrue(character.pinned)

        let phrase = try XCTUnwrap(try store.allPhraseRecords().first)
        XCTAssertEqual(phrase.selectionCount, 99)
        XCTAssertEqual(phrase.createdAt.timeIntervalSince1970, 1)
        XCTAssertEqual(phrase.lastUsedAt?.timeIntervalSince1970, 900)
    }

    func testImportingTheSameArchiveTwiceChangesNothing() throws {
        let store = try makeStore()
        try store.recordSelection(
            character: "鍵",
            pronunciation: "ㄐㄧㄢˋ",
            at: Date(timeIntervalSince1970: 10)
        )
        try store.addPhrase(
            phrase: "久空",
            pronunciationSequence: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"],
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let archive = UserDataArchive.make(
            characters: try store.allCharacterRecords(),
            phrases: try store.allPhraseRecords(),
            exportedAt: Date(timeIntervalSince1970: 20)
        )

        try store.merge(archive)
        let afterFirst = (
            try store.allCharacterRecords(),
            try store.allPhraseRecords()
        )
        try store.merge(archive)

        XCTAssertEqual(try store.allCharacterRecords(), afterFirst.0)
        XCTAssertEqual(try store.allPhraseRecords(), afterFirst.1)
        XCTAssertEqual(afterFirst.0.first?.selectionCount, 1)
    }

    func testExportThenImportReproducesTheDataOnAnotherDatabase() throws {
        let source = try makeStore()
        try source.recordSelection(
            character: "鍵",
            pronunciation: "ㄐㄧㄢˋ",
            at: Date(timeIntervalSince1970: 10)
        )
        try source.setPinned(true, character: "見", pronunciation: "ㄐㄧㄢˋ")
        try source.addPhrase(
            phrase: "久空",
            pronunciationSequence: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"],
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let archive = UserDataArchive.make(
            characters: try source.allCharacterRecords(),
            phrases: try source.allPhraseRecords(),
            exportedAt: Date(timeIntervalSince1970: 20)
        )

        let destination = try makeStore()
        let (decoded, issues) = try UserDataArchive.decoded(
            from: try archive.encoded()
        )
        try destination.merge(decoded)

        XCTAssertTrue(issues.isEmpty)
        XCTAssertEqual(
            try destination.allCharacterRecords(),
            try source.allCharacterRecords()
        )
        XCTAssertEqual(
            try destination.allPhraseRecords().map(\.phrase),
            try source.allPhraseRecords().map(\.phrase)
        )
        XCTAssertEqual(
            try destination.allPhraseRecords().map(\.pronunciationSequence),
            try source.allPhraseRecords().map(\.pronunciationSequence)
        )
    }

    func testMergeRollsBackCompletelyWhenAnEntryCannotBeApplied() throws {
        let store = try makeStore()
        try store.recordSelection(
            character: "鍵",
            pronunciation: "ㄐㄧㄢˋ",
            at: Date(timeIntervalSince1970: 10)
        )
        try store.addPhrase(
            phrase: "久空",
            pronunciationSequence: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"],
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let before = (
            try store.allCharacterRecords(),
            try store.allPhraseRecords()
        )

        XCTAssertThrowsError(
            try store.merge(
                UserDataArchive(
                    exportedAt: 0,
                    characters: [
                        ArchivedCharacter(
                            character: "件",
                            pronunciation: "ㄐㄧㄢˋ",
                            selectionCount: 3,
                            lastSelectedAt: nil,
                            pinned: false
                        ),
                    ],
                    phrases: [
                        ArchivedPhrase(
                            phrase: "久空",
                            readings: ["ㄐㄧㄡˇ"],
                            selectionCount: 1,
                            createdAt: 1,
                            lastUsedAt: nil,
                            pinned: false
                        ),
                    ]
                )
            )
        )

        XCTAssertEqual(try store.allCharacterRecords(), before.0)
        XCTAssertEqual(try store.allPhraseRecords(), before.1)
    }

    func testImportedPhraseIsImmediatelyOfferedAsACandidate() throws {
        let store = try makeStore()
        let service = UserLearningService(store: store)
        let provider = CharacterCandidateProvider(
            dictionary: try CharacterDictionary(databaseURL: databaseURL),
            learning: service
        )
        var buffer = CompositionBuffer()
        buffer.append(text: "久", pronunciation: "ㄐㄧㄡˇ")

        XCTAssertNotNil(
            service.merge(
                UserDataArchive(
                    exportedAt: 0,
                    characters: [],
                    phrases: [
                        ArchivedPhrase(
                            phrase: "久空",
                            readings: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"],
                            selectionCount: 0,
                            createdAt: 1,
                            lastUsedAt: nil,
                            pinned: false
                        ),
                    ]
                )
            )
        )

        let candidates = try provider.candidates(
            for: "ㄎㄨㄥ",
            phraseQueries: buffer.phraseLookupQueries(appending: "ㄎㄨㄥ")
        )

        XCTAssertEqual(candidates.first?.text, "久空")
        XCTAssertEqual(candidates.first?.type, .phrase)
    }

    func testServiceReportsMissingStorageForEveryManagementOperation() {
        let service = UserLearningService(store: nil)

        XCTAssertEqual(service.allCharacterRecords(), [])
        XCTAssertEqual(service.allPhraseRecords(), [])
        XCTAssertFalse(
            service.deleteCharacterRecord(character: "鍵", pronunciation: "ㄐㄧㄢˋ")
        )
        XCTAssertFalse(
            service.deletePhrase(
                phrase: "久空",
                pronunciationSequence: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"]
            )
        )
        XCTAssertNil(service.exportArchive(at: Date(timeIntervalSince1970: 0)))
        XCTAssertNil(
            service.merge(
                UserDataArchive(exportedAt: 0, characters: [], phrases: [])
            )
        )
    }

    func testExportReadsBothDataSetsThroughTheService() throws {
        let store = try makeStore()
        try store.recordSelection(
            character: "鍵",
            pronunciation: "ㄐㄧㄢˋ",
            at: Date(timeIntervalSince1970: 10)
        )
        try store.addPhrase(
            phrase: "久空",
            pronunciationSequence: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"],
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let service = UserLearningService(store: store)

        let archive = try XCTUnwrap(
            service.exportArchive(at: Date(timeIntervalSince1970: 30))
        )

        XCTAssertEqual(archive.exportedAt, 30_000)
        XCTAssertEqual(archive.characters.map(\.character), ["鍵"])
        XCTAssertEqual(archive.phrases.map(\.phrase), ["久空"])
    }

    private func makeStore() throws -> UserLearningStore {
        try UserLearningStore(location: try makeLocation())
    }

    private func makeLocation() throws -> UserDataLocation {
        UserDataLocation(
            applicationSupportRootURL: try makeTemporaryDirectory()
        )
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
}
