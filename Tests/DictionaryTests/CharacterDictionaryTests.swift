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
                DictionaryCharacter(
                    text: "我",
                    sourceOrder: 827,
                    cnsPlane: 1,
                    usageTier: 0,
                    firstPartyPhraseCount: 35,
                    defaultSelectionCount: 164
                ),
                DictionaryCharacter(text: "倭", sourceOrder: 2_092, cnsPlane: 1, usageTier: 0),
                DictionaryCharacter(text: "婑", sourceOrder: 9_357, cnsPlane: 2, usageTier: 2),
            ]
        )
        XCTAssertTrue(entries[0].isInGeneralCandidateRepertoire)
        XCTAssertTrue(entries[2].isInGeneralCandidateRepertoire)
        XCTAssertFalse(entries[4].isInGeneralCandidateRepertoire)
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

    func testTiFourthToneContainsTi() throws {
        let dictionary = try makeDictionary()

        XCTAssertTrue(try dictionary.candidates(for: "ㄊㄧˋ").contains("剔"))
        XCTAssertTrue(try dictionary.pronunciations(for: "剔").contains("ㄊㄧˋ"))
    }

    func testNeutralMoOffersMeAsTheFirstCandidate() throws {
        let dictionary = try makeDictionary()

        XCTAssertEqual(try dictionary.candidates(for: "˙ㄇㄛ").first, "麼")
        XCTAssertTrue(
            try dictionary.pronunciations(for: "麼").contains("˙ㄇㄛ")
        )
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
        XCTAssertEqual(
            try dictionary.phraseEntries(
                for: ["ㄅㄨˋ", "ㄘㄞˊ", "ㄗㄞˋ", "ㄉㄜ˙"]
            ),
            []
        )
        XCTAssertEqual(try dictionary.phraseEntries(for: ["ㄘㄜˋ"]), [])
    }

    func testFirstPartyPhraseLookupFindsTestByExactReadingSequence() throws {
        let dictionary = try makeDictionary()

        XCTAssertEqual(
            try dictionary.phraseEntries(for: ["ㄘㄜˋ", "ㄕˋ"]),
            [
                DictionaryPhrase(
                    text: "測試",
                    pronunciationSequence: ["ㄘㄜˋ", "ㄕˋ"],
                    sourceOrder: 0,
                    defaultSelectionCount: 8
                ),
            ]
        )
        XCTAssertEqual(
            try dictionary.phraseEntries(for: ["ㄘㄜˋ", "ㄕˇ"]),
            []
        )
    }

    func testFirstPartyPhraseLookupFindsTheRequestedSentence() throws {
        let dictionary = try makeDictionary()
        let readings = ["ㄘㄜˋ", "ㄕˋ", "ㄓㄨㄥ", "ㄑㄧㄥˇ", "ㄕㄠ", "ㄏㄡˋ"]

        XCTAssertEqual(
            try dictionary.phraseEntries(for: readings).map(\.text),
            ["測試中請稍後"]
        )
    }

    func testBundledArtifactHasPinnedMetadataAndPassesQuickCheck() throws {
        let dictionary = try makeDictionary()

        XCTAssertEqual(try dictionary.metadataValue(for: "source_version"), "20260805")
        XCTAssertEqual(try dictionary.metadataValue(for: "dictionary_entries"), "94712")
        XCTAssertEqual(try dictionary.metadataValue(for: "unique_characters"), "76373")
        XCTAssertEqual(
            try dictionary.metadataValue(for: "first_party_character_entries"),
            "4"
        )
        XCTAssertEqual(try dictionary.metadataValue(for: "phrase_entries"), "1965")
        XCTAssertEqual(try dictionary.metadataValue(for: "unique_phrases"), "1964")
        XCTAssertEqual(
            try dictionary.metadataValue(for: "default_character_ranking_entries"),
            "804"
        )
        XCTAssertEqual(
            try dictionary.metadataValue(for: "default_character_ranking_selections"),
            "7066"
        )
        XCTAssertEqual(
            try dictionary.metadataValue(for: "default_phrase_ranking_entries"),
            "385"
        )
        XCTAssertEqual(
            try dictionary.metadataValue(for: "default_phrase_ranking_selections"),
            "2277"
        )
        XCTAssertEqual(
            try dictionary.metadataValue(
                for: "first_party_attested_character_readings"
            ),
            "1202"
        )
        XCTAssertEqual(
            try dictionary.metadataValue(
                for: "first_party_character_reading_attestations"
            ),
            "4817"
        )
        XCTAssertEqual(
            try dictionary.metadataValue(for: "phrase_dataset_name"),
            "Jiukong first-party phrase lexicon"
        )
        XCTAssertEqual(
            try dictionary.metadataValue(for: "frequency_tier_common_characters"),
            "4808"
        )
        XCTAssertEqual(
            try dictionary.metadataValue(for: "frequency_tier_semi_common_characters"),
            "6343"
        )
        XCTAssertEqual(
            try dictionary.metadataValue(for: "frequency_tier_heteronym_overrides"),
            "3"
        )
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

    func testNarrowYiHeteronymsAreRareWithoutChangingTheirEverydayReadings() throws {
        let dictionary = try makeDictionary()

        func tier(_ character: String, reading: String) throws -> Int? {
            try dictionary.candidateEntries(for: reading)
                .first(where: { $0.text == character })?.usageTier
        }

        XCTAssertEqual(try tier("食", reading: "ㄧˋ"), 2)
        XCTAssertEqual(try tier("射", reading: "ㄧˋ"), 2)
        XCTAssertEqual(try tier("食", reading: "ㄕˊ"), 0)
        XCTAssertEqual(try tier("射", reading: "ㄕㄜˋ"), 0)
    }

    func testFirstPartyPhraseCountsAreSpecificToEachReading() throws {
        let dictionary = try makeDictionary()

        func count(_ character: String, reading: String) throws -> Int64? {
            try dictionary.candidateEntries(for: reading)
                .first(where: { $0.text == character })?
                .firstPartyPhraseCount
        }

        XCTAssertEqual(try count("意", reading: "ㄧˋ"), 10)
        XCTAssertEqual(try count("食", reading: "ㄕˊ"), 4)
        XCTAssertEqual(try count("食", reading: "ㄧˋ"), 0)
        XCTAssertEqual(try count("射", reading: "ㄧˋ"), 0)
    }

    func testBundledLexiconCoversReviewedEverydayCategories() throws {
        let dictionary = try makeDictionary()
        let cases: [([String], String)] = [
            (["ㄗㄠˇ", "ㄢ"], "早安"),
            (["ㄒㄧㄥ", "ㄑㄧˊ", "ㄧ"], "星期一"),
            (["ㄐㄧㄚ", "ㄖㄣˊ"], "家人"),
            (["ㄔ", "ㄈㄢˋ"], "吃飯"),
            (["ㄊㄨˊ", "ㄕㄨ", "ㄍㄨㄢˇ"], "圖書館"),
            (["ㄏㄨㄟˋ", "ㄧˋ"], "會議"),
            (["ㄗ", "ㄌㄧㄠˋ", "ㄐㄧㄚˊ"], "資料夾"),
            (["ㄅㄨˋ", "ㄕㄨ", "ㄈㄨˊ"], "不舒服"),
        ]

        for (readings, expected) in cases {
            XCTAssertTrue(
                try dictionary.phraseEntries(for: readings)
                    .contains(where: { $0.text == expected }),
                expected
            )
        }
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
