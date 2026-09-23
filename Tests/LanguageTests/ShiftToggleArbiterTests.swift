import XCTest

final class ShiftToggleArbiterTests: XCTestCase {
    func testObservedReleaseCounterCancelsLINEFallbackDespiteDisjointTimestamps() {
        var arbiter = ShiftToggleArbiter()
        // The incident's release times differ by 45.5 ms. The press time is
        // deliberately after the physical release, covering fully delayed
        // client delivery without assuming that the two intervals overlap.
        let polled = makeTap(
            side: .right, press: 28848.99, release: 28849.0708,
            releaseCounter: 178
        )
        let client = makeTap(side: .right, press: 28849.101, release: 28849.1163)

        arbiter.fallbackObserved(polled)
        XCTAssertTrue(conclude(client, observedReleaseCounter: 178, on: &arbiter))
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 28849.21), [])
    }

    func testObservedReleaseCounterSuppressesDelayedClientAfterFallbackSwitched() {
        var arbiter = ShiftToggleArbiter()
        let polled = makeTap(press: 49.92, release: 50, releaseCounter: 178)
        let client = makeTap(press: 50.03, release: 50.0455)

        arbiter.fallbackObserved(polled)
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.13), [polled])
        XCTAssertFalse(conclude(client, observedReleaseCounter: 178, on: &arbiter))
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.2), [])
    }

    func testClientCounterConclusionSuppressesALaterPolledTapWithDisjointTimestamps() {
        var arbiter = ShiftToggleArbiter()
        let client = makeTap(press: 50.03, release: 50.0455)
        let polled = makeTap(press: 49.92, release: 50, releaseCounter: 178)

        // The client has handled both delayed callbacks before the timer
        // gets another opportunity to observe the physical release.
        XCTAssertTrue(conclude(client, observedReleaseCounter: 178, on: &arbiter))
        arbiter.fallbackObserved(polled)
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.14), [])
    }

    func testLatePolledCounterDoesNotChooseBetweenUnpairedClientConclusions() {
        var arbiter = ShiftToggleArbiter()
        let firstClient = makeTap(press: 49.7, release: 49.76)
        let secondClient = makeTap(press: 50.03, release: 50.0455)
        let polled = makeTap(press: 49.92, release: 50, releaseCounter: 178)

        XCTAssertTrue(conclude(firstClient, observedReleaseCounter: 176, on: &arbiter))
        XCTAssertTrue(conclude(secondClient, observedReleaseCounter: 178, on: &arbiter))
        arbiter.fallbackObserved(polled)
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.14), [polled])
    }

    func testCounterOnlyClientRejectionAllowsOneLaterPolledRecoveryDespiteTimestampDrift() {
        var arbiter = ShiftToggleArbiter()
        let client = makeTap(press: 50.03, release: 50.0455)
        let polled = makeTap(press: 49.92, release: 50, releaseCounter: 178)

        XCTAssertTrue(conclude(
            client, allowingRecovery: true, observedReleaseCounter: 178, on: &arbiter
        ))
        arbiter.fallbackObserved(polled)
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.14), [polled])
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.2), [])
        XCTAssertFalse(conclude(
            client, allowingRecovery: true, observedReleaseCounter: 178, on: &arbiter
        ))
    }

    func testDifferentCounterPreservesAQuickSecondClientTap() {
        var arbiter = ShiftToggleArbiter()
        let first = makeTap(press: 49.92, release: 50, releaseCounter: 178)
        let second = makeTap(press: 50.03, release: 50.07)

        arbiter.fallbackObserved(first)
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.13), [first])
        XCTAssertTrue(conclude(second, observedReleaseCounter: 180, on: &arbiter))
    }

    func testOlderClientTapCannotClaimANewerPendingTapUsingItsObservedCounter() {
        var arbiter = ShiftToggleArbiter()
        let olderClient = makeTap(press: 49.865, release: 49.945)
        let newerPolled = makeTap(press: 49.96, release: 50.04, releaseCounter: 180)

        // Polling missed the first tap during activation. Its delayed client
        // callbacks both see the counter after a second, polling-only tap.
        arbiter.fallbackObserved(newerPolled)
        XCTAssertTrue(conclude(olderClient, observedReleaseCounter: 180, on: &arbiter))
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.18), [newerPolled])
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.25), [])
    }

    func testOlderClientCounterCannotSuppressANewerTapObservedAfterItsConclusion() {
        var arbiter = ShiftToggleArbiter()
        let olderClient = makeTap(press: 49.865, release: 49.945)
        let newerPolled = makeTap(press: 49.96, release: 50.04, releaseCounter: 180)

        // The same two physical taps must each switch when the delayed
        // client callbacks run before the timer observes the second release.
        XCTAssertTrue(conclude(olderClient, observedReleaseCounter: 180, on: &arbiter))
        arbiter.fallbackObserved(newerPolled)
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.18), [newerPolled])
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.25), [])
    }

    func testCounterDoesNotChooseBetweenTwoUnpairedPendingTaps() {
        var arbiter = ShiftToggleArbiter()
        let first = makeTap(release: 49.9, releaseCounter: 176)
        let second = makeTap(release: 50, releaseCounter: 178)
        let client = makeTap(press: 50.03, release: 50.0455)

        arbiter.fallbackObserved(first)
        arbiter.fallbackObserved(second)
        XCTAssertTrue(conclude(client, observedReleaseCounter: 178, on: &arbiter))
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.14), [first, second])
    }

    func testCounterDoesNotChooseBetweenSwitchedAndPendingUnpairedTaps() {
        var arbiter = ShiftToggleArbiter()
        let first = makeTap(release: 49.85, releaseCounter: 176)
        let second = makeTap(release: 50, releaseCounter: 178)
        let client = makeTap(press: 50.03, release: 50.0455)

        arbiter.fallbackObserved(first)
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 49.98), [first])
        arbiter.fallbackObserved(second)
        XCTAssertTrue(conclude(client, observedReleaseCounter: 178, on: &arbiter))
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.14), [second])
    }

    func testCounterMatchStillRequiresTheSameShiftSide() {
        var arbiter = ShiftToggleArbiter()
        let right = makeTap(side: .right, release: 50, releaseCounter: 178)
        let left = makeTap(side: .left, press: 50.03, release: 50.0455)

        arbiter.fallbackObserved(right)
        XCTAssertTrue(conclude(left, observedReleaseCounter: 178, on: &arbiter))
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.14), [right])
    }

    func testMissingOrDifferentCountersDoNotExpandTimestampMatching() {
        let counters: [(UInt32?, UInt32?)] = [
            (nil, nil), (nil, 178), (178, nil), (178, 180)
        ]
        for (polledCounter, clientCounter) in counters {
            var arbiter = ShiftToggleArbiter()
            let polled = makeTap(release: 50, releaseCounter: polledCounter)
            let client = makeTap(press: 50.03, release: 50.0455)

            arbiter.fallbackObserved(polled)
            XCTAssertTrue(conclude(
                client, observedReleaseCounter: clientCounter, on: &arbiter
            ))
            XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.14), [polled])
        }
    }

    func testMatchingCounterCannotClaimAnExpiredFallbackToggle() {
        var arbiter = ShiftToggleArbiter()
        let polled = makeTap(release: 50, releaseCounter: 178)
        let client = makeTap(press: 50.58, release: 50.65)

        arbiter.fallbackObserved(polled)
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.13), [polled])
        XCTAssertTrue(conclude(client, observedReleaseCounter: 178, on: &arbiter))
    }

    func testCounterMatchedFallbackCannotBeClaimedByAnotherClientGesture() {
        var arbiter = ShiftToggleArbiter()
        let polled = makeTap(release: 50, releaseCounter: 178)
        let first = makeTap(press: 50.03, release: 50.0455)
        let second = makeTap(press: 50.07, release: 50.085)

        arbiter.fallbackObserved(polled)
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.13), [polled])
        XCTAssertFalse(conclude(first, observedReleaseCounter: 178, on: &arbiter))
        XCTAssertTrue(conclude(second, observedReleaseCounter: 178, on: &arbiter))
    }

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

    func testClientPressTrailingTheSampleStillMatchesOnePhysicalTap() {
        // Chrome, 2026-09-23 13:41:07: the client concluded first with a press
        // 49.7 ms after the sampled one, and the fallback switched back.
        var arbiter = ShiftToggleArbiter()
        let client = makeTap(side: .right, press: 76580.9039, release: 76580.9628)
        let polled = makeTap(side: .right, press: 76580.8542, release: 76580.9601)

        XCTAssertTrue(conclude(client, on: &arbiter))
        arbiter.fallbackObserved(polled)
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 76581.2), [])
    }

    func testTrailingClientConclusionCancelsAPendingFallback() {
        // 13:41:08: the sample came first; the client press trailed by 29 ms.
        var arbiter = ShiftToggleArbiter()
        let polled = makeTap(side: .right, press: 76582.1683, release: 76582.2428)
        let client = makeTap(side: .right, press: 76582.1977, release: 76582.2472)

        arbiter.fallbackObserved(polled)
        XCTAssertTrue(conclude(client, on: &arbiter))
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 76582.5), [])
    }

    func testClientReleaseTrailingTheSampleStillMatches() {
        // 11:26:41: the client release trailed by 33.1 ms.
        var arbiter = ShiftToggleArbiter()
        let polled = makeTap(side: .right, press: 68515.4418, release: 68515.5610)
        let client = makeTap(side: .right, press: 68515.4472, release: 68515.5941)

        arbiter.fallbackObserved(polled)
        XCTAssertTrue(conclude(client, on: &arbiter))
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 68515.8), [])
    }

    func testTrailingClientEventAfterTheFallbackSwitchedMustNotSwitchAgain() {
        // The 74.3 ms press lag measured at 12:04:18, arriving after the
        // fallback has already switched.
        var arbiter = ShiftToggleArbiter()
        let polled = makeTap(side: .right, press: 70772.7465, release: 70772.8529)
        let client = makeTap(side: .right, press: 70772.8208, release: 70772.8553)

        arbiter.fallbackObserved(polled)
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 70772.98), [polled])
        XCTAssertFalse(conclude(client, on: &arbiter))
    }

    func testClientReleaseLeadingTheSampleBeyondToleranceDoesNotMatch() {
        var arbiter = ShiftToggleArbiter()
        let polled = makeTap(press: 49.92, release: 50)

        XCTAssertTrue(conclude(makeTap(press: 49.92, release: 49.97), on: &arbiter))
        arbiter.fallbackObserved(polled)
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.2), [polled])
    }

    func testClientReleaseTrailingBeyondTheLagWindowDoesNotMatch() {
        var arbiter = ShiftToggleArbiter()
        let polled = makeTap(press: 49.9, release: 50)

        XCTAssertTrue(conclude(makeTap(press: 49.95, release: 50.06), on: &arbiter))
        arbiter.fallbackObserved(polled)
        XCTAssertEqual(arbiter.dueFallbackTaps(now: 50.2), [polled])
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
        release: TimeInterval,
        releaseCounter: UInt32? = nil
    ) -> SystemShiftTap {
        SystemShiftTap(
            side: side,
            pressTime: press ?? release - 0.08,
            releaseTime: release,
            releaseCounter: releaseCounter
        )
    }

    private func conclude(
        _ tap: SystemShiftTap,
        allowingRecovery: Bool = false,
        observedReleaseCounter: UInt32? = nil,
        on arbiter: inout ShiftToggleArbiter
    ) -> Bool {
        arbiter.clientPathConcludedGesture(
            pressedAt: tap.pressTime,
            releasedAt: tap.releaseTime,
            side: tap.side,
            allowFallbackRecovery: allowingRecovery,
            observedReleaseCounter: observedReleaseCounter
        )
    }
}
