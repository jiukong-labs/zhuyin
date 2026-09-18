import Foundation

/// Notices a client that stopped routing key events to the input method right
/// after a switch to Chinese.
///
/// Chromium-based clients sometimes stop handing any key event to the input
/// method once it switches from English to Chinese: the selected source is
/// Chinese and the indicator correctly shows 中, yet every key lands in the
/// page as a Latin letter, until the input source changes again. The detector
/// watches only that window, and only plain keys, so a client that is merely
/// focused on something that does not take text is left alone.
struct SilentClientDetector {
    /// How long a plain key may go unseen before the client counts as silent.
    /// A delivered key normally arrives within a few milliseconds; this also
    /// absorbs a main thread that was briefly busy switching sources.
    static let deliveryGrace: TimeInterval = 0.2
    /// A switch is watched until the client proves itself or this passes.
    static let watchDuration: TimeInterval = 30
    /// Re-attaching cannot help a client that is not editing text at all, so
    /// the detector gives up after this many attempts for one switch.
    static let maximumAttempts = 2
    /// Clock slack between a key's hardware time and the delivered event.
    private static let timestampTolerance: TimeInterval = 0.02

    private var watchStart: TimeInterval?
    private var attempts = 0
    private var lastDeliveredKeyDown: TimeInterval = -.infinity

    var isWatching: Bool {
        watchStart != nil
    }

    /// The input method just switched the client to Chinese.
    mutating func switchedToChinese(at time: TimeInterval) {
        watchStart = time
        attempts = 0
    }

    /// The client handed a key-down to the input method, which proves it is
    /// routing keys again.
    mutating func clientDeliveredKeyDown(at time: TimeInterval) {
        lastDeliveredKeyDown = max(lastDeliveredKeyDown, time)
        if let watchStart, time >= watchStart - Self.timestampTolerance {
            stopWatching()
        }
    }

    /// Focus moved, the mode left Chinese, or the input method was deselected.
    mutating func stopWatching() {
        watchStart = nil
        attempts = 0
    }

    /// Returns true when the client should be re-attached now.
    ///
    /// `lastPlainKeyDown` is the hardware time of the most recent key-down
    /// typed without Command or Control, or nil when there has been none.
    mutating func shouldReattach(
        now: TimeInterval,
        lastPlainKeyDown: TimeInterval?
    ) -> Bool {
        guard let watchStart else {
            return false
        }
        guard now - watchStart <= Self.watchDuration else {
            stopWatching()
            return false
        }
        guard let key = lastPlainKeyDown,
              key > watchStart,
              key > lastDeliveredKeyDown + Self.timestampTolerance,
              now - key >= Self.deliveryGrace else {
            return false
        }
        guard attempts < Self.maximumAttempts else {
            stopWatching()
            return false
        }

        attempts += 1
        // Judge the next attempt only on keys typed after this one.
        self.watchStart = now
        return true
    }
}
