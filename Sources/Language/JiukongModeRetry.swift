import Foundation

/// Decides when Chinese may try the 久空 mode again after macOS did not
/// select it.
///
/// A refusal can last only a moment. Restoring Jiukong after a Chrome
/// password field once found macOS not selecting the 久空 mode, and treating
/// that as permanent left every later Chinese selection on the Chinese mode,
/// with 中 in the menu bar, until the process restarted. A failure therefore
/// only postpones the next attempt, so a mode macOS keeps refusing does not
/// make every Chinese selection switch sources twice. The wait doubles with
/// each consecutive failure up to `maximumDelay`, and any successful
/// selection, including the user choosing the mode from the input menu,
/// starts over.
struct JiukongModeRetry {
    static let initialDelay: TimeInterval = 2
    static let maximumDelay: TimeInterval = 300

    /// When the next attempt may be made; nil until a failure.
    private(set) var retryTime: TimeInterval?
    private var nextDelay = initialDelay

    func allowsAttempt(at now: TimeInterval) -> Bool {
        guard let retryTime else {
            return true
        }
        return now >= retryTime
    }

    /// Returns how long the next attempt waits.
    @discardableResult
    mutating func failed(at now: TimeInterval) -> TimeInterval {
        let delay = nextDelay
        retryTime = now + delay
        nextDelay = min(delay * 2, Self.maximumDelay)
        return delay
    }

    /// The 久空 mode is selected, so macOS accepts it.
    mutating func succeeded() {
        retryTime = nil
        nextDelay = Self.initialDelay
    }
}
