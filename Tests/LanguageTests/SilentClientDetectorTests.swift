import XCTest

final class SilentClientDetectorTests: XCTestCase {
    func testUndeliveredPlainKeyAfterSwitchTriggersReattach() {
        var detector = SilentClientDetector()
        detector.switchedToChinese(at: 100)

        // A plain key at 100.5 never reaches the input method.
        let grace = SilentClientDetector.deliveryGrace
        XCTAssertFalse(detector.shouldReattach(now: 100.5 + grace - 0.01, lastPlainKeyDown: 100.5))
        XCTAssertTrue(detector.shouldReattach(now: 100.5 + grace + 0.01, lastPlainKeyDown: 100.5))
    }

    func testGraceStaysShortEnoughToLimitLeakedKeys() {
        // Every key typed while waiting reaches the client as English; at an
        // ordinary eight keys per second this bounds the leak to one key.
        XCTAssertLessThanOrEqual(SilentClientDetector.deliveryGrace, 0.1)
    }

    func testBlockedMainThreadPostponesTheDecisionOneSample() {
        var detector = SilentClientDetector()
        detector.switchedToChinese(at: 100)

        // Keys the client delivered while the main thread was blocked may
        // still be queued behind this sample.
        XCTAssertFalse(detector.shouldReattach(
            now: 100.7,
            lastPlainKeyDown: 100.5,
            mainThreadWasBusy: true
        ))
        detector.clientDeliveredKeyDown(at: 100.5, mode: .chinese)
        XCTAssertFalse(detector.isWatching)
    }

    func testBlockedMainThreadOnlyDelaysARealSilentClient() {
        var detector = SilentClientDetector()
        detector.switchedToChinese(at: 100)

        XCTAssertFalse(detector.shouldReattach(
            now: 100.7,
            lastPlainKeyDown: 100.5,
            mainThreadWasBusy: true
        ))
        XCTAssertTrue(detector.shouldReattach(now: 100.715, lastPlainKeyDown: 100.5))
    }

    func testContinuousTypingDoesNotPostponeTheReattach() {
        var detector = SilentClientDetector()
        detector.switchedToChinese(at: 100)

        // Keys every 30 ms never leave a pause as long as the grace, yet
        // none of them reached the input method; the first one has waited
        // long enough.
        XCTAssertFalse(detector.shouldReattach(now: 100.52, lastPlainKeyDown: 100.5))
        XCTAssertFalse(detector.shouldReattach(now: 100.55, lastPlainKeyDown: 100.53))
        XCTAssertTrue(detector.shouldReattach(now: 100.59, lastPlainKeyDown: 100.56))
        XCTAssertEqual(detector.firstUndeliveredKey, 100.5)
    }

    func testDeliveredKeyStopsWatching() {
        var detector = SilentClientDetector()
        detector.switchedToChinese(at: 100)

        detector.clientDeliveredKeyDown(at: 100.5, mode: .chinese)
        XCTAssertFalse(detector.isWatching)
        XCTAssertFalse(detector.shouldReattach(now: 101, lastPlainKeyDown: 100.5))
    }

    func testDeliveryHandledLateStillCountsAsDelivered() {
        var detector = SilentClientDetector()
        detector.switchedToChinese(at: 100)

        // The event's hardware time is when it was typed, even if the busy
        // main thread handled it later.
        detector.clientDeliveredKeyDown(at: 100.5, mode: .chinese)
        XCTAssertFalse(detector.shouldReattach(now: 101.2, lastPlainKeyDown: 100.5))
    }

    func testKeysTypedBeforeTheSwitchAreIgnored() {
        var detector = SilentClientDetector()
        detector.switchedToChinese(at: 100)

        XCTAssertFalse(detector.shouldReattach(now: 101, lastPlainKeyDown: 99.9))
    }

    func testNoPlainKeyMeansNoReattach() {
        var detector = SilentClientDetector()
        detector.switchedToChinese(at: 100)

        XCTAssertFalse(detector.shouldReattach(now: 105, lastPlainKeyDown: nil))
    }

    func testNotWatchingWithoutASwitch() {
        var detector = SilentClientDetector()

        XCTAssertFalse(detector.shouldReattach(now: 101, lastPlainKeyDown: 100.5))
    }

    func testWatchExpires() {
        var detector = SilentClientDetector()
        detector.switchedToChinese(at: 100)

        let late = 100 + SilentClientDetector.watchDuration + 1
        XCTAssertFalse(detector.shouldReattach(now: late, lastPlainKeyDown: late - 0.5))
        XCTAssertFalse(detector.isWatching)
    }

    func testSecondAttemptWaitsForANewUndeliveredKey() {
        var detector = SilentClientDetector()
        detector.switchedToChinese(at: 100)

        XCTAssertTrue(detector.shouldReattach(now: 100.8, lastPlainKeyDown: 100.5))
        detector.reattachedToChinese(at: 100.9)
        // The same stray key must not trigger another attempt.
        XCTAssertFalse(detector.shouldReattach(now: 101.5, lastPlainKeyDown: 100.5))
        XCTAssertTrue(detector.shouldReattach(now: 102.3, lastPlainKeyDown: 102))
    }

    func testGivesUpAfterMaximumAttempts() {
        var detector = SilentClientDetector()
        detector.switchedToChinese(at: 100)

        XCTAssertTrue(detector.shouldReattach(now: 100.8, lastPlainKeyDown: 100.5))
        detector.reattachedToChinese(at: 100.9)
        XCTAssertTrue(detector.shouldReattach(now: 101.8, lastPlainKeyDown: 101.5))
        detector.reattachedToChinese(at: 101.9)
        // A client that is not editing text keeps ignoring the input method;
        // stop flipping the source at it.
        XCTAssertFalse(detector.shouldReattach(now: 102.8, lastPlainKeyDown: 102.5))
        XCTAssertFalse(detector.isWatching)
    }

    func testReattachRecoveryEndsTheWatch() {
        var detector = SilentClientDetector()
        detector.switchedToChinese(at: 100)

        XCTAssertTrue(detector.shouldReattach(now: 100.8, lastPlainKeyDown: 100.5))
        detector.reattachedToChinese(at: 100.9)
        detector.clientDeliveredKeyDown(at: 101.2, mode: .chinese)
        XCTAssertFalse(detector.isWatching)
    }

    func testNewSwitchResetsAttempts() {
        var detector = SilentClientDetector()
        detector.switchedToChinese(at: 100)
        XCTAssertTrue(detector.shouldReattach(now: 100.8, lastPlainKeyDown: 100.5))
        detector.reattachedToChinese(at: 100.9)
        XCTAssertTrue(detector.shouldReattach(now: 101.8, lastPlainKeyDown: 101.5))
        detector.reattachedToChinese(at: 101.9)

        detector.switchedToChinese(at: 110)
        XCTAssertTrue(detector.shouldReattach(now: 110.8, lastPlainKeyDown: 110.5))
    }

    func testStopWatchingOnFocusChange() {
        var detector = SilentClientDetector()
        detector.switchedToChinese(at: 100)

        detector.stopWatching()
        XCTAssertFalse(detector.shouldReattach(now: 100.8, lastPlainKeyDown: 100.5))
    }

    func testEnglishDeliveryDoesNotProveChineseIsHealthy() {
        var detector = SilentClientDetector()
        detector.switchedToChinese(at: 100)

        detector.clientDeliveredKeyDown(at: 100.5, mode: .english)
        XCTAssertTrue(detector.isWatching)
        XCTAssertTrue(detector.shouldReattach(now: 100.8, lastPlainKeyDown: 100.5))
    }

    func testReattachWaitsForConfirmedReturnToChinese() {
        var detector = SilentClientDetector()
        detector.switchedToChinese(at: 100)
        XCTAssertTrue(detector.shouldReattach(now: 100.8, lastPlainKeyDown: 100.5))

        detector.clientDeliveredKeyDown(at: 100.85, mode: .english)
        detector.clientDeliveredKeyDown(at: 100.86, mode: .chinese)
        XCTAssertTrue(detector.isWatching)
        XCTAssertTrue(detector.isReattaching)
        XCTAssertFalse(detector.shouldReattach(now: 101.2, lastPlainKeyDown: 100.9))

        detector.reattachedToChinese(at: 101.3)
        XCTAssertFalse(detector.isReattaching)
        XCTAssertFalse(detector.shouldReattach(now: 101.6, lastPlainKeyDown: 101.2))
        XCTAssertTrue(detector.shouldReattach(now: 102, lastPlainKeyDown: 101.7))
    }

    func testDelayedEnglishKeyAfterReturnDoesNotEndWatch() {
        var detector = SilentClientDetector()
        detector.switchedToChinese(at: 100)
        XCTAssertTrue(detector.shouldReattach(now: 100.8, lastPlainKeyDown: 100.5))
        detector.reattachedToChinese(at: 100.9)

        // Delivery sees Chinese selected, but the key was typed in English
        // just before the source returned. Even a 10 ms gap must be rejected.
        detector.clientDeliveredKeyDown(at: 100.89, mode: .chinese)
        XCTAssertTrue(detector.isWatching)
        XCTAssertTrue(detector.shouldReattach(now: 101.8, lastPlainKeyDown: 101.5))
    }

    func testDelayedKeyBeforeNewSwitchDoesNotEndWatch() {
        var detector = SilentClientDetector()
        detector.switchedToChinese(at: 100)

        detector.clientDeliveredKeyDown(at: 99.99, mode: .chinese)
        detector.clientDeliveredKeyDown(at: 100.1, mode: nil)
        XCTAssertTrue(detector.isWatching)
        XCTAssertTrue(detector.shouldReattach(now: 100.8, lastPlainKeyDown: 100.5))
    }

    func testReturnToChineseDoesNotExtendOriginalDeadline() {
        var detector = SilentClientDetector()
        detector.switchedToChinese(at: 100)
        XCTAssertTrue(detector.shouldReattach(now: 129, lastPlainKeyDown: 128.5))
        detector.reattachedToChinese(at: 129.1)

        XCTAssertFalse(detector.shouldReattach(now: 130.3, lastPlainKeyDown: 129.9))
        XCTAssertFalse(detector.isWatching)
    }

    func testLateReturnAfterCancellationDoesNotRestartWatch() {
        var detector = SilentClientDetector()
        detector.switchedToChinese(at: 100)
        XCTAssertTrue(detector.shouldReattach(now: 100.8, lastPlainKeyDown: 100.5))

        detector.stopWatching()
        detector.reattachedToChinese(at: 100.9)
        XCTAssertFalse(detector.isWatching)
        XCTAssertFalse(detector.isReattaching)
    }

    func testWatchCanExpireDuringReattach() {
        var detector = SilentClientDetector()
        detector.switchedToChinese(at: 100)
        XCTAssertTrue(detector.shouldReattach(now: 129.9, lastPlainKeyDown: 129.5))

        detector.reattachedToChinese(at: 130.1)
        XCTAssertFalse(detector.isWatching)
        XCTAssertFalse(detector.isReattaching)
    }

    func testReattachmentCallbackCanBeClaimedOnlyOnce() {
        var guardState = ClientReattachmentGuard()
        let token = guardState.begin()

        XCTAssertTrue(guardState.claim(token: token, currentMode: .english, isCurrentClient: true))
        XCTAssertFalse(guardState.claim(token: token, currentMode: .english, isCurrentClient: true))
    }

    func testCancelledReattachmentCannotChangeSource() {
        var guardState = ClientReattachmentGuard()
        let token = guardState.begin()
        guardState.cancel()

        XCTAssertFalse(guardState.claim(token: token, currentMode: .english, isCurrentClient: true))
    }

    func testReattachmentRejectsChangedInputSource() {
        for mode: LanguageMode? in [.chinese, nil] {
            var guardState = ClientReattachmentGuard()
            let token = guardState.begin()

            XCTAssertFalse(guardState.claim(token: token, currentMode: mode, isCurrentClient: true))
            XCTAssertFalse(guardState.claim(token: token, currentMode: .english, isCurrentClient: true))
        }
    }

    func testReattachmentRejectsChangedClient() {
        var guardState = ClientReattachmentGuard()
        let token = guardState.begin()

        XCTAssertFalse(guardState.claim(token: token, currentMode: .english, isCurrentClient: false))
    }

    func testOldCallbackCannotConsumeNewRecoveryToken() {
        var guardState = ClientReattachmentGuard()
        let oldToken = guardState.begin()
        let newToken = guardState.begin()

        XCTAssertFalse(guardState.claim(token: oldToken, currentMode: .english, isCurrentClient: true))
        XCTAssertTrue(guardState.claim(token: newToken, currentMode: .english, isCurrentClient: true))
    }

    func testTypingKeysAreHeldDuringReattachment() {
        for characters in ["k", "J", "1", ";", " ", "-"] {
            XCTAssertTrue(
                ReattachmentKeyHold.holds(characters: characters, hasCommandModifier: false),
                characters
            )
        }
    }

    func testEditingNavigationAndShortcutKeysAreNotHeld() {
        let returnKey = "\r", tab = "\t", delete = "\u{7F}", escape = "\u{1B}"
        let leftArrow = "\u{F702}"
        for characters in [returnKey, tab, delete, escape, leftArrow, ""] {
            XCTAssertFalse(
                ReattachmentKeyHold.holds(characters: characters, hasCommandModifier: false),
                characters.debugDescription
            )
        }
        XCTAssertFalse(ReattachmentKeyHold.holds(characters: nil, hasCommandModifier: false))
        XCTAssertFalse(ReattachmentKeyHold.holds(characters: "c", hasCommandModifier: true))
    }
}
