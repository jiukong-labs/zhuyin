import Foundation
import XCTest

final class UserPhraseRecordTests: XCTestCase {
    func testValidatorNormalizesPhraseToNFC() throws {
        let decomposedPhrase = "e\u{301}好"

        let value = try UserPhraseValidator.validate(
            phrase: decomposedPhrase,
            pronunciationSequence: ["ㄟˊ", "ㄏㄠˇ"]
        )

        XCTAssertEqual(value.phrase, "é好")
        XCTAssertEqual(
            value.phrase,
            value.phrase.precomposedStringWithCanonicalMapping
        )
        XCTAssertEqual(value.pronunciationSequence, ["ㄟˊ", "ㄏㄠˇ"])
    }

    func testValidatorAcceptsCanonicalTonePositionsAndFirstToneOmission() throws {
        let cases = [
            ["ㄅ", "ㄆㄛˊ"],
            ["ㄨㄛˇ", "ㄕˋ"],
            ["˙ㄉㄜ", "ㄇㄚ"],
            ["ㄧㄚ", "ㄦˊ"],
        ]

        for readings in cases {
            XCTAssertNoThrow(
                try UserPhraseValidator.validate(
                    phrase: "甲乙",
                    pronunciationSequence: readings
                ),
                "Expected canonical readings: \(readings)"
            )
        }
    }

    func testValidatorRejectsNonBopomofoDuplicateAndOutOfOrderComponents() {
        let invalidReadings = [
            "ASCII",
            "ㄅㄆ",
            "ㄧㄨ",
            "ㄚㄧ",
            "ㄚㄛ",
        ]

        for reading in invalidReadings {
            XCTAssertThrowsError(
                try UserPhraseValidator.validate(
                    phrase: "甲乙",
                    pronunciationSequence: [reading, "ㄅ"]
                )
            ) { error in
                XCTAssertEqual(
                    error as? UserPhraseValidationError,
                    .invalidPronunciation(index: 0)
                )
            }
        }
    }

    func testValidatorRejectsMisplacedOrDuplicatedTones() {
        let invalidReadings = [
            "ˊㄅ",
            "ㄅ˙",
            "ㄅˇㄚ",
            "˙ㄅˋ",
            "˙˙ㄅ",
            "ㄅˊˋ",
        ]

        for reading in invalidReadings {
            XCTAssertThrowsError(
                try UserPhraseValidator.validate(
                    phrase: "甲乙",
                    pronunciationSequence: ["ㄅ", reading]
                )
            ) { error in
                XCTAssertEqual(
                    error as? UserPhraseValidationError,
                    .invalidPronunciation(index: 1)
                )
            }
        }
    }

    func testValidatorRequiresTwoReadingsUnlessPunctuatedAndCapsAt64() throws {
        XCTAssertThrowsError(
            try UserPhraseValidator.validate(
                phrase: "甲",
                pronunciationSequence: ["ㄅ"]
            )
        ) { error in
            XCTAssertEqual(
                error as? UserPhraseValidationError,
                .invalidUnitCount(1)
            )
        }

        let punctuated = try UserPhraseValidator.validate(
            phrase: "嗎？",
            pronunciationSequence: ["ㄇㄚ"]
        )
        XCTAssertEqual(punctuated.outputPattern.rawValue, "RP")

        let maximumPhrase = String(repeating: "甲", count: 64)
        let maximumReadings = Array(repeating: "ㄅ", count: 64)
        XCTAssertNoThrow(
            try UserPhraseValidator.validate(
                phrase: maximumPhrase,
                pronunciationSequence: maximumReadings
            )
        )

        XCTAssertThrowsError(
            try UserPhraseValidator.validate(
                phrase: maximumPhrase + "甲",
                pronunciationSequence: maximumReadings + ["ㄅ"]
            )
        ) { error in
            XCTAssertEqual(
                error as? UserPhraseValidationError,
                .invalidUnitCount(65)
            )
        }

        XCTAssertThrowsError(
            try UserPhraseValidator.validate(
                phrase: "甲乙丙",
                pronunciationSequence: ["ㄅ", "ㄆ"]
            )
        ) { error in
            XCTAssertEqual(
                error as? UserPhraseValidationError,
                .textReadingCountMismatch(textCount: 3, readingCount: 2)
            )
        }
    }

    func testVersionedLengthPrefixDistinguishesAmbiguousConcatenations() throws {
        let first = try UserPhrasePronunciationKey.encode(["ㄅ", "ㄧㄚ"])
        let second = try UserPhrasePronunciationKey.encode(["ㄅㄧ", "ㄚ"])

        XCTAssertTrue(first.hasPrefix("v1|"))
        XCTAssertTrue(second.hasPrefix("v1|"))
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(
            ["ㄅ", "ㄧㄚ"].joined(),
            ["ㄅㄧ", "ㄚ"].joined()
        )
    }
}
