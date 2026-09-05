import Foundation
import SQLite3
import XCTest

/// A pack is a word list handed to another person, so it must carry the words
/// without the sender's statistics, and it must never trust its own contents.
final class PhraseSharePackTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
        try super.tearDownWithError()
    }

    func testPackRoundTripsPhrasesAndRemovals() throws {
        let pack = makePack()

        let (decoded, issues) = try PhraseSharePack.decoded(
            from: try pack.encoded()
        )

        XCTAssertEqual(decoded, pack)
        XCTAssertTrue(issues.isEmpty)
        XCTAssertEqual(decoded.phrases.map(\.phrase), ["久空"])
        XCTAssertEqual(
            decoded.removedBuiltInPhrases.map(\.phrase),
            ["測試"]
        )
    }

    func testPackOmitsCountsTimestampsAndPins() throws {
        let json = try XCTUnwrap(
            String(data: try makePack().encoded(), encoding: .utf8)
        )

        for field in [
            "selectionCount",
            "lastUsedAt",
            "createdAt",
            "suppressedAt",
            "pinned",
        ] {
            XCTAssertFalse(
                json.contains(field),
                "a shared pack must not disclose \(field)"
            )
        }
    }

    func testImportedPhrasesArriveWithNoCountAndNoPin() throws {
        let importedAt = Date(timeIntervalSince1970: 900)

        let archive = makePack().archive(
            importedAt: importedAt,
            includesRemovals: true
        )

        XCTAssertTrue(archive.characters.isEmpty)
        let phrase = try XCTUnwrap(archive.phrases.first)
        XCTAssertEqual(phrase.phrase, "久空")
        XCTAssertEqual(phrase.selectionCount, 0)
        XCTAssertFalse(phrase.pinned)
        XCTAssertNil(phrase.lastUsedAt)
        XCTAssertEqual(phrase.createdAt, 900_000)
        XCTAssertEqual(archive.suppressions.map(\.phrase), ["測試"])
    }

    func testRemovalsCanBeLeftOutOfAnImport() throws {
        let archive = makePack().archive(
            importedAt: Date(timeIntervalSince1970: 900),
            includesRemovals: false
        )

        XCTAssertEqual(archive.phrases.count, 1)
        XCTAssertTrue(archive.suppressions.isEmpty)
    }

    /// A pack arrives from another person, so every row is untrusted input.
    func testUnusableAndDuplicateEntriesAreSkippedAndCounted() throws {
        let data = try JSONSerialization.data(
            withJSONObject: [
                "format": PhraseSharePack.formatIdentifier,
                "version": PhraseSharePack.currentVersion,
                "exportedAt": 0,
                "phrases": [
                    ["phrase": "久空", "readings": ["ㄐㄧㄡˇ", "ㄎㄨㄥ"]],
                    ["phrase": "久空", "readings": ["ㄐㄧㄡˇ", "ㄎㄨㄥ"]],
                    ["phrase": "錯誤", "readings": ["ASCII", "ㄨˋ"]],
                    ["phrase": "短", "readings": ["ㄉㄨㄢˇ"]],
                    [
                        "phrase": "久空",
                        "readings": ["ㄐㄧㄡˇ", "ㄎㄨㄥ"],
                        "unitPattern": "RRR",
                    ],
                ],
                "removedBuiltInPhrases": [
                    ["phrase": "測試", "readings": ["ㄘㄜˋ", "ㄕˋ"]],
                    ["phrase": "", "readings": ["ㄘㄜˋ"]],
                ],
            ]
        )

        let (pack, issues) = try PhraseSharePack.decoded(from: data)

        XCTAssertEqual(pack.phrases.map(\.phrase), ["久空"])
        XCTAssertEqual(issues.skippedPhrases, 4)
        XCTAssertEqual(pack.removedBuiltInPhrases.map(\.phrase), ["測試"])
        XCTAssertEqual(issues.skippedRemovals, 1)
        XCTAssertFalse(issues.isEmpty)
    }

    func testDifferentReadingsOfTheSameTextAreKept() throws {
        let data = try JSONSerialization.data(
            withJSONObject: [
                "format": PhraseSharePack.formatIdentifier,
                "version": PhraseSharePack.currentVersion,
                "exportedAt": 0,
                "phrases": [
                    ["phrase": "行走", "readings": ["ㄒㄧㄥˊ", "ㄗㄡˇ"]],
                    ["phrase": "行走", "readings": ["ㄏㄤˊ", "ㄗㄡˇ"]],
                ],
                "removedBuiltInPhrases": [],
            ]
        )

        let (pack, issues) = try PhraseSharePack.decoded(from: data)

        XCTAssertEqual(pack.phrases.count, 2)
        XCTAssertTrue(issues.isEmpty)
    }

    func testPunctuatedShortcutSurvivesAPack() throws {
        let pack = PhraseSharePack.make(
            phrases: [
                UserPhraseRecord(
                    phraseID: 1,
                    phrase: "嗎？",
                    pronunciationSequence: ["˙ㄇㄚ"],
                    createdAt: Date(timeIntervalSince1970: 1),
                    lastUsedAt: nil,
                    selectionCount: 4,
                    pinned: true
                ),
            ],
            removedBuiltInPhrases: [],
            exportedAt: Date(timeIntervalSince1970: 2)
        )

        let (decoded, issues) = try PhraseSharePack.decoded(
            from: try pack.encoded()
        )

        XCTAssertTrue(issues.isEmpty)
        XCTAssertEqual(decoded.phrases.first?.phrase, "嗎？")
        XCTAssertEqual(decoded.phrases.first?.unitPattern, "RP")
    }

    func testAPersonalBackupIsNamedRatherThanCalledUnreadable() throws {
        let backup = UserDataArchive.make(
            characters: [],
            phrases: [],
            exportedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertThrowsError(
            try PhraseSharePack.decoded(from: try backup.encoded())
        ) { error in
            XCTAssertEqual(
                error as? PhraseSharePackError,
                .personalBackupDocument
            )
        }
    }

    func testForeignFormatFutureVersionAndGarbageAreRefused() throws {
        let foreign = try JSONSerialization.data(
            withJSONObject: [
                "format": "some-other-input-method",
                "version": 1,
                "exportedAt": 0,
                "phrases": [],
                "removedBuiltInPhrases": [],
            ]
        )
        let future = try JSONSerialization.data(
            withJSONObject: [
                "format": PhraseSharePack.formatIdentifier,
                "version": PhraseSharePack.currentVersion + 1,
                "exportedAt": 0,
                "phrases": [],
                "removedBuiltInPhrases": [],
            ]
        )

        XCTAssertThrowsError(try PhraseSharePack.decoded(from: foreign)) { error in
            XCTAssertEqual(
                error as? PhraseSharePackError,
                .unknownFormat("some-other-input-method")
            )
        }
        XCTAssertThrowsError(try PhraseSharePack.decoded(from: future)) { error in
            XCTAssertEqual(
                error as? PhraseSharePackError,
                .unsupportedVersion(PhraseSharePack.currentVersion + 1)
            )
        }
        for data in [Data("not json".utf8), Data()] {
            XCTAssertThrowsError(try PhraseSharePack.decoded(from: data)) { error in
                XCTAssertEqual(
                    error as? PhraseSharePackError,
                    .malformedDocument
                )
            }
        }
    }

    func testSharedListReachesAnotherMacWithoutTouchingItsOwnLearning() throws {
        let sender = try makeStore()
        try sender.addPhrase(
            phrase: "久空",
            pronunciationSequence: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"],
            createdAt: Date(timeIntervalSince1970: 10)
        )
        try sender.recordPhraseSelection(
            phrase: "久空",
            pronunciationSequence: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"],
            at: Date(timeIntervalSince1970: 20)
        )
        try sender.suppressPhrase(
            phrase: "測試",
            pronunciationSequence: ["ㄘㄜˋ", "ㄕˋ"],
            at: Date(timeIntervalSince1970: 30)
        )
        let pack = PhraseSharePack.make(
            phrases: try sender.allPhraseRecords(),
            removedBuiltInPhrases: try sender.allSuppressedPhrases(),
            exportedAt: Date(timeIntervalSince1970: 40)
        )

        let recipient = try makeStore()
        try recipient.addPhrase(
            phrase: "久空",
            pronunciationSequence: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"],
            createdAt: Date(timeIntervalSince1970: 1)
        )
        for _ in 0 ..< 5 {
            try recipient.recordPhraseSelection(
                phrase: "久空",
                pronunciationSequence: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"],
                at: Date(timeIntervalSince1970: 2)
            )
        }
        try recipient.setPhrasePinned(
            true,
            phrase: "久空",
            pronunciationSequence: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"]
        )

        let (decoded, _) = try PhraseSharePack.decoded(from: try pack.encoded())
        let summary = try recipient.merge(
            decoded.archive(
                importedAt: Date(timeIntervalSince1970: 500),
                includesRemovals: true
            )
        )

        XCTAssertEqual(summary.mergedPhrases, 1)
        XCTAssertEqual(summary.mergedSuppressions, 1)
        let received = try XCTUnwrap(recipient.allPhraseRecords().first)
        XCTAssertEqual(received.phrase, "久空")
        // The sender's list never lowers a count or clears a pin the recipient
        // set for themselves.
        XCTAssertEqual(received.selectionCount, 5)
        XCTAssertTrue(received.pinned)
        XCTAssertEqual(
            try recipient.allSuppressedPhrases().map(\.phrase),
            ["測試"]
        )
    }

    func testImportingTheSamePackTwiceChangesNothingTheSecondTime() throws {
        let recipient = try makeStore()
        let archive = makePack().archive(
            importedAt: Date(timeIntervalSince1970: 500),
            includesRemovals: true
        )

        try recipient.merge(archive)
        let afterFirst = try recipient.allPhraseRecords()
        try recipient.merge(archive)

        XCTAssertEqual(try recipient.allPhraseRecords(), afterFirst)
        XCTAssertEqual(try recipient.allSuppressedPhrases().count, 1)
    }

    private func makeStore() throws -> UserLearningStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false
        )
        temporaryDirectories.append(root)
        return try UserLearningStore(
            location: UserDataLocation(applicationSupportRootURL: root)
        )
    }

    private func makePack() -> PhraseSharePack {
        PhraseSharePack.make(
            phrases: [
                UserPhraseRecord(
                    phraseID: 7,
                    phrase: "久空",
                    pronunciationSequence: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"],
                    createdAt: Date(timeIntervalSince1970: 100),
                    lastUsedAt: Date(timeIntervalSince1970: 200),
                    selectionCount: 12,
                    pinned: true
                ),
            ],
            removedBuiltInPhrases: [
                SuppressedPhraseRecord(
                    phrase: "測試",
                    pronunciationSequence: ["ㄘㄜˋ", "ㄕˋ"],
                    suppressedAt: Date(timeIntervalSince1970: 300)
                ),
            ],
            exportedAt: Date(timeIntervalSince1970: 400)
        )
    }
}
