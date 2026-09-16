import AppKit
import Carbon
import XCTest

final class ShiftToggleControllerTests: XCTestCase {
    func testStandaloneLeftShiftTogglesOnRelease() {
        var controller = ShiftToggleController()

        XCTAssertFalse(press(.left, on: &controller))
        XCTAssertTrue(release(.left, on: &controller))
    }

    func testStandaloneRightShiftTogglesOnRelease() {
        var controller = ShiftToggleController()

        XCTAssertFalse(press(.right, on: &controller))
        XCTAssertTrue(release(.right, on: &controller))
    }

    func testShiftModifiedLetterDoesNotToggle() {
        var controller = ShiftToggleController()

        _ = press(.left, on: &controller)
        controller.noteKeyDown(systemShiftIsPressed: true)
        XCTAssertFalse(release(.left, on: &controller))
    }

    func testDuplicateShiftDownDoesNotToggleBeforePhysicalRelease() {
        for side: ShiftKeySide in [.left, .right] {
            var controller = ShiftToggleController()

            XCTAssertFalse(press(side, on: &controller))
            XCTAssertFalse(press(side, on: &controller))
            XCTAssertTrue(controller.isTrackingShift)
            XCTAssertTrue(release(side, on: &controller))
        }
    }

    func testDuplicateShiftDownWithoutDeviceFlagsIsAlsoIgnored() {
        var controller = ShiftToggleController()

        XCTAssertFalse(
            controller.handleFlagsChanged(
                keyCode: UInt16(kVK_Shift),
                modifierFlags: .shift,
                systemShiftIsPressed: true
            )
        )
        XCTAssertFalse(
            controller.handleFlagsChanged(
                keyCode: UInt16(kVK_Shift),
                modifierFlags: .shift,
                systemShiftIsPressed: true
            )
        )
        XCTAssertTrue(
            controller.handleFlagsChanged(
                keyCode: UInt16(kVK_Shift),
                modifierFlags: [],
                systemShiftIsPressed: false
            )
        )
    }

    func testStaleGenericShiftFlagOnReleaseUsesSystemState() {
        var controller = ShiftToggleController()

        XCTAssertFalse(
            controller.handleFlagsChanged(
                keyCode: UInt16(kVK_Shift),
                modifierFlags: .shift,
                systemShiftIsPressed: true
            )
        )
        // macOS can leave the generic `.shift` bit on a flagsChanged release
        // even though WindowServer already reports that Shift is physically up.
        XCTAssertTrue(
            controller.handleFlagsChanged(
                keyCode: UInt16(kVK_Shift),
                modifierFlags: .shift,
                systemShiftIsPressed: false
            )
        )
        XCTAssertFalse(controller.isTrackingShift)
    }

    func testMissingShiftReleaseRecoversOnNextKeyDown() {
        var controller = ShiftToggleController()

        XCTAssertFalse(press(.left, on: &controller))
        XCTAssertTrue(controller.isTrackingShift)

        controller.noteKeyDown(systemShiftIsPressed: false)
        XCTAssertFalse(controller.isTrackingShift)

        XCTAssertFalse(press(.left, on: &controller))
        XCTAssertTrue(release(.left, on: &controller))
    }

    func testDuplicateShiftDownFollowedByLetterRemainsAChord() {
        var controller = ShiftToggleController()

        XCTAssertFalse(press(.left, on: &controller))
        XCTAssertFalse(press(.left, on: &controller))
        controller.noteKeyDown(systemShiftIsPressed: true)

        XCTAssertFalse(release(.left, on: &controller))
    }

    func testShiftModifiedArrowDoesNotToggle() {
        var controller = ShiftToggleController()

        _ = press(.right, on: &controller)
        controller.noteKeyDown(systemShiftIsPressed: true)
        XCTAssertFalse(release(.right, on: &controller))
    }

    func testShiftModifiedNumberDoesNotToggle() {
        var controller = ShiftToggleController()

        _ = press(.left, on: &controller)
        controller.noteKeyDown(systemShiftIsPressed: true)
        XCTAssertFalse(release(.left, on: &controller))
    }

    func testSystemKeyDownCounterRejectsAChordDeliveredAfterShiftRelease() {
        var controller = ShiftToggleController()

        XCTAssertFalse(
            controller.handleFlagsChanged(
                keyCode: UInt16(kVK_Shift),
                modifierFlags: .shift,
                systemKeyDownEventCount: 40,
                systemShiftIsPressed: true
            )
        )
        // Microsoft Word can expose this ordering to the input method: the
        // WindowServer has already seen Shift+9, but the controller receives
        // Shift-up before the 9 key-down callback. It is still a chord.
        XCTAssertFalse(
            controller.handleFlagsChanged(
                keyCode: UInt16(kVK_Shift),
                modifierFlags: [],
                systemKeyDownEventCount: 41,
                systemShiftIsPressed: false
            )
        )
    }

    func testUnchangedSystemKeyDownCounterStillAllowsStandaloneShift() {
        var controller = ShiftToggleController()

        XCTAssertFalse(
            controller.handleFlagsChanged(
                keyCode: UInt16(kVK_Shift),
                modifierFlags: .shift,
                systemKeyDownEventCount: 80,
                systemShiftIsPressed: true
            )
        )
        XCTAssertTrue(
            controller.handleFlagsChanged(
                keyCode: UInt16(kVK_Shift),
                modifierFlags: [],
                systemKeyDownEventCount: 80,
                systemShiftIsPressed: false
            )
        )
    }

    func testAnotherModifierInterruptsStandaloneShift() {
        var controller = ShiftToggleController()

        _ = press(.left, on: &controller)
        XCTAssertFalse(
            controller.handleFlagsChanged(
                keyCode: UInt16(kVK_Command),
                modifierFlags: [.shift, .command],
                systemShiftIsPressed: true
            )
        )
        XCTAssertFalse(release(.left, on: &controller))
    }

    func testModifierHeldBeforeShiftDoesNotToggle() {
        let modifiers: [NSEvent.ModifierFlags] = [
            .command,
            .control,
            .function,
            .option
        ]

        for modifier in modifiers {
            var controller = ShiftToggleController()
            XCTAssertFalse(
                controller.handleFlagsChanged(
                    keyCode: UInt16(kVK_Shift),
                    modifierFlags: [.shift, modifier],
                    systemShiftIsPressed: true
                )
            )
            XCTAssertFalse(
                controller.handleFlagsChanged(
                    keyCode: UInt16(kVK_Shift),
                    modifierFlags: modifier,
                    systemShiftIsPressed: false
                )
            )
        }
    }

    func testLockedCapsLockDoesNotPreventStandaloneShift() {
        var controller = ShiftToggleController()

        XCTAssertFalse(
            controller.handleFlagsChanged(
                keyCode: UInt16(kVK_Shift),
                modifierFlags: [.shift, .capsLock],
                systemShiftIsPressed: true
            )
        )
        XCTAssertTrue(
            controller.handleFlagsChanged(
                keyCode: UInt16(kVK_Shift),
                modifierFlags: .capsLock,
                systemShiftIsPressed: false
            )
        )
    }

    func testChangingCapsLockDuringShiftGestureDoesNotToggle() {
        var controller = ShiftToggleController()

        _ = press(.left, on: &controller)
        XCTAssertFalse(
            controller.handleFlagsChanged(
                keyCode: UInt16(kVK_CapsLock),
                modifierFlags: [.shift, .capsLock],
                systemShiftIsPressed: true
            )
        )
        XCTAssertFalse(
            controller.handleFlagsChanged(
                keyCode: UInt16(kVK_Shift),
                modifierFlags: .capsLock,
                systemShiftIsPressed: false
            )
        )
    }

    func testPressingBothShiftKeysDoesNotToggle() {
        var controller = ShiftToggleController()

        _ = press(.left, on: &controller)
        _ = press(.right, on: &controller)
        XCTAssertFalse(release(.right, stillHoldingShift: true, on: &controller))
        XCTAssertFalse(release(.left, on: &controller))
    }

    func testSidePreferenceIsAppliedOnRelease() {
        var leftOnly = ShiftToggleController()
        _ = press(.right, on: &leftOnly)
        XCTAssertFalse(
            release(.right, preference: .left, on: &leftOnly)
        )

        var rightOnly = ShiftToggleController()
        _ = press(.right, on: &rightOnly)
        XCTAssertTrue(
            release(.right, preference: .right, on: &rightOnly)
        )
    }

    func testEveryPreferenceAllowsOnlyItsConfiguredSides() {
        let expected: [ShiftKeyPreference: Set<ShiftKeySide>] = [
            .both: [.left, .right],
            .left: [.left],
            .right: [.right],
            .disabled: []
        ]

        for preference in ShiftKeyPreference.allCases {
            for side: ShiftKeySide in [.left, .right] {
                XCTAssertEqual(
                    preference.allows(side),
                    expected[preference, default: []].contains(side)
                )
            }
        }
    }

    func testDisabledPreferenceNeverToggles() {
        var controller = ShiftToggleController()

        _ = press(.left, on: &controller)
        XCTAssertFalse(
            release(.left, preference: .disabled, on: &controller)
        )
    }

    func testLoneReleaseAfterActivationDoesNotToggle() {
        var controller = ShiftToggleController()

        XCTAssertFalse(release(.left, on: &controller))
    }

    func testResetClearsAnInterruptedGesture() {
        var controller = ShiftToggleController()

        _ = press(.left, on: &controller)
        controller.reset()
        XCTAssertFalse(release(.left, on: &controller))

        _ = press(.left, on: &controller)
        XCTAssertTrue(release(.left, on: &controller))
    }

    func testLanguageModeControllerAlternatesModes() {
        let modeController = LanguageModeController(initialMode: .chinese)

        XCTAssertEqual(modeController.mode.toggled, .english)
        _ = modeController.synchronize(withSystemMode: .english)
        XCTAssertEqual(modeController.mode.toggled, .chinese)
    }

    func testLanguageModesHaveStableInputSourceIdentifiers() {
        let parentID = "tw.idv.example.inputmethod.demo"

        XCTAssertEqual(
            LanguageMode.chinese.inputSourceID(parentID: parentID),
            "tw.idv.example.inputmethod.demo.Chinese"
        )
        XCTAssertEqual(
            LanguageMode.english.inputSourceID(parentID: parentID),
            "tw.idv.example.inputmethod.demo.English"
        )
        XCTAssertEqual(
            LanguageMode.mode(
                forInputSourceID: "tw.idv.example.inputmethod.demo.English",
                parentID: parentID
            ),
            .english
        )
        XCTAssertNil(
            LanguageMode.mode(
                forInputSourceID: "com.apple.keylayout.US",
                parentID: parentID
            )
        )
    }

    func testLanguageModeControllerCanSynchronizeWithSystemMode() {
        let modeController = LanguageModeController(initialMode: .chinese)

        XCTAssertEqual(
            modeController.synchronize(withSystemMode: .english),
            .english
        )
        XCTAssertEqual(modeController.mode, .english)
    }

    func testIndependentGestureTrackersCanDriveOneLanguageMode() {
        var firstClient = ShiftToggleController()
        var secondClient = ShiftToggleController()
        let modeController = LanguageModeController(initialMode: .chinese)

        _ = press(.left, on: &firstClient)
        if release(.left, on: &firstClient) {
            modeController.synchronize(
                withSystemMode: modeController.mode.toggled
            )
        }
        XCTAssertEqual(modeController.mode, .english)

        _ = press(.right, on: &secondClient)
        if release(.right, on: &secondClient) {
            modeController.synchronize(
                withSystemMode: modeController.mode.toggled
            )
        }
        XCTAssertEqual(modeController.mode, .chinese)
    }

    private func press(
        _ side: ShiftKeySide,
        on controller: inout ShiftToggleController
    ) -> Bool {
        controller.handleFlagsChanged(
            keyCode: keyCode(for: side),
            modifierFlags: [.shift, side.deviceModifierFlag],
            systemShiftIsPressed: true
        )
    }

    private func release(
        _ side: ShiftKeySide,
        stillHoldingShift: Bool = false,
        preference: ShiftKeyPreference = .both,
        on controller: inout ShiftToggleController
    ) -> Bool {
        let heldFlags: NSEvent.ModifierFlags
        if stillHoldingShift {
            let otherSide: ShiftKeySide = side == .left ? .right : .left
            heldFlags = [.shift, otherSide.deviceModifierFlag]
        } else {
            heldFlags = []
        }
        return controller.handleFlagsChanged(
            keyCode: keyCode(for: side),
            modifierFlags: heldFlags,
            preference: preference,
            systemShiftIsPressed: stillHoldingShift
        )
    }

    private func keyCode(for side: ShiftKeySide) -> UInt16 {
        switch side {
        case .left:
            return UInt16(kVK_Shift)
        case .right:
            return UInt16(kVK_RightShift)
        }
    }
}
