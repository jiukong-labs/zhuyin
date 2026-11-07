import XCTest

final class JiukongModeRetryTests: XCTestCase {
    private let initial = JiukongModeRetry.initialDelay

    func testAttemptsUntilTheFirstFailure() {
        let retry = JiukongModeRetry()

        XCTAssertTrue(retry.allowsAttempt(at: 0))
        XCTAssertNil(retry.retryTime)
    }

    func testOneRefusalDoesNotDisableTheModeForTheRestOfTheProcess() {
        // The restore after a Chrome password field found macOS not
        // selecting the 久空 mode; the next restore 15 s later must try it
        // again instead of going straight to the Chinese mode.
        var retry = JiukongModeRetry()

        XCTAssertEqual(retry.failed(at: 100), initial)
        XCTAssertFalse(retry.allowsAttempt(at: 100))
        XCTAssertFalse(retry.allowsAttempt(at: 100 + initial - 0.01))
        XCTAssertTrue(retry.allowsAttempt(at: 100 + initial))
        XCTAssertTrue(retry.allowsAttempt(at: 115))
        XCTAssertTrue(retry.allowsAttempt(at: 100 + 4 * 3600))
    }

    func testConsecutiveFailuresWaitLongerUpToTheMaximum() {
        var retry = JiukongModeRetry()
        var now: TimeInterval = 0
        var delays: [TimeInterval] = []

        for _ in 0 ..< 10 {
            let delay = retry.failed(at: now)
            delays.append(delay)
            XCTAssertEqual(retry.retryTime, now + delay)
            now += delay
        }

        XCTAssertEqual(delays, [2, 4, 8, 16, 32, 64, 128, 256, 300, 300])
    }

    func testSuccessStartsOver() {
        var retry = JiukongModeRetry()
        retry.failed(at: 0)
        retry.failed(at: 2)
        retry.failed(at: 6)

        retry.succeeded()

        XCTAssertNil(retry.retryTime)
        XCTAssertTrue(retry.allowsAttempt(at: 6.1))
        XCTAssertEqual(retry.failed(at: 7), initial)
    }
}
