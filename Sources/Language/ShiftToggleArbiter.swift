import Foundation

/// Lets one physical Shift tap switch the language at most once when both the
/// client-delivered event path and the keyboard-state fallback observe it.
///
/// The event path stays authoritative whenever it sees a gesture through to
/// its release, including when it decides the gesture was a chord. The
/// fallback only acts on taps the event path never concluded, after giving a
/// late client event time to arrive.
struct ShiftToggleArbiter {
    /// How far apart the two paths' release times may be for the same tap.
    /// Both report when the release happened rather than when it was handled,
    /// so this only has to absorb timestamp imprecision, and stays well below
    /// the gap between two deliberate taps.
    static let matchWindow: TimeInterval = 0.15
    /// How long a fallback tap waits for the client event before acting.
    static let fallbackDelay: TimeInterval = 0.12
    /// A tap older than this is dropped instead of switched. Polling pauses
    /// while no client is active, and a tap queued just before focus left must
    /// not switch the language whenever focus eventually returns.
    static let expiry: TimeInterval = 0.5
    /// How long concluded releases are remembered for matching.
    private static let memory: TimeInterval = 2

    private var clientConclusions: [TimeInterval] = []
    private var fallbackToggles: [TimeInterval] = []
    private var pendingTaps: [SystemShiftTap] = []

    /// Records that the event path finished judging a Shift gesture released
    /// at `releaseTime`. Returns false when the fallback already switched the
    /// language for this same tap, so the event path must not switch again.
    mutating func clientPathConcludedGesture(
        releasedAt releaseTime: TimeInterval
    ) -> Bool {
        forget(before: releaseTime - Self.memory)
        pendingTaps.removeAll { Self.matches($0.releaseTime, releaseTime) }
        clientConclusions.append(releaseTime)
        return !fallbackToggles.contains { Self.matches($0, releaseTime) }
    }

    /// Queues a tap recovered from keyboard state.
    mutating func fallbackObserved(_ tap: SystemShiftTap) {
        guard !clientConclusions.contains(where: {
            Self.matches($0, tap.releaseTime)
        }) else {
            return
        }
        pendingTaps.append(tap)
    }

    /// Returns the queued taps the event path never concluded and that have
    /// waited long enough, marking each as switched by the fallback.
    mutating func dueFallbackTaps(now: TimeInterval) -> [SystemShiftTap] {
        let isDue: (SystemShiftTap) -> Bool = {
            now - $0.releaseTime >= Self.fallbackDelay
        }
        let due = pendingTaps.filter(isDue)
        pendingTaps.removeAll(where: isDue)

        let unclaimed = due.filter { tap in
            now - tap.releaseTime <= Self.expiry
                && !clientConclusions.contains {
                    Self.matches($0, tap.releaseTime)
                }
        }
        fallbackToggles.append(contentsOf: unclaimed.map(\.releaseTime))
        forget(before: now - Self.memory)
        return unclaimed
    }

    private mutating func forget(before horizon: TimeInterval) {
        clientConclusions.removeAll { $0 < horizon }
        fallbackToggles.removeAll { $0 < horizon }
    }

    private static func matches(
        _ first: TimeInterval,
        _ second: TimeInterval
    ) -> Bool {
        abs(first - second) <= matchWindow
    }
}
