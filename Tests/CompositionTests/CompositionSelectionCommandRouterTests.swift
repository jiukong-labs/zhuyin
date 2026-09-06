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
            .previousUnit
        )
        XCTAssertEqual(
            cursorCommand(
                kVK_RightArrow,
                modifiers: [.function, .numericPad, .capsLock]
            ),
            .nextUnit
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

    func testDownOpensRevisionCandidatesAndUpReturnsToPositioning() {
        XCTAssertEqual(
            revisionCandidateCommand(
                kVK_DownArrow,
                modifiers: [.function],
                hasRevisionCaret: true,
                isChoosingCandidates: false
            ),
            .openCandidates
        )
        XCTAssertEqual(
            revisionCandidateCommand(
                kVK_UpArrow,
                modifiers: [.function, .numericPad],
                hasRevisionCaret: true,
                isChoosingCandidates: true
            ),
            .returnToPositioning
        )
    }

    /// Up belongs to the candidate grid for as long as the highlight has a row
    /// above it, so every displayed row can be reached without leaving
    /// candidate choosing. Only the first row hands Up back to positioning.
    func testUpStaysInTheGridWhileARowAboveTheHighlightRemains() {
        XCTAssertNil(
            revisionCandidateCommand(
                kVK_UpArrow,
                modifiers: [.function],
                hasRevisionCaret: true,
                isChoosingCandidates: true,
                hasCandidateRowAbove: true
            )
        )
        XCTAssertEqual(
            revisionCandidateCommand(
                kVK_UpArrow,
                modifiers: [.function],
                hasRevisionCaret: true,
                isChoosingCandidates: true,
                hasCandidateRowAbove: false
            ),
            .returnToPositioning
        )
        XCTAssertEqual(
            revisionCandidateCommand(
                kVK_DownArrow,
                modifiers: [.function],
                hasRevisionCaret: true,
                isChoosingCandidates: false,
                hasCandidateRowAbove: true
            ),
            .openCandidates
        )
    }

    func testRevisionCandidateModeOwnsOnlyItsMatchingVerticalArrow() {
        XCTAssertNil(
            revisionCandidateCommand(
                kVK_UpArrow,
                modifiers: [],
                hasRevisionCaret: true,
                isChoosingCandidates: false
            )
        )
        XCTAssertNil(
            revisionCandidateCommand(
                kVK_DownArrow,
                modifiers: [],
                hasRevisionCaret: true,
                isChoosingCandidates: true
            )
        )
        XCTAssertNil(
            revisionCandidateCommand(
                kVK_DownArrow,
                modifiers: [],
                hasRevisionCaret: false,
                isChoosingCandidates: false
            )
        )
        XCTAssertNil(
            revisionCandidateCommand(
                kVK_DownArrow,
                modifiers: [.shift],
                hasRevisionCaret: true,
                isChoosingCandidates: false
            )
        )
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

    private func revisionCandidateCommand(
        _ keyCode: Int,
        modifiers: NSEvent.ModifierFlags,
        hasRevisionCaret: Bool,
        isChoosingCandidates: Bool,
        hasCandidateRowAbove: Bool = false
    ) -> CompositionRevisionCandidateCommand? {
        CompositionRevisionCandidateCommandRouter.command(
            keyCode: UInt16(keyCode),
            modifierFlags: modifiers,
            hasRevisionCaret: hasRevisionCaret,
            isChoosingCandidates: isChoosingCandidates,
            hasCandidateRowAbove: hasCandidateRowAbove
        )
    }
}
