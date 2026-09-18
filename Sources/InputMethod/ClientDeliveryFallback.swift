import AppKit
import Carbon

/// Recovers from key events a client never handed to the input method.
///
/// Chromium-based clients such as Chrome, VS Code and Teams fail in two ways.
/// They intermittently drop a single Shift `flagsChanged` event while still
/// forwarding key-downs, so a Shift tap silently does not switch. And right
/// after a switch from English to Chinese they sometimes stop forwarding key
/// events altogether, so typing lands in the page as Latin letters under a
/// Chinese source until the source changes again.
///
/// While a client has Jiukong active, this polls the session keyboard state,
/// which needs no extra permission. It switches the language for Shift taps
/// the event path never concluded, and re-attaches a client that went silent
/// after a switch to Chinese.
final class ClientDeliveryFallback {
    static let shared = ClientDeliveryFallback()

    /// Short enough to see the briefest deliberate tap, which measured around
    /// 45 ms, as held for at least one sample.
    static let pollingInterval: TimeInterval = 0.015

    private let preferences = PreferencesController.shared
    private var shiftTapDetector = SystemShiftTapDetector()
    private var arbiter = ShiftToggleArbiter()
    private var silentClientDetector = SilentClientDetector()
    private var lastKeyDownCount: UInt32?
    private var lastPlainKeyDown: TimeInterval?
    private var lastPollTime: TimeInterval?
    private var statsStart: TimeInterval = 0
    private var statsTicks = 0
    private var statsMaxGap: TimeInterval = 0
    private var watchStartedAt: TimeInterval?
    private weak var activeController: InputController?
    private var timer: Timer?
    private var activity: NSObjectProtocol?

    private init() {}

    func controllerDidActivate(_ controller: InputController) {
        precondition(Thread.isMainThread)
        activeController = controller
        startPolling()
    }

    /// Controllers hand over with overlap: a new one can activate before the
    /// previous one deactivates, so only the current controller stops polling.
    func controllerDidDeactivate(_ controller: InputController) {
        precondition(Thread.isMainThread)
        guard activeController === controller else {
            return
        }
        activeController = nil
        stopPolling()
    }

    /// Reports a key-down the client handed to the input method, stamped with
    /// the event's hardware time.
    func clientDeliveredKeyDown(at time: TimeInterval) {
        precondition(Thread.isMainThread)
        let wasWatching = silentClientDetector.isWatching
        silentClientDetector.clientDeliveredKeyDown(at: time)
        if wasWatching, !silentClientDetector.isWatching, let start = watchStartedAt {
            jiukongShiftTrace(
                "silent watch: client delivered a key \(Int((time - start) * 1000))ms after the switch — healthy"
            )
            watchStartedAt = nil
        }
    }

    /// Reports a language switch the user asked for. A switch to Chinese is
    /// watched for a client that stops handing keys to the input method.
    func languageModeSwitched(to mode: LanguageMode) {
        precondition(Thread.isMainThread)
        switch mode {
        case .chinese:
            let now = ProcessInfo.processInfo.systemUptime
            silentClientDetector.switchedToChinese(at: now)
            watchStartedAt = now
            jiukongShiftTrace("silent watch: armed after switch to chinese")
        case .english:
            silentClientDetector.stopWatching()
        }
    }

    /// Reports that the event path finished judging a Shift gesture. Returns
    /// false when this fallback already switched the language for that tap.
    func clientPathConcludedGesture(
        releasedAt releaseTime: TimeInterval
    ) -> Bool {
        precondition(Thread.isMainThread)
        return arbiter.clientPathConcludedGesture(releasedAt: releaseTime)
    }

    private func startPolling() {
        guard timer == nil else {
            return
        }

        shiftTapDetector.reset()
        // An agent app without a key window is a candidate for App Nap, which
        // would stretch the polling interval far past a tap's duration.
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Detect Shift taps a client did not deliver"
        )

        let timer = Timer(
            timeInterval: Self.pollingInterval,
            repeats: true
        ) { [weak self] _ in
            self?.poll()
        }
        timer.tolerance = Self.pollingInterval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        jiukongShiftTrace("fallback polling started")
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
        activity = nil
        shiftTapDetector.reset()
        silentClientDetector.stopWatching()
        lastKeyDownCount = nil
        lastPlainKeyDown = nil
        lastPollTime = nil
        if watchStartedAt != nil {
            jiukongShiftTrace("silent watch: ended because the client deactivated")
        }
        watchStartedAt = nil
        jiukongShiftTrace("fallback polling stopped")
    }

    private func poll() {
        let now = ProcessInfo.processInfo.systemUptime
        recordCadence(now: now)
        let flags = CGEventSource.flagsState(Self.eventState)
        let sample = Self.sampleKeyboard(now: now, flags: flags)

        if let tap = shiftTapDetector.ingest(sample) {
            jiukongShiftTrace(
                "fallback tap side=\(tap.side == .left ? "L" : "R")"
                    + " release=\(String(format: "%.4f", tap.releaseTime))"
                    + " seenAfterMs=\(Int((now - tap.releaseTime) * 1000))"
            )
            arbiter.fallbackObserved(tap)
        }
        for tap in arbiter.dueFallbackTaps(now: now) {
            let allowed = preferences.current.shiftKeyPreference.allows(tap.side)
            jiukongShiftTrace(
                "fallback SWITCHING release=\(String(format: "%.4f", tap.releaseTime))"
                    + " allowed=\(allowed) hasController=\(activeController != nil)"
            )
            guard allowed else {
                continue
            }
            activeController?.toggleLanguageModeForUndeliveredShiftTap()
        }

        let wasWatching = silentClientDetector.isWatching
        notePlainKeyDowns(in: sample, flags: flags, now: now)
        if silentClientDetector.shouldReattach(
            now: now,
            lastPlainKeyDown: lastPlainKeyDown
        ) {
            jiukongShiftTrace(
                "silent watch: SILENT CLIENT — plain key at "
                    + String(format: "%.4f", lastPlainKeyDown ?? 0)
                    + " never delivered; reattaching, hasController=\(activeController != nil)"
            )
            activeController?.reattachSilentClient()
        } else if wasWatching, !silentClientDetector.isWatching, watchStartedAt != nil {
            jiukongShiftTrace("silent watch: gave up or expired")
            watchStartedAt = nil
        }
    }

    private func recordCadence(now: TimeInterval) {
        defer { lastPollTime = now }
        guard let lastPollTime else {
            statsStart = now
            statsTicks = 0
            statsMaxGap = 0
            return
        }
        let gap = now - lastPollTime
        statsTicks += 1
        statsMaxGap = max(statsMaxGap, gap)
        if gap > 0.05 {
            jiukongShiftTrace("fallback poll gap \(Int(gap * 1000))ms")
        }
        if now - statsStart >= 60 {
            jiukongShiftTrace(
                "fallback poll stats ticks=\(statsTicks)"
                    + " avgMs=\(String(format: "%.1f", (now - statsStart) / Double(max(statsTicks, 1)) * 1000))"
                    + " maxGapMs=\(Int(statsMaxGap * 1000))"
            )
            statsStart = now
            statsTicks = 0
            statsMaxGap = 0
        }
    }

    /// Command and Control chords are menu shortcuts a client may handle
    /// without the input method, so only keys typed without them count as
    /// keys the client should have handed over.
    private func notePlainKeyDowns(
        in sample: SystemKeyboardSample,
        flags: CGEventFlags,
        now: TimeInterval
    ) {
        defer { lastKeyDownCount = sample.keyDownCount }
        guard let lastKeyDownCount,
              sample.keyDownCount != lastKeyDownCount,
              flags.intersection([.maskCommand, .maskControl]).isEmpty else {
            return
        }
        lastPlainKeyDown = now - CGEventSource.secondsSinceLastEventType(
            Self.eventState,
            eventType: .keyDown
        )
    }

    private static let eventState = CGEventSourceStateID.combinedSessionState

    private static func sampleKeyboard(
        now: TimeInterval,
        flags: CGEventFlags
    ) -> SystemKeyboardSample {
        let state = eventState
        let otherModifiers: CGEventFlags = [
            .maskCommand,
            .maskControl,
            .maskAlternate,
            .maskSecondaryFn
        ]
        let mouseDownCount = [
            CGEventType.leftMouseDown,
            .rightMouseDown,
            .otherMouseDown
        ].reduce(UInt32(0)) {
            $0 &+ CGEventSource.counterForEventType(state, eventType: $1)
        }

        // `CGEventSource.keyState` reports either Shift as the left one, so
        // the side comes from the device-dependent flag bits instead.
        return SystemKeyboardSample(
            lastModifierChangeTime: now - CGEventSource.secondsSinceLastEventType(
                state,
                eventType: .flagsChanged
            ),
            leftShiftDown: flags.rawValue & UInt64(NX_DEVICELSHIFTKEYMASK) != 0,
            rightShiftDown: flags.rawValue & UInt64(NX_DEVICERSHIFTKEYMASK) != 0,
            otherModifierDown: !flags.intersection(otherModifiers).isEmpty,
            keyDownCount: CGEventSource.counterForEventType(
                state,
                eventType: .keyDown
            ),
            mouseDownCount: mouseDownCount,
            flagsChangedCount: CGEventSource.counterForEventType(
                state,
                eventType: .flagsChanged
            )
        )
    }
}
