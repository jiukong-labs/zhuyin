import AppKit
import Carbon
import XCTest

final class CompositionSelectionCommandRouterTests: XCTestCase {
    func testShiftLeftExpandsAndShiftRightShrinks() {
        XCTAssertEqual(
            command(kVK_LeftArrow, modifiers: [.shift, .function]),
            .expandBackward
        )
        XCTAssertEqual(
            command(kVK_RightArrow, modifiers: [.shift, .function]),
            .shrinkForward
        )
    }

    func testInherentArrowAndCapsLockFlagsAreAllowed() {
        XCTAssertEqual(
            command(
                kVK_LeftArrow,
                modifiers: [.shift, .function, .numericPad, .capsLock]
            ),
            .expandBackward
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

    private func command(
        _ keyCode: Int,
        modifiers: NSEvent.ModifierFlags
    ) -> CompositionSelectionCommand? {
        CompositionSelectionCommandRouter.command(
            keyCode: UInt16(keyCode),
            modifierFlags: modifiers
        )
    }
}
