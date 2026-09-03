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
        // Quote and equal became resolvable in Milestone 10 because other
        // arrangements use them; grave and Tab still belong to the client.
        XCTAssertNil(MacVirtualKeyResolver.key(for: UInt16(kVK_ANSI_Grave)))
        XCTAssertNil(MacVirtualKeyResolver.key(for: UInt16(kVK_Tab)))
    }

    func testStandardArrangementIgnoresKeysOtherArrangementsUse() {
        let layout = StandardZhuyinLayout()

        XCTAssertNil(layout.component(for: .quote))
        XCTAssertNil(layout.component(for: .equal))
    }

    func testOptionASCIIShortcutProducesEveryTopRowDigit() {
        let mappings: [(KeyboardKey, String)] = [
            (.digit0, "0"), (.digit1, "1"), (.digit2, "2"),
            (.digit3, "3"), (.digit4, "4"), (.digit5, "5"),
            (.digit6, "6"), (.digit7, "7"), (.digit8, "8"),
            (.digit9, "9"),
        ]

        for (key, expectedText) in mappings {
            XCTAssertEqual(
                OptionASCIIShortcut.text(
                    for: key,
                    modifierFlags: .option
                ),
                expectedText
            )
            XCTAssertEqual(
                OptionASCIIShortcut.text(
                    for: key,
                    modifierFlags: [.option, .capsLock]
                ),
                expectedText
            )
        }
    }

    func testOptionASCIIShortcutProducesLowercaseAndShiftedUppercaseLetters() {
        let mappings: [(KeyboardKey, String)] = [
            (.letterA, "a"), (.letterB, "b"), (.letterC, "c"),
            (.letterD, "d"), (.letterE, "e"), (.letterF, "f"),
            (.letterG, "g"), (.letterH, "h"), (.letterI, "i"),
            (.letterJ, "j"), (.letterK, "k"), (.letterL, "l"),
            (.letterM, "m"), (.letterN, "n"), (.letterO, "o"),
            (.letterP, "p"), (.letterQ, "q"), (.letterR, "r"),
            (.letterS, "s"), (.letterT, "t"), (.letterU, "u"),
            (.letterV, "v"), (.letterW, "w"), (.letterX, "x"),
            (.letterY, "y"), (.letterZ, "z"),
        ]

        for (key, lowercase) in mappings {
            XCTAssertEqual(
                OptionASCIIShortcut.text(
                    for: key,
                    modifierFlags: .option
                ),
                lowercase
            )
            XCTAssertEqual(
                OptionASCIIShortcut.text(
                    for: key,
                    modifierFlags: [.option, .shift]
                ),
                lowercase.uppercased()
            )
        }
    }

    /// Plain Shift (no Option) must also resolve an uppercase letter, so the
    /// caller commits it through its own reliable `insertText` call instead
    /// of leaving it to the client's handling of the raw, separately
    /// redelivered key event — a path that can land the letter away from the
    /// caret on some clients when it races an in-flight composition commit.
    func testShiftAloneProducesUppercaseLettersButNotDigits() {
        let mappings: [(KeyboardKey, String)] = [
            (.letterA, "A"), (.letterB, "B"), (.letterC, "C"),
            (.letterD, "D"), (.letterE, "E"), (.letterF, "F"),
            (.letterG, "G"), (.letterH, "H"), (.letterI, "I"),
            (.letterJ, "J"), (.letterK, "K"), (.letterL, "L"),
            (.letterM, "M"), (.letterN, "N"), (.letterO, "O"),
            (.letterP, "P"), (.letterQ, "Q"), (.letterR, "R"),
            (.letterS, "S"), (.letterT, "T"), (.letterU, "U"),
            (.letterV, "V"), (.letterW, "W"), (.letterX, "X"),
            (.letterY, "Y"), (.letterZ, "Z"),
        ]

        for (key, uppercase) in mappings {
            XCTAssertEqual(
                OptionASCIIShortcut.text(
                    for: key,
                    modifierFlags: .shift
                ),
                uppercase
            )
            XCTAssertEqual(
                OptionASCIIShortcut.text(
                    for: key,
                    modifierFlags: [.shift, .capsLock]
                ),
                uppercase
            )
        }

        for digit: KeyboardKey in [
            .digit0, .digit1, .digit2, .digit3, .digit4,
            .digit5, .digit6, .digit7, .digit8, .digit9,
        ] {
            XCTAssertNil(
                OptionASCIIShortcut.text(for: digit, modifierFlags: .shift)
            )
        }
    }

    func testOptionASCIIShortcutRejectsOtherKeysAndModifierChords() {
        XCTAssertNil(
            OptionASCIIShortcut.text(for: .digit1, modifierFlags: [])
        )
        XCTAssertNil(
            OptionASCIIShortcut.text(
                for: .digit1,
                modifierFlags: [.option, .shift]
            )
        )

        for modifiers: NSEvent.ModifierFlags in [
            [.option, .command],
            [.option, .control],
            [.option, .function],
        ] {
            XCTAssertNil(
                OptionASCIIShortcut.text(
                    for: .letterA,
                    modifierFlags: modifiers
                )
            )
        }
    }
}
