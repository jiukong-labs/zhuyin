import Carbon
import XCTest

final class StandardZhuyinLayoutTests: XCTestCase {
    func testMapsEveryStandardZhuyinPhysicalKey() throws {
        let mappings: [(Int, String)] = [
            (kVK_ANSI_1, "ㄅ"), (kVK_ANSI_Q, "ㄆ"),
            (kVK_ANSI_A, "ㄇ"), (kVK_ANSI_Z, "ㄈ"),
            (kVK_ANSI_2, "ㄉ"), (kVK_ANSI_W, "ㄊ"),
            (kVK_ANSI_S, "ㄋ"), (kVK_ANSI_X, "ㄌ"),
            (kVK_ANSI_E, "ㄍ"), (kVK_ANSI_D, "ㄎ"),
            (kVK_ANSI_C, "ㄏ"), (kVK_ANSI_R, "ㄐ"),
            (kVK_ANSI_F, "ㄑ"), (kVK_ANSI_V, "ㄒ"),
            (kVK_ANSI_5, "ㄓ"), (kVK_ANSI_T, "ㄔ"),
            (kVK_ANSI_G, "ㄕ"), (kVK_ANSI_B, "ㄖ"),
            (kVK_ANSI_Y, "ㄗ"), (kVK_ANSI_H, "ㄘ"),
            (kVK_ANSI_N, "ㄙ"), (kVK_ANSI_U, "ㄧ"),
            (kVK_ANSI_J, "ㄨ"), (kVK_ANSI_M, "ㄩ"),
            (kVK_ANSI_8, "ㄚ"), (kVK_ANSI_I, "ㄛ"),
            (kVK_ANSI_K, "ㄜ"), (kVK_ANSI_Comma, "ㄝ"),
            (kVK_ANSI_9, "ㄞ"), (kVK_ANSI_O, "ㄟ"),
            (kVK_ANSI_L, "ㄠ"), (kVK_ANSI_Period, "ㄡ"),
            (kVK_ANSI_0, "ㄢ"), (kVK_ANSI_P, "ㄣ"),
            (kVK_ANSI_Semicolon, "ㄤ"), (kVK_ANSI_Slash, "ㄥ"),
            (kVK_ANSI_Minus, "ㄦ"), (kVK_Space, ""),
            (kVK_ANSI_6, "ˊ"), (kVK_ANSI_3, "ˇ"),
            (kVK_ANSI_4, "ˋ"), (kVK_ANSI_7, "˙")
        ]
        let layout = StandardZhuyinLayout()

        XCTAssertEqual(mappings.count, 42)
        for (keyCode, expectedText) in mappings {
            let key = try XCTUnwrap(
                MacVirtualKeyResolver.key(for: UInt16(keyCode)),
                "Missing physical key code \(keyCode)"
            )
            XCTAssertEqual(
                layout.component(for: key)?.text,
                expectedText,
                "Unexpected mapping for physical key code \(keyCode)"
            )
        }
    }

    func testResolvesCompositionControlKeys() {
        XCTAssertEqual(
            MacVirtualKeyResolver.key(for: UInt16(kVK_Delete)),
            .deleteBackward
        )
        XCTAssertEqual(
            MacVirtualKeyResolver.key(for: UInt16(kVK_Escape)),
            .escape
        )
        XCTAssertEqual(
            MacVirtualKeyResolver.key(for: UInt16(kVK_Return)),
            .returnKey
        )
        XCTAssertEqual(
            MacVirtualKeyResolver.key(for: UInt16(kVK_ANSI_KeypadEnter)),
            .keypadEnter
        )
    }

    func testLeavesUnmappedPhysicalKeyAlone() {
        XCTAssertNil(MacVirtualKeyResolver.key(for: UInt16(kVK_ANSI_Equal)))
    }
}
