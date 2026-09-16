import XCTest

final class CustomReadingValidatorTests: XCTestCase {
    func testAcceptsOneVisibleCharacterWithFieldEditorFormattingScalars() throws {
        let validated = try CustomReadingValidator.validate(
            character: "\u{200B}播\u{200E}\u{FFFC}",
            pronunciation: "\u{2060}ㄅㄛ\u{FEFF}"
        )

        XCTAssertEqual(validated.character, "播")
        XCTAssertEqual(validated.pronunciation, "ㄅㄛ")
    }

    func testStillRejectsTwoVisibleCharacters() {
        XCTAssertThrowsError(
            try CustomReadingValidator.validate(
                character: "播放",
                pronunciation: "ㄅㄛ"
            )
        ) { error in
            XCTAssertEqual(
                error as? CustomReadingValidationError,
                .invalidCharacter
            )
        }
    }

    func testKeepsOrdinaryToneMarksWhileRemovingInvisibleFormatting() throws {
        let validated = try CustomReadingValidator.validate(
            character: "播",
            pronunciation: "\u{200B}ㄅㄛˋ\u{2060}"
        )

        XCTAssertEqual(validated.pronunciation, "ㄅㄛˋ")
    }
}
