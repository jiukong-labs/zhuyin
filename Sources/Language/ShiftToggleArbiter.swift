import Foundation

/// Lets one physical Shift tap switch the language at most once when both the
/// client-delivered event path and the keyboard-state fallback observe it.
struct ShiftToggleArbiter {
    /// The state sample and client event can differ slightly in hardware time.
    /// Both edges and an overlapping interval must match; proximity of two
    /// releases alone cannot identify a physical gesture.
    static let matchWindow: TimeInterval = 0.02
    static let fallbackDelay: TimeInterval = 0.12
    static let expiry: TimeInterval = 0.5
    private static let memory: TimeInterval = 2

    private struct ClientConclusion {
        var gesture: SystemShiftTap
        var allowsFallbackRecovery: Bool
        var matchingFallback: SystemShiftTap?
    }

    private struct FallbackToggle {
        var gesture: SystemShiftTap
        var matchingClient: SystemShiftTap?
    }

    private var clientConclusions: [ClientConclusion] = []
    private var fallbackToggles: [FallbackToggle] = []
    private var pendingTaps: [SystemShiftTap] = []

    /// Returns false if this physical gesture has already been handled. A
    /// client rejection based only on a late system counter is uncertain: in
    /// that case a confirmed state sample may still recover the tap.
    mutating func clientPathConcludedGesture(
        pressedAt pressTime: TimeInterval,
        releasedAt releaseTime: TimeInterval,
        side: ShiftKeySide,
        allowFallbackRecovery: Bool = false
    ) -> Bool {
        let gesture = SystemShiftTap(
            side: side,
            pressTime: pressTime,
            releaseTime: releaseTime
        )
        forget(before: releaseTime - Self.memory)
        guard !clientConclusions.contains(where: { $0.gesture == gesture }) else {
            return false
        }

        var conclusion = ClientConclusion(
            gesture: gesture,
            allowsFallbackRecovery: allowFallbackRecovery
        )
        if let index = closestMatch(
            for: gesture,
            among: fallbackToggles.indices.filter {
                fallbackToggles[$0].matchingClient == nil
            },
            gestureAt: { fallbackToggles[$0].gesture }
        ) {
            fallbackToggles[index].matchingClient = gesture
            conclusion.matchingFallback = fallbackToggles[index].gesture
            clientConclusions.append(conclusion)
            return false
        }

        if let index = closestMatch(
            for: gesture,
            among: pendingTaps.indices,
            gestureAt: { pendingTaps[$0] }
        ) {
            conclusion.matchingFallback = pendingTaps[index]
            if !allowFallbackRecovery {
                pendingTaps.remove(at: index)
            }
        }
        clientConclusions.append(conclusion)
        return true
    }

    mutating func fallbackObserved(_ tap: SystemShiftTap) {
        guard !pendingTaps.contains(tap),
              !fallbackToggles.contains(where: { $0.gesture == tap }),
              !clientConclusions.contains(where: {
                  $0.matchingFallback == tap && !$0.allowsFallbackRecovery
              }) else {
            return
        }

        if let index = closestMatch(
            for: tap,
            among: clientConclusions.indices.filter {
                clientConclusions[$0].matchingFallback == nil
            },
            gestureAt: { clientConclusions[$0].gesture }
        ) {
            clientConclusions[index].matchingFallback = tap
            if !clientConclusions[index].allowsFallbackRecovery {
                return
            }
        }
        pendingTaps.append(tap)
    }

    /// Gives the event path time to arrive when the user has not typed again.
    mutating func dueFallbackTaps(now: TimeInterval) -> [SystemShiftTap] {
        takePendingTaps(now: now) {
            now - $0.releaseTime >= Self.fallbackDelay
        }
    }

    /// A confirmed tap preceding a key must take effect before that key is
    /// interpreted. Its event timestamp supplies ordering, while the current
    /// clock decides whether a queued tap has expired.
    mutating func dueFallbackTaps(
        beforeKeyDownAt eventTime: TimeInterval,
        now: TimeInterval
    ) -> [SystemShiftTap] {
        takePendingTaps(now: now) { $0.releaseTime < eventTime }
    }

    /// Focus changes invalidate queued work but must not erase knowledge of a
    /// tap already switched, whose client event may still arrive late.
    mutating func cancelPendingTaps() {
        pendingTaps.removeAll()
    }

    private mutating func takePendingTaps(
        now: TimeInterval,
        isDue: (SystemShiftTap) -> Bool
    ) -> [SystemShiftTap] {
        var due: [SystemShiftTap] = []
        pendingTaps.removeAll { tap in
            guard now - tap.releaseTime <= Self.expiry else {
                return true
            }
            guard isDue(tap) else {
                return false
            }
            due.append(tap)
            return true
        }
        for tap in due {
            let client = clientConclusions.first { $0.matchingFallback == tap }
            fallbackToggles.append(FallbackToggle(
                gesture: tap,
                matchingClient: client?.gesture
            ))
        }
        forget(before: now - Self.memory)
        return due
    }

    private func closestMatch<Indices: Sequence>(
        for gesture: SystemShiftTap,
        among indices: Indices,
        gestureAt: (Int) -> SystemShiftTap
    ) -> Int? where Indices.Element == Int {
        indices.filter { Self.matches(gestureAt($0), gesture) }.min {
            let first = gestureAt($0)
            let second = gestureAt($1)
            return abs(first.pressTime - gesture.pressTime)
                + abs(first.releaseTime - gesture.releaseTime)
                < abs(second.pressTime - gesture.pressTime)
                + abs(second.releaseTime - gesture.releaseTime)
        }
    }

    private mutating func forget(before horizon: TimeInterval) {
        clientConclusions.removeAll { $0.gesture.releaseTime < horizon }
        fallbackToggles.removeAll { $0.gesture.releaseTime < horizon }
    }

    private static func matches(
        _ first: SystemShiftTap,
        _ second: SystemShiftTap
    ) -> Bool {
        first.side == second.side
            && abs(first.pressTime - second.pressTime) <= matchWindow
            && abs(first.releaseTime - second.releaseTime) <= matchWindow
            && max(first.pressTime, second.pressTime)
                < min(first.releaseTime, second.releaseTime)
    }
}
