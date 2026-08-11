import AppKit
import Carbon
import XCTest

final class SystemCandidateKeyRoutingTests: XCTestCase {
    func testMapsCandidateSelectionNumbers() {
        let selectionKeys = [
            (kVK_ANSI_1, 0),
            (kVK_ANSI_5, 4),
            (kVK_ANSI_9, 8)
        ]

        for (keyCode, expectedIndex) in selectionKeys {
            XCTAssertEqual(
                SystemCandidateKeyRouting.selectionKeyIndex(
                    keyCode: UInt16(keyCode),
                    modifierFlags: []
                ),
                expectedIndex
            )
        }
    }

    func testMapsNavigationWithFlagsInherentToNavigationKeys() {
        let inherentModifierSets: [NSEvent.ModifierFlags] = [
            .function,
            .numericPad,
            [.function, .numericPad]
        ]

        for modifierFlags in inherentModifierSets {
            XCTAssertEqual(
                SystemCandidateKeyRouting.navigation(
                    keyCode: UInt16(kVK_RightArrow),
                    modifierFlags: modifierFlags
                ),
                .next
            )
        }
    }

    func testMapsEveryNavigationKey() {
        let mappings: [(Int, CandidateNavigation)] = [
            (kVK_LeftArrow, .previous),
            (kVK_UpArrow, .previous),
            (kVK_RightArrow, .next),
            (kVK_DownArrow, .next),
            (kVK_Home, .first),
            (kVK_End, .last),
            (kVK_PageUp, .previousPage),
            (kVK_PageDown, .nextPage)
        ]

        for (keyCode, expectedNavigation) in mappings {
            XCTAssertEqual(
                SystemCandidateKeyRouting.navigation(
                    keyCode: UInt16(keyCode),
                    modifierFlags: []
                ),
                expectedNavigation
            )
        }
    }

    func testDoesNotNavigateWithShortcutModifiers() {
        let shortcutModifiers: [NSEvent.ModifierFlags] = [
            .command,
            .control,
            .option,
            .shift,
            [.command, .function]
        ]

        for modifierFlags in shortcutModifiers {
            XCTAssertNil(
                SystemCandidateKeyRouting.navigation(
                    keyCode: UInt16(kVK_RightArrow),
                    modifierFlags: modifierFlags
                )
            )
        }
    }

    func testDoesNotMapSelectionNumbersWithShortcutModifiers() {
        XCTAssertNil(
            SystemCandidateKeyRouting.selectionKeyIndex(
                keyCode: UInt16(kVK_ANSI_2),
                modifierFlags: .shift
            )
        )
    }

    func testKeepsCancellationCommitAndZeroKeysOutOfNumberSelection() {
        for keyCode in [kVK_Delete, kVK_Escape, kVK_Return, kVK_ANSI_0] {
            XCTAssertNil(
                SystemCandidateKeyRouting.selectionKeyIndex(
                    keyCode: UInt16(keyCode),
                    modifierFlags: []
                )
            )
        }
    }
}
