import AppKit
import Carbon
import XCTest

final class CompositionSelectionCommandRouterTests: XCTestCase {
    func testShiftArrowsExtendTheirMatchingSelectionEdge() {
        XCTAssertEqual(
            command(kVK_LeftArrow, modifiers: [.shift, .function]),
            .extendLeft
        )
        XCTAssertEqual(
            command(kVK_RightArrow, modifiers: [.shift, .function]),
            .extendRight
        )
    }

    func testInherentArrowAndCapsLockFlagsAreAllowed() {
        XCTAssertEqual(
            command(
                kVK_LeftArrow,
                modifiers: [.shift, .function, .numericPad, .capsLock]
            ),
            .extendLeft
        )
    }

    func testArrowWithoutShiftIsNotOwnedByComposition() {
        XCTAssertNil(command(kVK_LeftArrow, modifiers: []))
        XCTAssertNil(command(kVK_RightArrow, modifiers: [.function]))
    }

    func testRealShortcutModifiersAreRejected() {
        for rejectedModifier in [
            NSEvent.ModifierFlags.command,
            .control,
            .option
        ] {
            XCTAssertNil(
                command(
                    kVK_LeftArrow,
                    modifiers: [.shift, .function, rejectedModifier]
                )
            )
            XCTAssertNil(
                command(
                    kVK_RightArrow,
                    modifiers: [.shift, .function, rejectedModifier]
                )
            )
        }
    }

    func testShiftWithNonArrowKeyIsNotASelectionCommand() {
        XCTAssertNil(command(kVK_ANSI_A, modifiers: .shift))
        XCTAssertNil(command(kVK_Return, modifiers: .shift))
    }

    func testPlainArrowsMoveTheCompositionRevisionCursor() {
        XCTAssertEqual(
            cursorCommand(kVK_LeftArrow, modifiers: [.function]),
            .previousReading
        )
        XCTAssertEqual(
            cursorCommand(
                kVK_RightArrow,
                modifiers: [.function, .numericPad, .capsLock]
            ),
            .nextReading
        )
    }

    func testRevisionCursorLeavesModifiedArrowsToTheirShortcutOwner() {
        for modifier in [
            NSEvent.ModifierFlags.shift,
            .command,
            .control,
            .option,
        ] {
            XCTAssertNil(
                cursorCommand(
                    kVK_LeftArrow,
                    modifiers: [.function, modifier]
                )
            )
            XCTAssertNil(
                cursorCommand(
                    kVK_RightArrow,
                    modifiers: [.function, modifier]
                )
            )
        }
        XCTAssertNil(cursorCommand(kVK_ANSI_A, modifiers: []))
    }

    func testBothPhysicalDeleteKeysAreRecognized() {
        XCTAssertEqual(
            deletionCommand(kVK_Delete, modifiers: []),
            .deleteBackward
        )
        XCTAssertEqual(
            deletionCommand(kVK_ForwardDelete, modifiers: [.function]),
            .deleteForward
        )
    }

    func testDeletionRejectsShortcutsAndUnrelatedKeys() {
        for modifier in [
            NSEvent.ModifierFlags.shift,
            .command,
            .control,
            .option,
        ] {
            XCTAssertNil(
                deletionCommand(kVK_Delete, modifiers: modifier)
            )
            XCTAssertNil(
                deletionCommand(kVK_ForwardDelete, modifiers: modifier)
            )
        }
        XCTAssertNil(deletionCommand(kVK_ANSI_A, modifiers: []))
    }

    private func command(
        _ keyCode: Int,
        modifiers: NSEvent.ModifierFlags
    ) -> CompositionSelectionCommand? {
        CompositionSelectionCommandRouter.command(
            keyCode: UInt16(keyCode),
            modifierFlags: modifiers
        )
    }


    private func cursorCommand(
        _ keyCode: Int,
        modifiers: NSEvent.ModifierFlags
    ) -> CompositionCursorCommand? {
        CompositionCursorCommandRouter.command(
            keyCode: UInt16(keyCode),
            modifierFlags: modifiers
        )
    }

    private func deletionCommand(
        _ keyCode: Int,
        modifiers: NSEvent.ModifierFlags
    ) -> CompositionDeletionCommand? {
        CompositionDeletionCommandRouter.command(
            keyCode: UInt16(keyCode),
            modifierFlags: modifiers
        )
    }
}
