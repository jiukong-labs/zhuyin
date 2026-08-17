import AppKit
import XCTest

final class CursorIndicatorAppearanceTests: XCTestCase {
    func testDefaultsMatchTheLanguageModeIndicators() {
        let appearance = CursorIndicatorAppearance()

        XCTAssertEqual(appearance.text(for: .chinese), "中")
        XCTAssertEqual(appearance.text(for: .english), "A")
        XCTAssertEqual(appearance.color(for: .chinese), .systemRed)
        XCTAssertEqual(appearance.color(for: .english), .systemBlue)
    }

    func testCustomTextIsTrimmedAndLengthLimited() {
        let appearance = CursorIndicatorAppearance(
            chineseText: "  漢字輸入中  ",
            englishText: "\n en \n"
        )

        XCTAssertEqual(appearance.chineseText, "漢字輸入")
        XCTAssertEqual(appearance.text(for: .chinese), "漢字輸入")
        XCTAssertEqual(appearance.englishText, "en")
    }

    func testBlankOverridesFallBackToTheDefault() {
        let appearance = CursorIndicatorAppearance(
            chineseText: "   ",
            englishText: ""
        )

        XCTAssertNil(appearance.chineseText)
        XCTAssertNil(appearance.englishText)
        XCTAssertEqual(appearance.text(for: .chinese), "中")
        XCTAssertEqual(appearance.text(for: .english), "A")
    }

    func testHexIsNormalizedAndAppliedPerMode() {
        let appearance = CursorIndicatorAppearance(
            chineseColorHex: "00ff7f",
            englishColorHex: "#AABBCC"
        )

        XCTAssertEqual(appearance.chineseColorHex, "#00FF7F")
        XCTAssertEqual(appearance.englishColorHex, "#AABBCC")
        XCTAssertNotEqual(appearance.color(for: .chinese), .systemRed)
        XCTAssertNotEqual(appearance.color(for: .english), .systemBlue)
    }

    func testMalformedHexFallsBackToTheDefaultColor() {
        for hex in ["", "#12345", "#GGGGGG", "1234567", "red"] {
            let appearance = CursorIndicatorAppearance(chineseColorHex: hex)

            XCTAssertNil(appearance.chineseColorHex, hex)
            XCTAssertEqual(appearance.color(for: .chinese), .systemRed, hex)
        }
    }

    func testColorRoundTripsThroughHex() throws {
        let original = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        let hex = try XCTUnwrap(CursorIndicatorAppearance.hex(from: original))
        let restored = try XCTUnwrap(CursorIndicatorAppearance.color(fromHex: hex))

        XCTAssertEqual(
            CursorIndicatorAppearance.hex(from: restored),
            hex
        )
        let sRGB = try XCTUnwrap(restored.usingColorSpace(.sRGB))
        XCTAssertEqual(sRGB.redComponent, 0.2, accuracy: 0.01)
        XCTAssertEqual(sRGB.greenComponent, 0.4, accuracy: 0.01)
        XCTAssertEqual(sRGB.blueComponent, 0.6, accuracy: 0.01)
    }

    func testOneModeOverrideDoesNotDisturbTheOther() {
        let appearance = CursorIndicatorAppearance(
            chineseText: "漢",
            chineseColorHex: "#112233"
        )

        XCTAssertEqual(appearance.text(for: .chinese), "漢")
        XCTAssertEqual(appearance.text(for: .english), "A")
        XCTAssertEqual(appearance.color(for: .english), .systemBlue)
    }
}
