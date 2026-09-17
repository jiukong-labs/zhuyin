import XCTest

final class ShiftToggleArbiterTests: XCTestCase {
    func testFallbackSwitchesWhenTheClientNeverReportsTheTap() {
        var arbiter = ShiftToggleArbiter()
        let tap = SystemShiftTap(side: .left, releaseTime: 50)

        arbiter.fallbackObserved(tap)
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.05), [])
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.13), [tap])
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 51), [])
    }

    func testClientConclusionBeforeTheSampleSuppressesTheFallback() {
        var arbiter = ShiftToggleArbiter()

        XCTAssertTrue(arbiter.clientPathConcludedGesture(releasedAt: 50))
        arbiter.fallbackObserved(SystemShiftTap(side: .left, releaseTime: 50.012))
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.2), [])
    }

    func testLateClientConclusionCancelsAPendingFallback() {
        var arbiter = ShiftToggleArbiter()

        arbiter.fallbackObserved(SystemShiftTap(side: .left, releaseTime: 50.012))
        XCTAssertTrue(arbiter.clientPathConcludedGesture(releasedAt: 50))
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.2), [])
    }

    func testClientChordDecisionAlsoSuppressesTheFallback() {
        var arbiter = ShiftToggleArbiter()

        // The event path concludes a gesture whether it switches or rejects it
        // as a chord; either way the fallback must defer to it.
        _ = arbiter.clientPathConcludedGesture(releasedAt: 50)
        arbiter.fallbackObserved(SystemShiftTap(side: .left, releaseTime: 50.01))
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.3), [])
    }

    func testClientEventArrivingAfterTheFallbackSwitchedMustNotSwitchAgain() {
        var arbiter = ShiftToggleArbiter()
        let tap = SystemShiftTap(side: .right, releaseTime: 50.012)

        arbiter.fallbackObserved(tap)
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.14), [tap])
        XCTAssertFalse(arbiter.clientPathConcludedGesture(releasedAt: 50))
    }

    func testSeparateTapsAreJudgedIndependently() {
        var arbiter = ShiftToggleArbiter()
        let dropped = SystemShiftTap(side: .left, releaseTime: 51)

        XCTAssertTrue(arbiter.clientPathConcludedGesture(releasedAt: 50))
        arbiter.fallbackObserved(SystemShiftTap(side: .left, releaseTime: 50.01))
        arbiter.fallbackObserved(dropped)

        XCTAssertEqual(arbiter.dueFallbackTaps(now: 51.2), [dropped])
        XCTAssertTrue(arbiter.clientPathConcludedGesture(releasedAt: 52))
    }

    func testStaleTapIsDroppedWhenPollingResumesLate() {
        var arbiter = ShiftToggleArbiter()

        arbiter.fallbackObserved(SystemShiftTap(side: .left, releaseTime: 50))
        // Focus left before the tap was due; polling resumes much later.
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 58), [])
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 58.2), [])
    }
}
