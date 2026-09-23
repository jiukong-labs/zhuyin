import Foundation

/// Lets one physical Shift tap switch the language at most once when both the
/// client-delivered event path and the keyboard-state fallback observe it.
struct ShiftToggleArbiter {
    /// How far a client edge may precede the sampled edge of the same tap.
    /// Timestamp matching requires both edges and an overlapping interval;
    /// proximity of two releases alone cannot identify a physical gesture.
    static let matchWindow: TimeInterval = 0.02
    /// How far a client release may trail the sampled release of the same
    /// tap. A client forwards each Shift edge after WindowServer records it:
    /// measured client presses trailed by up to 131 ms and releases by up to
    /// 72 ms, never leading by more than a few milliseconds. Requiring the
    /// press within 20 ms made the fallback switch back taps that the client
    /// had already switched. A lag that separates the two intervals remains
    /// the observed-counter path's job.
    static let clientReleaseLag: TimeInterval = 0.05
    static let fallbackDelay: TimeInterval = 0.12
    static let expiry: TimeInterval = 0.5
    private static let memory: TimeInterval = 2

    private struct ClientConclusion {
        var gesture: SystemShiftTap
        var allowsFallbackRecovery: Bool
        var observedReleaseCounter: UInt32?
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
        allowFallbackRecovery: Bool = false,
        observedReleaseCounter: UInt32? = nil
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
            allowsFallbackRecovery: allowFallbackRecovery,
            observedReleaseCounter: observedReleaseCounter
        )
        let counterMatch = uniquelyObservedRelease(
            for: gesture,
            counter: observedReleaseCounter
        )
        if let index = closestMatch(
            forClient: gesture,
            among: fallbackToggles.indices.filter {
                fallbackToggles[$0].matchingClient == nil
            },
            gestureAt: { fallbackToggles[$0].gesture }
        ) ?? fallbackToggles.firstIndex(where: {
            $0.matchingClient == nil && $0.gesture == counterMatch
        }) {
            fallbackToggles[index].matchingClient = gesture
            conclusion.matchingFallback = fallbackToggles[index].gesture
            clientConclusions.append(conclusion)
            return false
        }

        if let index = closestMatch(
            forClient: gesture,
            among: pendingTaps.indices,
            gestureAt: { pendingTaps[$0] }
        ) ?? pendingTaps.firstIndex(where: { $0 == counterMatch }) {
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
            forPolled: tap,
            among: clientConclusions.indices.filter {
                clientConclusions[$0].matchingFallback == nil
            },
            gestureAt: { clientConclusions[$0].gesture }
        ) ?? uniquelyObservedClient(for: tap) {
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
        forClient client: SystemShiftTap,
        among indices: Indices,
        gestureAt: (Int) -> SystemShiftTap
    ) -> Int? where Indices.Element == Int {
        closestMatch(for: client, among: indices, gestureAt: gestureAt) {
            Self.matches(client: client, polled: $0)
        }
    }

    private func closestMatch<Indices: Sequence>(
        forPolled polled: SystemShiftTap,
        among indices: Indices,
        gestureAt: (Int) -> SystemShiftTap
    ) -> Int? where Indices.Element == Int {
        closestMatch(for: polled, among: indices, gestureAt: gestureAt) {
            Self.matches(client: $0, polled: polled)
        }
    }

    private func closestMatch<Indices: Sequence>(
        for gesture: SystemShiftTap,
        among indices: Indices,
        gestureAt: (Int) -> SystemShiftTap,
        matching: (SystemShiftTap) -> Bool
    ) -> Int? where Indices.Element == Int {
        indices.filter { matching(gestureAt($0)) }.min {
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

    /// LINE can deliver a complete down/up pair after polling already saw the
    /// release, with timestamps shifted enough that the intervals no longer
    /// overlap. Only use a counter the caller observed unchanged at BOTH
    /// callbacks while physical Shift was up. Requiring one unclaimed tap
    /// avoids guessing which gesture a delayed pair belongs to after rapid
    /// consecutive taps. Only tolerate timestamps shifted forward: reading a
    /// later counter cannot make an earlier client release belong to a newer
    /// physical tap. Normal timestamp matching remains unchanged.
    private func uniquelyObservedRelease(
        for gesture: SystemShiftTap,
        counter: UInt32?
    ) -> SystemShiftTap? {
        guard let counter else { return nil }
        let candidates = unclaimedFallbacks(near: gesture)
        guard candidates.count == 1,
              candidates[0].releaseCounter == counter,
              candidates[0].releaseTime <= gesture.releaseTime else { return nil }
        return candidates[0]
    }

    /// The timer may observe the release after both delayed client callbacks.
    /// Apply the same evidence requirements regardless of delivery order.
    private func uniquelyObservedClient(for tap: SystemShiftTap) -> Int? {
        guard let counter = tap.releaseCounter,
              unclaimedFallbacks(near: tap).isEmpty else { return nil }
        let candidates = clientConclusions.indices.filter {
            let client = clientConclusions[$0]
            return client.matchingFallback == nil
                && client.gesture.side == tap.side
                && abs(client.gesture.releaseTime - tap.releaseTime) <= Self.expiry
        }
        guard candidates.count == 1,
              clientConclusions[candidates[0]].observedReleaseCounter == counter,
              tap.releaseTime <= clientConclusions[candidates[0]].gesture.releaseTime else {
            return nil
        }
        return candidates[0]
    }

    private func unclaimedFallbacks(near gesture: SystemShiftTap) -> [SystemShiftTap] {
        let unclaimed = pendingTaps + fallbackToggles.compactMap {
            $0.matchingClient == nil ? $0.gesture : nil
        }
        return unclaimed.filter { tap in
            tap.side == gesture.side
                && abs(tap.releaseTime - gesture.releaseTime) <= Self.expiry
                && !clientConclusions.contains { $0.matchingFallback == tap }
        }
    }

    private static func matches(
        client: SystemShiftTap,
        polled: SystemShiftTap
    ) -> Bool {
        let pressLag = client.pressTime - polled.pressTime
        let releaseLag = client.releaseTime - polled.releaseTime
        return client.side == polled.side
            && pressLag >= -matchWindow
            && releaseLag >= -matchWindow
            && releaseLag <= clientReleaseLag
            && max(client.pressTime, polled.pressTime)
                < min(client.releaseTime, polled.releaseTime)
    }
}
