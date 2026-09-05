import Foundation
import XCTest

final class UserDataArchiveTests: XCTestCase {
    func testArchiveRoundTripsEveryFieldWithoutLoss() throws {
        let archive = UserDataArchive.make(
            characters: [
                CharacterLearningRecord(
                    character: "鍵",
                    pronunciation: "ㄐㄧㄢˋ",
                    selectionCount: 6,
                    lastSelectedAt: Date(timeIntervalSince1970: 1_700.5),
                    pinned: true
                ),
            ],
            phrases: [
                UserPhraseRecord(
                    phraseID: 3,
                    phrase: "久空",
                    pronunciationSequence: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"],
                    createdAt: Date(timeIntervalSince1970: 100),
                    lastUsedAt: nil,
                    selectionCount: 2,
                    pinned: false
                ),
            ],
            exportedAt: Date(timeIntervalSince1970: 2_000)
        )

        let (decoded, issues) = try UserDataArchive.decoded(
            from: try archive.encoded()
        )

        XCTAssertEqual(decoded, archive)
        XCTAssertTrue(issues.isEmpty)
        XCTAssertEqual(decoded.characters.first?.lastSelectedAt, 1_700_500)
        XCTAssertEqual(decoded.phrases.first?.createdAt, 100_000)
        XCTAssertNil(decoded.phrases.first?.lastUsedAt)
        XCTAssertEqual(decoded.exportedAt, 2_000_000)
    }

    func testExportOmitsTheLocalPhraseIdentifier() throws {
        let archive = UserDataArchive.make(
            characters: [],
            phrases: [
                UserPhraseRecord(
                    phraseID: 42,
                    phrase: "久空",
                    pronunciationSequence: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"],
                    createdAt: Date(timeIntervalSince1970: 1),
                    lastUsedAt: nil,
                    selectionCount: 0,
                    pinned: false
                ),
            ],
            exportedAt: Date(timeIntervalSince1970: 1)
        )

        let json = try XCTUnwrap(
            String(data: try archive.encoded(), encoding: .utf8)
        )

        XCTAssertFalse(json.contains("phraseID"))
        XCTAssertFalse(json.contains("42"))
        XCTAssertTrue(json.contains("\"format\" : \"jiukong-zhuyin-user-data\""))
    }

    func testForeignFormatAndFutureVersionAreRefused() throws {
        let foreign = try JSONSerialization.data(
            withJSONObject: [
                "format": "some-other-input-method",
                "version": 1,
                "exportedAt": 0,
                "characters": [],
                "phrases": [],
            ]
        )
        let future = try JSONSerialization.data(
            withJSONObject: [
                "format": UserDataArchive.formatIdentifier,
                "version": UserDataArchive.currentVersion + 1,
                "exportedAt": 0,
                "characters": [],
                "phrases": [],
            ]
        )

        XCTAssertThrowsError(try UserDataArchive.decoded(from: foreign)) { error in
            XCTAssertEqual(
                error as? UserDataArchiveError,
                .unknownFormat("some-other-input-method")
            )
        }
        XCTAssertThrowsError(try UserDataArchive.decoded(from: future)) { error in
            XCTAssertEqual(
                error as? UserDataArchiveError,
                .unsupportedVersion(UserDataArchive.currentVersion + 1)
            )
        }
    }

    func testUnreadableFileIsRefusedWithoutCrashing() {
        for data in [
            Data("not json at all".utf8),
            Data(),
            try! JSONSerialization.data(withJSONObject: ["format": "x"]),
        ] {
            XCTAssertThrowsError(try UserDataArchive.decoded(from: data)) { error in
                XCTAssertEqual(
                    error as? UserDataArchiveError,
                    .malformedDocument
                )
            }
        }
    }

    func testUnusableEntriesAreSkippedAndCounted() throws {
        let data = try JSONSerialization.data(
            withJSONObject: [
                "format": UserDataArchive.formatIdentifier,
                "version": 1,
                "exportedAt": 0,
                "characters": [
                    ["character": "鍵", "pronunciation": "ㄐㄧㄢˋ",
                     "selectionCount": 3, "pinned": false],
                    ["character": "", "pronunciation": "ㄐㄧㄢˋ",
                     "selectionCount": 1, "pinned": false],
                    ["character": "鍵盤", "pronunciation": "ㄐㄧㄢˋ",
                     "selectionCount": 1, "pinned": false],
                    ["character": "鍵", "pronunciation": "not bopomofo",
                     "selectionCount": 1, "pinned": false],
                    ["character": "鍵", "pronunciation": "ㄐㄧㄢˋ",
                     "selectionCount": -5, "pinned": false],
                ],
                "phrases": [
                    ["phrase": "久空", "readings": ["ㄐㄧㄡˇ", "ㄎㄨㄥ"],
                     "selectionCount": 0, "createdAt": 0, "pinned": false],
                    ["phrase": "久", "readings": ["ㄐㄧㄡˇ"],
                     "selectionCount": 0, "createdAt": 0, "pinned": false],
                    ["phrase": "久空", "readings": ["ㄐㄧㄡˇ"],
                     "selectionCount": 0, "createdAt": 0, "pinned": false],
                    ["phrase": "久空", "readings": ["ㄐㄧㄡˇ", "zz"],
                     "selectionCount": 0, "createdAt": 0, "pinned": false],
                ],
            ]
        )

        let (archive, issues) = try UserDataArchive.decoded(from: data)

        XCTAssertEqual(archive.characters.map(\.character), ["鍵"])
        XCTAssertEqual(archive.characters.first?.selectionCount, 3)
        XCTAssertEqual(archive.phrases.map(\.phrase), ["久空"])
        XCTAssertEqual(issues.skippedCharacters, 4)
        XCTAssertEqual(issues.skippedPhrases, 3)
        XCTAssertFalse(issues.isEmpty)
    }

    func testDuplicateEntriesAreKeptOnlyOnce() throws {
        let data = try JSONSerialization.data(
            withJSONObject: [
                "format": UserDataArchive.formatIdentifier,
                "version": 1,
                "exportedAt": 0,
                "characters": [
                    ["character": "鍵", "pronunciation": "ㄐㄧㄢˋ",
                     "selectionCount": 3, "pinned": false],
                    ["character": "鍵", "pronunciation": "ㄐㄧㄢˋ",
                     "selectionCount": 9, "pinned": true],
                ],
                "phrases": [
                    ["phrase": "久空", "readings": ["ㄐㄧㄡˇ", "ㄎㄨㄥ"],
                     "selectionCount": 0, "createdAt": 0, "pinned": false],
                    ["phrase": "久空", "readings": ["ㄐㄧㄡˇ", "ㄎㄨㄥ"],
                     "selectionCount": 4, "createdAt": 0, "pinned": false],
                ],
            ]
        )

        let (archive, issues) = try UserDataArchive.decoded(from: data)

        XCTAssertEqual(archive.characters.map(\.selectionCount), [3])
        XCTAssertEqual(archive.phrases.map(\.selectionCount), [0])
        XCTAssertEqual(issues.skippedCharacters, 1)
        XCTAssertEqual(issues.skippedPhrases, 1)
    }

    func testDifferentReadingsOfTheSameTextAreDistinctEntries() throws {
        let data = try JSONSerialization.data(
            withJSONObject: [
                "format": UserDataArchive.formatIdentifier,
                "version": 1,
                "exportedAt": 0,
                "characters": [
                    ["character": "行", "pronunciation": "ㄒㄧㄥˊ",
                     "selectionCount": 1, "pinned": false],
                    ["character": "行", "pronunciation": "ㄏㄤˊ",
                     "selectionCount": 2, "pinned": false],
                ],
                "phrases": [],
            ]
        )

        let (archive, issues) = try UserDataArchive.decoded(from: data)

        XCTAssertEqual(archive.characters.count, 2)
        XCTAssertTrue(issues.isEmpty)
    }

    func testArchiveCarriesRemovedBuiltInPhrases() throws {
        let archive = UserDataArchive.make(
            characters: [],
            phrases: [],
            suppressions: [
                SuppressedPhraseRecord(
                    phrase: "測試",
                    pronunciationSequence: ["ㄘㄜˋ", "ㄕˋ"],
                    suppressedAt: Date(timeIntervalSince1970: 300.25)
                ),
            ],
            exportedAt: Date(timeIntervalSince1970: 2_000)
        )

        let (decoded, issues) = try UserDataArchive.decoded(
            from: try archive.encoded()
        )

        XCTAssertEqual(decoded, archive)
        XCTAssertTrue(issues.isEmpty)
        XCTAssertFalse(decoded.isEmpty)
        XCTAssertEqual(decoded.suppressions.first?.phrase, "測試")
        XCTAssertEqual(
            decoded.suppressions.first?.readings,
            ["ㄘㄜˋ", "ㄕˋ"]
        )
        XCTAssertEqual(decoded.suppressions.first?.suppressedAt, 300_250)
    }

    /// Version 1 and 2 documents predate removable built-in phrases. They must
    /// still import in full rather than being refused for a missing list.
    func testOlderDocumentWithoutSuppressionsStillImports() throws {
        let data = try JSONSerialization.data(
            withJSONObject: [
                "format": UserDataArchive.formatIdentifier,
                "version": 2,
                "exportedAt": 0,
                "characters": [
                    [
                        "character": "鍵",
                        "pronunciation": "ㄐㄧㄢˋ",
                        "selectionCount": 3,
                        "pinned": false,
                    ],
                ],
                "phrases": [],
            ]
        )

        let (decoded, issues) = try UserDataArchive.decoded(from: data)

        XCTAssertEqual(decoded.characters.count, 1)
        XCTAssertEqual(decoded.suppressions, [])
        XCTAssertTrue(issues.isEmpty)
    }

    func testUnusableRemovedBuiltInPhrasesAreSkippedAndCounted() throws {
        let data = try JSONSerialization.data(
            withJSONObject: [
                "format": UserDataArchive.formatIdentifier,
                "version": UserDataArchive.currentVersion,
                "exportedAt": 0,
                "characters": [],
                "phrases": [],
                "suppressions": [
                    [
                        "phrase": "測試",
                        "readings": ["ㄘㄜˋ", "ㄕˋ"],
                        "suppressedAt": 1,
                    ],
                    [
                        "phrase": "測試",
                        "readings": ["ㄘㄜˋ", "ㄕˋ"],
                        "suppressedAt": 2,
                    ],
                    [
                        "phrase": "錯誤",
                        "readings": ["ASCII", "ㄨˋ"],
                        "suppressedAt": 3,
                    ],
                    [
                        "phrase": "太長",
                        "readings": ["ㄊㄞˋ"],
                        "suppressedAt": 4,
                    ],
                ],
            ]
        )

        let (decoded, issues) = try UserDataArchive.decoded(from: data)

        XCTAssertEqual(decoded.suppressions.count, 1)
        XCTAssertEqual(decoded.suppressions.first?.suppressedAt, 1)
        XCTAssertEqual(issues.skippedSuppressions, 3)
        XCTAssertFalse(issues.isEmpty)
    }

    func testEmptyArchiveIsValid() throws {
        let archive = UserDataArchive.make(
            characters: [],
            phrases: [],
            exportedAt: Date(timeIntervalSince1970: 0)
        )

        let (decoded, issues) = try UserDataArchive.decoded(
            from: try archive.encoded()
        )

        XCTAssertTrue(decoded.isEmpty)
        XCTAssertTrue(issues.isEmpty)
    }
}
