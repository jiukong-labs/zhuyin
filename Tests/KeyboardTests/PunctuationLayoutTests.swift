import Carbon
import XCTest

final class PunctuationLayoutTests: XCTestCase {
    private let layout = PunctuationLayout.standard

    func testShiftedZhuyinKeysProduceFullWidthPunctuation() {
        let expected: [(KeyboardKey, String)] = [
            (.comma, "，"),
            (.period, "。"),
            (.slash, "？"),
            (.semicolon, "："),
            (.digit1, "！"),
            (.digit6, "…"),
            (.digit9, "（"),
            (.digit0, "）"),
            (.minus, "—"),
        ]

        for (key, punctuation) in expected {
            XCTAssertEqual(
                layout.punctuation(for: key, shifted: true),
                punctuation,
                "shifted \(key)"
            )
        }
    }

    func testUnusedKeysCarryBracketMarksWithoutShift() {
        XCTAssertEqual(layout.punctuation(for: .leftBracket, shifted: false), "「")
        XCTAssertEqual(layout.punctuation(for: .rightBracket, shifted: false), "」")
        XCTAssertEqual(layout.punctuation(for: .backslash, shifted: false), "、")
        XCTAssertEqual(layout.punctuation(for: .leftBracket, shifted: true), "『")
        XCTAssertEqual(layout.punctuation(for: .rightBracket, shifted: true), "』")
    }

    func testUnshiftedZhuyinKeysKeepTheirBopomofoMeaning() {
        let zhuyinLayout = StandardZhuyinLayout()
        let keys: [KeyboardKey] = [
            .comma, .period, .slash, .semicolon, .minus,
            .digit1, .digit6, .digit9, .digit0,
        ]

        for key in keys {
            XCTAssertNil(
                layout.punctuation(for: key, shifted: false),
                "unshifted \(key)"
            )
            XCTAssertNotNil(zhuyinLayout.component(for: key), "\(key)")
        }
    }

    func testLettersAndControlKeysNeverProducePunctuation() {
        let keys: [KeyboardKey] = [
            .letterA, .letterZ, .letterQ, .letterM,
            .space, .returnKey, .keypadEnter, .escape, .deleteBackward,
            .digit2, .digit3, .digit4, .digit5, .digit7, .digit8,
        ]

        for key in keys {
            XCTAssertNil(layout.punctuation(for: key, shifted: false), "\(key)")
            XCTAssertNil(layout.punctuation(for: key, shifted: true), "\(key)")
        }
    }

    func testBackslashHasNoShiftedMark() {
        XCTAssertNil(layout.punctuation(for: .backslash, shifted: true))
    }

    func testEveryPunctuationKeyResolvesFromItsVirtualKeyCode() {
        let expected: [(Int, KeyboardKey)] = [
            (kVK_ANSI_LeftBracket, .leftBracket),
            (kVK_ANSI_RightBracket, .rightBracket),
            (kVK_ANSI_Backslash, .backslash),
            (kVK_ANSI_Comma, .comma),
            (kVK_ANSI_Period, .period),
            (kVK_ANSI_Slash, .slash),
            (kVK_ANSI_Semicolon, .semicolon),
            (kVK_ANSI_Minus, .minus),
        ]

        for (keyCode, key) in expected {
            XCTAssertEqual(
                MacVirtualKeyResolver.key(for: UInt16(keyCode)),
                key,
                "key code \(keyCode)"
            )
        }
    }

    func testPunctuationIsSingleFullWidthTextWithoutAscii() {
        let keys: [KeyboardKey] = [
            .comma, .period, .slash, .semicolon, .digit1, .digit6,
            .digit9, .digit0, .minus, .leftBracket, .rightBracket, .backslash,
        ]

        for key in keys {
            for shifted in [true, false] {
                guard let punctuation = layout.punctuation(
                    for: key,
                    shifted: shifted
                ) else {
                    continue
                }
                XCTAssertEqual(punctuation.count, 1, "\(key) \(shifted)")
                XCTAssertFalse(
                    punctuation.unicodeScalars.contains { $0.isASCII },
                    "\(key) \(shifted)"
                )
            }
        }
    }
}
