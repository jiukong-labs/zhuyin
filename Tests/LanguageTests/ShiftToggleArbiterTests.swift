import XCTest

final class ShiftToggleArbiterTests: XCTestCase {
    func testFallbackSwitchesWhenTheClientNeverReportsTheTap() {
        var arbiter = ShiftToggleArbiter()
        let tap = makeTap(release: 50)

        arbiter.fallbackObserved(tap)
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.05), [])
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.13), [tap])
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 51), [])
    }

    func testClientConclusionBeforeTheSampleSuppressesTheFallback() {
        var arbiter = ShiftToggleArbiter()

        XCTAssertTrue(conclude(makeTap(release: 50), on: &arbiter))
        arbiter.fallbackObserved(makeTap(release: 50.012))
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.2), [])
    }

    func testLateClientConclusionCancelsAPendingFallback() {
        var arbiter = ShiftToggleArbiter()

        arbiter.fallbackObserved(makeTap(release: 50.012))
        XCTAssertTrue(conclude(makeTap(release: 50), on: &arbiter))
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.2), [])
    }

    func testClientChordDecisionAlsoSuppressesTheFallback() {
        var arbiter = ShiftToggleArbiter()

        _ = conclude(makeTap(release: 50), on: &arbiter)
        arbiter.fallbackObserved(makeTap(release: 50.01))
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.3), [])
    }

    func testClientEventArrivingAfterTheFallbackSwitchedMustNotSwitchAgain() {
        var arbiter = ShiftToggleArbiter()
        let tap = makeTap(side: .right, release: 50.012)

        arbiter.fallbackObserved(tap)
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.14), [tap])
        XCTAssertFalse(conclude(makeTap(side: .right, release: 50), on: &arbiter))
    }

    func testMeasuredTimestampDriftStillMatchesOnePhysicalTap() {
        var arbiter = ShiftToggleArbiter()
        let polled = makeTap(release: 151195.0014)
        let client = makeTap(release: 151195.0160)

        arbiter.fallbackObserved(polled)
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 151195.13), [polled])
        XCTAssertFalse(conclude(client, on: &arbiter))
    }

    func testSeparateTapsAreJudgedIndependently() {
        var arbiter = ShiftToggleArbiter()
        let dropped = makeTap(release: 51)

        XCTAssertTrue(conclude(makeTap(release: 50), on: &arbiter))
        arbiter.fallbackObserved(makeTap(release: 50.01))
        arbiter.fallbackObserved(dropped)

        XCTAssertEqual(arbiter.dueFallbackTaps(now: 51.2), [dropped])
        XCTAssertTrue(conclude(makeTap(release: 52), on: &arbiter))
    }

    func testSecondTapWithinTheFormerMatchWindowStillSwitches() {
        var arbiter = ShiftToggleArbiter()
        let first = makeTap(release: 50)

        arbiter.fallbackObserved(first)
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.121), [first])
        XCTAssertTrue(conclude(makeTap(release: 50.14), on: &arbiter))
    }

    func testNonoverlappingGesturesNeverMatchEvenInsideTimestampTolerance() {
        var arbiter = ShiftToggleArbiter()
        let first = makeTap(press: 49.990, release: 50)
        let second = makeTap(press: 50.001, release: 50.011)

        XCTAssertTrue(conclude(first, on: &arbiter))
        arbiter.fallbackObserved(second)
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.14), [second])
    }

    func testOppositeSidesDoNotMatch() {
        var arbiter = ShiftToggleArbiter()
        let right = makeTap(side: .right, release: 50.01)

        XCTAssertTrue(conclude(makeTap(side: .left, release: 50), on: &arbiter))
        arbiter.fallbackObserved(right)
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.2), [right])
    }

    func testBothEdgesMustMatch() {
        var arbiter = ShiftToggleArbiter()
        let polled = makeTap(press: 49.9, release: 50)

        XCTAssertTrue(conclude(makeTap(press: 49.7, release: 50), on: &arbiter))
        arbiter.fallbackObserved(polled)
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.2), [polled])
    }

    func testAClientConclusionCanClaimOnlyOneFallbackGesture() {
        var arbiter = ShiftToggleArbiter()
        let first = makeTap(press: 49.96, release: 50)
        let client = makeTap(press: 49.975, release: 50.015)
        let second = makeTap(press: 49.990, release: 50.03)

        XCTAssertTrue(conclude(client, on: &arbiter))
        arbiter.fallbackObserved(first)
        arbiter.fallbackObserved(second)
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.2), [second])
    }

    func testAFallbackToggleCanClaimOnlyOneClientGesture() {
        var arbiter = ShiftToggleArbiter()
        let polled = makeTap(press: 49.975, release: 50.015)

        arbiter.fallbackObserved(polled)
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.2), [polled])
        XCTAssertFalse(conclude(makeTap(press: 49.96, release: 50), on: &arbiter))
        XCTAssertTrue(conclude(makeTap(press: 49.990, release: 50.03), on: &arbiter))
    }

    func testDuplicateReportsCannotSwitchTwice() {
        var arbiter = ShiftToggleArbiter()
        let tap = makeTap(release: 50)

        arbiter.fallbackObserved(tap)
        arbiter.fallbackObserved(tap)
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.13), [tap])
        arbiter.fallbackObserved(tap)
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.2), [])
        XCTAssertFalse(conclude(tap, on: &arbiter))
        XCTAssertFalse(conclude(tap, on: &arbiter))
    }

    func testDuplicateClientReportsCannotSwitchTwice() {
        var arbiter = ShiftToggleArbiter()
        let tap = makeTap(release: 50)

        XCTAssertTrue(conclude(tap, on: &arbiter))
        XCTAssertFalse(conclude(tap, on: &arbiter))
    }

    func testCounterOnlyRejectionPreservesAnAlreadyConfirmedTap() {
        var arbiter = ShiftToggleArbiter()
        let tap = makeTap(release: 50)

        arbiter.fallbackObserved(tap)
        XCTAssertTrue(conclude(tap, allowingRecovery: true, on: &arbiter))
        XCTAssertEqual(
            arbiter.dueFallbackTaps(beforeKeyDownAt: 50.01, now: 50.02),
            [tap]
        )
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.2), [])
    }

    func testCounterOnlyRejectionAllowsALaterStateSample() {
        var arbiter = ShiftToggleArbiter()
        let tap = makeTap(release: 50)

        XCTAssertTrue(conclude(tap, allowingRecovery: true, on: &arbiter))
        arbiter.fallbackObserved(tap)
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.13), [tap])
        XCTAssertFalse(conclude(tap, allowingRecovery: true, on: &arbiter))
    }

    func testKeyDownFlushesConfirmedEarlierTapWithoutWaitingForDelay() {
        var arbiter = ShiftToggleArbiter()
        let tap = makeTap(release: 50)

        arbiter.fallbackObserved(tap)
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.01), [])
        XCTAssertEqual(
            arbiter.dueFallbackTaps(beforeKeyDownAt: 50.02, now: 50.03),
            [tap]
        )
        XCTAssertFalse(conclude(tap, on: &arbiter))
    }

    func testKeyDownDoesNotFlushALaterTap() {
        var arbiter = ShiftToggleArbiter()
        let tap = makeTap(release: 50)

        arbiter.fallbackObserved(tap)
        XCTAssertEqual(
            arbiter.dueFallbackTaps(beforeKeyDownAt: 49.99, now: 50.03),
            []
        )
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.13), [tap])
    }

    func testKeyDownFlushUsesCurrentTimeForExpiry() {
        var arbiter = ShiftToggleArbiter()

        arbiter.fallbackObserved(makeTap(release: 50))
        XCTAssertEqual(
            arbiter.dueFallbackTaps(beforeKeyDownAt: 50.01, now: 51),
            []
        )
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 51.1), [])
    }

    func testStaleTapIsDroppedWhenPollingResumesLate() {
        var arbiter = ShiftToggleArbiter()

        arbiter.fallbackObserved(makeTap(release: 50))
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 58), [])
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 58.2), [])
    }

    func testFocusChangeCancelsPendingTaps() {
        var arbiter = ShiftToggleArbiter()

        arbiter.fallbackObserved(makeTap(release: 50))
        arbiter.cancelPendingTaps()
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.2), [])
    }

    func testFocusChangeKeepsTheMemoryOfAnAlreadySwitchedTap() {
        var arbiter = ShiftToggleArbiter()
        let tap = makeTap(release: 50)

        arbiter.fallbackObserved(tap)
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.13), [tap])
        arbiter.cancelPendingTaps()
        XCTAssertFalse(conclude(tap, on: &arbiter))
    }

    private func makeTap(
        side: ShiftKeySide = .left,
        press: TimeInterval? = nil,
        release: TimeInterval
    ) -> SystemShiftTap {
        SystemShiftTap(
            side: side,
            pressTime: press ?? release - 0.08,
            releaseTime: release
        )
    }

    private func conclude(
        _ tap: SystemShiftTap,
        allowingRecovery: Bool = false,
        on arbiter: inout ShiftToggleArbiter
    ) -> Bool {
        arbiter.clientPathConcludedGesture(
            pressedAt: tap.pressTime,
            releasedAt: tap.releaseTime,
            side: tap.side,
            allowFallbackRecovery: allowingRecovery
        )
    }
}
