import AppKit
import Carbon
import XCTest

final class ShiftToggleControllerTests: XCTestCase {
    func testRecoveredMissingReleaseDoesNotPoisonTheNextTapIdentity() throws {
        var controller = ShiftToggleController()
        var arbiter = ShiftToggleArbiter()
        _ = controller.handleFlagsChanged(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [.shift, ShiftKeySide.left.deviceModifierFlag],
            eventTimestamp: 10
        )
        // The first Shift release never reaches the event tracker.
        let first = SystemShiftTap(side: .left, pressTime: 10, releaseTime: 10.1)
        arbiter.fallbackObserved(first)
        let recovered = arbiter.dueFallbackTaps(now: 10.23)
        XCTAssertEqual(recovered, [first])
        controller.recoveredTap(releasedAt: recovered[0].releaseTime)

        _ = controller.handleFlagsChanged(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [.shift, ShiftKeySide.left.deviceModifierFlag],
            eventTimestamp: 10.3
        )
        XCTAssertTrue(controller.handleFlagsChanged(
            keyCode: UInt16(kVK_Shift), modifierFlags: [], eventTimestamp: 10.4
        ))
        let second = try XCTUnwrap(controller.concludedGesture)
        XCTAssertEqual(second.pressTime, 10.3)
        XCTAssertTrue(arbiter.clientPathConcludedGesture(
            pressedAt: second.pressTime, releasedAt: second.releaseTime, side: second.side
        ))
        arbiter.fallbackObserved(SystemShiftTap(side: .left, pressTime: 10.3, releaseTime: 10.4))
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 10.53), [])
    }

    func testRecoveringEarlierTapPreservesANewerPress() throws {
        var controller = ShiftToggleController()
        _ = controller.handleFlagsChanged(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [.shift, ShiftKeySide.left.deviceModifierFlag],
            eventTimestamp: 10.3
        )
        controller.recoveredTap(releasedAt: 10.1)
        XCTAssertTrue(controller.isTrackingShift)
        XCTAssertTrue(controller.handleFlagsChanged(
            keyCode: UInt16(kVK_Shift), modifierFlags: [], eventTimestamp: 10.4
        ))
        XCTAssertEqual(try XCTUnwrap(controller.concludedGesture).pressTime, 10.3)
    }

    func testDelayedReleaseCanRecoverFromPollingBeforeTheFollowingKey() throws {
        var controller = ShiftToggleController()
        var detector = SystemShiftTapDetector()
        var arbiter = ShiftToggleArbiter()
        let sample = SystemKeyboardSample(
            lastModifierChangeTime: 9,
            leftShiftDown: false,
            rightShiftDown: false,
            otherModifierDown: false,
            keyDownCount: 100,
            mouseDownCount: 0,
            flagsChangedCount: 200
        )
        _ = detector.ingest(sample)
        var pressed = sample
        pressed.lastModifierChangeTime = 10
        pressed.leftShiftDown = true
        pressed.flagsChangedCount = 201
        _ = detector.ingest(pressed)
        _ = controller.handleFlagsChanged(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [.shift, ShiftKeySide.left.deviceModifierFlag],
            systemKeyDownEventCount: 100,
            eventTimestamp: 10
        )

        var released = pressed
        released.lastModifierChangeTime = 10.1
        released.leftShiftDown = false
        released.flagsChangedCount = 202
        let tap = try XCTUnwrap(detector.ingest(released))
        arbiter.fallbackObserved(tap)

        // A plain key was physically pressed at 10.110; the Shift-up callback
        // at 10.120 samples a counter that already includes that later key.
        XCTAssertFalse(controller.handleFlagsChanged(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [],
            systemKeyDownEventCount: 101,
            eventTimestamp: 10.1
        ))
        let gesture = try XCTUnwrap(controller.concludedGesture)
        XCTAssertTrue(gesture.allowsFallbackRecovery)
        _ = arbiter.clientPathConcludedGesture(
            pressedAt: gesture.pressTime,
            releasedAt: gesture.releaseTime,
            side: gesture.side,
            allowFallbackRecovery: gesture.allowsFallbackRecovery
        )
        XCTAssertEqual(
            arbiter.dueFallbackTaps(beforeKeyDownAt: 10.11, now: 10.13),
            [tap]
        )
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 10.3), [])
    }

    func testDeliveredChordCannotUseCounterRecovery() throws {
        var controller = ShiftToggleController()
        _ = controller.handleFlagsChanged(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [.shift, ShiftKeySide.left.deviceModifierFlag],
            systemKeyDownEventCount: 100,
            eventTimestamp: 10
        )
        controller.noteKeyDown(systemShiftIsPressed: true)
        XCTAssertFalse(controller.handleFlagsChanged(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [],
            systemKeyDownEventCount: 101,
            eventTimestamp: 10.1
        ))
        XCTAssertFalse(try XCTUnwrap(controller.concludedGesture).allowsFallbackRecovery)
    }

    func testLateClientReleaseDoesNotUndoTapFlushedBeforeAKey() throws {
        var controller = ShiftToggleController()
        var arbiter = ShiftToggleArbiter()
        var mode = LanguageMode.english
        _ = controller.handleFlagsChanged(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [.shift, ShiftKeySide.left.deviceModifierFlag],
            systemKeyDownEventCount: 100,
            eventTimestamp: 10
        )
        arbiter.fallbackObserved(SystemShiftTap(side: .left, pressTime: 10, releaseTime: 10.1))
        for _ in arbiter.dueFallbackTaps(beforeKeyDownAt: 10.11, now: 10.12) {
            mode = mode.toggled
        }
        XCTAssertEqual(mode, .chinese)

        let shouldToggle = controller.handleFlagsChanged(
            keyCode: UInt16(kVK_Shift),
            modifierFlags: [],
            systemKeyDownEventCount: 101,
            eventTimestamp: 10.1
        )
        let gesture = try XCTUnwrap(controller.concludedGesture)
        let proceed = arbiter.clientPathConcludedGesture(
            pressedAt: gesture.pressTime,
            releasedAt: gesture.releaseTime,
            side: gesture.side,
            allowFallbackRecovery: gesture.allowsFallbackRecovery
        )
        if shouldToggle && proceed { mode = mode.toggled }
        XCTAssertFalse(proceed)
        XCTAssertEqual(mode, .chinese)
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 10.3), [])
    }

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

    // macOS reports a physical tap as a press carrying the generic and the
    // device-specific Shift bit, then a release that clears both and leaves
    // only the non-coalesced marker. That release is the shape the input
    // method actually sees, so it must decide the tap without deferring to a
    // live modifier reading that belongs to a later moment.
    private static let nonCoalescedFlag = NSEvent.ModifierFlags(
        rawValue: 0x100
    )

    func testReleaseWithoutDeviceBitsTogglesWhileSystemStillReportsShift() {
        var controller = ShiftToggleController()
        let pressFlags: NSEvent.ModifierFlags = [
            .shift,
            ShiftKeySide.left.deviceModifierFlag,
            Self.nonCoalescedFlag
        ]

        XCTAssertFalse(
            controller.handleFlagsChanged(
                keyCode: UInt16(kVK_Shift),
                modifierFlags: pressFlags,
                systemShiftIsPressed: true
            )
        )
        // A quick second tap can push Shift down again before this release is
        // handled, so the live state still reports Shift as held.
        XCTAssertTrue(
            controller.handleFlagsChanged(
                keyCode: UInt16(kVK_Shift),
                modifierFlags: Self.nonCoalescedFlag,
                systemShiftIsPressed: true
            )
        )
        XCTAssertFalse(controller.isTrackingShift)
    }

    func testEveryTapInAFastRunToggles() {
        var controller = ShiftToggleController()
        let pressFlags: NSEvent.ModifierFlags = [
            .shift,
            ShiftKeySide.left.deviceModifierFlag,
            Self.nonCoalescedFlag
        ]

        for tap in 1 ... 5 {
            XCTAssertFalse(
                controller.handleFlagsChanged(
                    keyCode: UInt16(kVK_Shift),
                    modifierFlags: pressFlags,
                    systemShiftIsPressed: true
                )
            )
            XCTAssertTrue(
                controller.handleFlagsChanged(
                    keyCode: UInt16(kVK_Shift),
                    modifierFlags: Self.nonCoalescedFlag,
                    systemShiftIsPressed: true
                ),
                "tap \(tap) did not toggle"
            )
        }
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
