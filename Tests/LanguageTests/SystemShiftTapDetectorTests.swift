import XCTest

final class SystemShiftTapDetectorTests: XCTestCase {
    func testStandaloneLeftTapIsRecognizedAtRelease() {
        var keyboard = KeyboardTimeline()
        var detector = SystemShiftTapDetector()

        XCTAssertNil(detector.ingest(keyboard.idle()))
        XCTAssertNil(detector.ingest(keyboard.press(.left)))
        XCTAssertNil(detector.ingest(keyboard.hold()))
        XCTAssertEqual(
            detector.ingest(keyboard.release()),
            SystemShiftTap(side: .left, releaseTime: keyboard.lastChange)
        )
    }

    func testStandaloneRightTapReportsRightSide() {
        var keyboard = KeyboardTimeline()
        var detector = SystemShiftTapDetector()

        _ = detector.ingest(keyboard.idle())
        _ = detector.ingest(keyboard.press(.right))
        XCTAssertEqual(detector.ingest(keyboard.release())?.side, .right)
    }

    func testTapShorterThanOneIntervalIsNotSeen() {
        var keyboard = KeyboardTimeline()
        var detector = SystemShiftTapDetector()

        _ = detector.ingest(keyboard.idle())
        // Press and release both landed between two samples: the state never
        // showed Shift down, so there is nothing to recover.
        keyboard.flagsChanged += 2
        XCTAssertNil(detector.ingest(keyboard.idle()))
    }

    func testKeyTypedWhileShiftHeldIsAChord() {
        var keyboard = KeyboardTimeline()
        var detector = SystemShiftTapDetector()

        _ = detector.ingest(keyboard.idle())
        _ = detector.ingest(keyboard.press(.left))
        keyboard.keyDowns += 1
        _ = detector.ingest(keyboard.hold())
        XCTAssertNil(detector.ingest(keyboard.release()))
    }

    func testKeyTypedBetweenSamplesBeforeReleaseIsAChord() {
        var keyboard = KeyboardTimeline()
        var detector = SystemShiftTapDetector()

        _ = detector.ingest(keyboard.idle())
        _ = detector.ingest(keyboard.press(.left))
        // The key-down and the Shift release landed in the same interval.
        keyboard.keyDowns += 1
        XCTAssertNil(detector.ingest(keyboard.release()))
    }

    func testKeyTypedInThePressIntervalCountsAgainstTheTap() {
        var keyboard = KeyboardTimeline()
        var detector = SystemShiftTapDetector()

        _ = detector.ingest(keyboard.idle())
        keyboard.keyDowns += 1
        _ = detector.ingest(keyboard.press(.left))
        XCTAssertNil(detector.ingest(keyboard.release()))
    }

    func testMouseClickWhileShiftHeldIsAChord() {
        var keyboard = KeyboardTimeline()
        var detector = SystemShiftTapDetector()

        _ = detector.ingest(keyboard.idle())
        _ = detector.ingest(keyboard.press(.left))
        keyboard.mouseDowns += 1
        _ = detector.ingest(keyboard.hold())
        XCTAssertNil(detector.ingest(keyboard.release()))
    }

    func testOtherModifierHeldWithShiftIsAChord() {
        var keyboard = KeyboardTimeline()
        var detector = SystemShiftTapDetector()

        _ = detector.ingest(keyboard.idle())
        _ = detector.ingest(keyboard.press(.left))
        keyboard.flagsChanged += 1
        _ = detector.ingest(keyboard.hold(otherModifier: true))
        keyboard.flagsChanged += 1
        _ = detector.ingest(keyboard.hold())
        XCTAssertNil(detector.ingest(keyboard.release()))
    }

    func testOtherModifierAlreadyHeldAtPressIsAChord() {
        var keyboard = KeyboardTimeline()
        var detector = SystemShiftTapDetector()

        _ = detector.ingest(keyboard.idle(otherModifier: true))
        _ = detector.ingest(keyboard.press(.left, otherModifier: true))
        XCTAssertNil(detector.ingest(keyboard.release(otherModifier: true)))
    }

    func testModifierTappedBetweenSamplesIsAChord() {
        var keyboard = KeyboardTimeline()
        var detector = SystemShiftTapDetector()

        _ = detector.ingest(keyboard.idle())
        _ = detector.ingest(keyboard.press(.left))
        // A Command press and release fitted between two samples; only the
        // session counter saw it.
        keyboard.flagsChanged += 2
        _ = detector.ingest(keyboard.hold())
        XCTAssertNil(detector.ingest(keyboard.release()))
    }

    func testBothShiftKeysDoNotTap() {
        var keyboard = KeyboardTimeline()
        var detector = SystemShiftTapDetector()

        _ = detector.ingest(keyboard.idle())
        _ = detector.ingest(keyboard.press(.left))
        _ = detector.ingest(keyboard.sample(left: true, right: true))
        _ = detector.ingest(keyboard.sample(left: true, right: false))
        XCTAssertNil(detector.ingest(keyboard.release()))
    }

    func testShiftHeldWhenPollingStartsIsNotATap() {
        var keyboard = KeyboardTimeline()
        var detector = SystemShiftTapDetector()

        XCTAssertNil(detector.ingest(keyboard.sample(left: true, right: false)))
        XCTAssertNil(detector.ingest(keyboard.release()))
    }

    func testResetForgetsAHeldShift() {
        var keyboard = KeyboardTimeline()
        var detector = SystemShiftTapDetector()

        _ = detector.ingest(keyboard.idle())
        _ = detector.ingest(keyboard.press(.left))
        detector.reset()
        XCTAssertNil(detector.ingest(keyboard.hold()))
        XCTAssertNil(detector.ingest(keyboard.release()))
    }

    func testChordDoesNotPoisonTheNextTap() {
        var keyboard = KeyboardTimeline()
        var detector = SystemShiftTapDetector()

        _ = detector.ingest(keyboard.idle())
        _ = detector.ingest(keyboard.press(.left))
        keyboard.keyDowns += 1
        XCTAssertNil(detector.ingest(keyboard.release()))

        _ = detector.ingest(keyboard.idle())
        _ = detector.ingest(keyboard.press(.left))
        XCTAssertNotNil(detector.ingest(keyboard.release()))
    }

    func testCountersWrapAround() {
        var keyboard = KeyboardTimeline()
        keyboard.flagsChanged = .max
        var detector = SystemShiftTapDetector()

        _ = detector.ingest(keyboard.idle())
        _ = detector.ingest(keyboard.press(.left))
        XCTAssertNotNil(detector.ingest(keyboard.release()))
    }
}

/// Builds samples the way polling observes a keyboard: every Shift transition
/// also advances the session's modifier-change counter.
private struct KeyboardTimeline {
    var time: TimeInterval = 100
    private(set) var lastChange: TimeInterval = 90
    var keyDowns: UInt32 = 10
    var mouseDowns: UInt32 = 3
    var flagsChanged: UInt32 = 40
    private var left = false
    private var right = false

    mutating func idle(otherModifier: Bool = false) -> SystemKeyboardSample {
        sample(left: false, right: false, otherModifier: otherModifier)
    }

    mutating func press(
        _ side: ShiftKeySide,
        otherModifier: Bool = false
    ) -> SystemKeyboardSample {
        sample(
            left: side == .left,
            right: side == .right,
            otherModifier: otherModifier
        )
    }

    mutating func hold(otherModifier: Bool = false) -> SystemKeyboardSample {
        sample(left: left, right: right, otherModifier: otherModifier)
    }

    mutating func release(otherModifier: Bool = false) -> SystemKeyboardSample {
        sample(left: false, right: false, otherModifier: otherModifier)
    }

    mutating func sample(
        left: Bool,
        right: Bool,
        otherModifier: Bool = false
    ) -> SystemKeyboardSample {
        time += 0.015
        if left != self.left || right != self.right {
            // The change happened somewhere inside the interval, before the
            // poll noticed it.
            lastChange = time - 0.009
        }
        if left != self.left {
            flagsChanged &+= 1
        }
        if right != self.right {
            flagsChanged &+= 1
        }
        self.left = left
        self.right = right
        return SystemKeyboardSample(
            lastModifierChangeTime: lastChange,
            leftShiftDown: left,
            rightShiftDown: right,
            otherModifierDown: otherModifier,
            keyDownCount: keyDowns,
            mouseDownCount: mouseDowns,
            flagsChangedCount: flagsChanged
        )
    }
}
