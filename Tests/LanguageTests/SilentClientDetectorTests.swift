import XCTest

final class SilentClientDetectorTests: XCTestCase {
    func testUndeliveredPlainKeyAfterSwitchTriggersReattach() {
        var detector = SilentClientDetector()
        detector.switchedToChinese(at: 100)

        // A plain key at 100.5 never reaches the input method.
        XCTAssertFalse(detector.shouldReattach(now: 100.6, lastPlainKeyDown: 100.5))
        XCTAssertTrue(detector.shouldReattach(now: 100.71, lastPlainKeyDown: 100.5))
    }

    func testDeliveredKeyStopsWatching() {
        var detector = SilentClientDetector()
        detector.switchedToChinese(at: 100)

        detector.clientDeliveredKeyDown(at: 100.5)
        XCTAssertFalse(detector.isWatching)
        XCTAssertFalse(detector.shouldReattach(now: 101, lastPlainKeyDown: 100.5))
    }

    func testDeliveryHandledLateStillCountsAsDelivered() {
        var detector = SilentClientDetector()
        detector.switchedToChinese(at: 100)

        // The event's hardware time is when it was typed, even if the busy
        // main thread handled it later.
        detector.clientDeliveredKeyDown(at: 100.5)
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
        // The same stray key must not trigger another attempt.
        XCTAssertFalse(detector.shouldReattach(now: 101.5, lastPlainKeyDown: 100.5))
        XCTAssertTrue(detector.shouldReattach(now: 102.3, lastPlainKeyDown: 102))
    }

    func testGivesUpAfterMaximumAttempts() {
        var detector = SilentClientDetector()
        detector.switchedToChinese(at: 100)

        XCTAssertTrue(detector.shouldReattach(now: 100.8, lastPlainKeyDown: 100.5))
        XCTAssertTrue(detector.shouldReattach(now: 101.8, lastPlainKeyDown: 101.5))
        // A client that is not editing text keeps ignoring the input method;
        // stop flipping the source at it.
        XCTAssertFalse(detector.shouldReattach(now: 102.8, lastPlainKeyDown: 102.5))
        XCTAssertFalse(detector.isWatching)
    }

    func testReattachRecoveryEndsTheWatch() {
        var detector = SilentClientDetector()
        detector.switchedToChinese(at: 100)

        XCTAssertTrue(detector.shouldReattach(now: 100.8, lastPlainKeyDown: 100.5))
        detector.clientDeliveredKeyDown(at: 101.2)
        XCTAssertFalse(detector.isWatching)
    }

    func testNewSwitchResetsAttempts() {
        var detector = SilentClientDetector()
        detector.switchedToChinese(at: 100)
        XCTAssertTrue(detector.shouldReattach(now: 100.8, lastPlainKeyDown: 100.5))
        XCTAssertTrue(detector.shouldReattach(now: 101.8, lastPlainKeyDown: 101.5))

        detector.switchedToChinese(at: 110)
        XCTAssertTrue(detector.shouldReattach(now: 110.8, lastPlainKeyDown: 110.5))
    }

    func testStopWatchingOnFocusChange() {
        var detector = SilentClientDetector()
        detector.switchedToChinese(at: 100)

        detector.stopWatching()
        XCTAssertFalse(detector.shouldReattach(now: 100.8, lastPlainKeyDown: 100.5))
    }
}
