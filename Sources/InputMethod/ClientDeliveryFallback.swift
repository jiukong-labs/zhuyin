import AppKit
import Carbon

/// Recovers from key events a client never handed to the input method.
///
/// Traces from Chrome and VS Code show missing Shift `flagsChanged` events
/// and, occasionally, missing key-downs after switching to Chinese. These
/// observations do not distinguish client routing from the macOS input
/// services, so recovery relies on observed delivery rather than app identity.
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
    /// False while watching a switch made inside the input method. No source
    /// change happened, so re-attaching would add one; the watch only traces.
    private var recoversSilentClient = true
    private var lastKeyDownCount: UInt32?
    private var lastPlainKeyDown: TimeInterval?
    private var lastPollTime: TimeInterval?
    private var statsStart: TimeInterval = 0
    private var statsTicks = 0
    private var statsMaxGap: TimeInterval = 0
    private var watchStartedAt: TimeInterval?
    private var controllers = ActiveControllerTracker<InputController>()
    private var activeController: InputController? { controllers.current }
    private var timer: Timer?
    private var activity: NSObjectProtocol?

    private init() {}

    func controllerDidActivate(_ controller: InputController) {
        precondition(Thread.isMainThread)
        let previous = activeController
        controllers.activated(controller)
        handOver(from: previous)
    }

    /// Controllers hand over with overlap: a new one can activate before the
    /// previous one deactivates, so only the current controller stops polling.
    /// Deactivating it resumes the newest controller still active.
    func controllerDidDeactivate(_ controller: InputController) {
        precondition(Thread.isMainThread)
        let previous = activeController
        guard controllers.deactivated(controller) else {
            return
        }
        handOver(from: previous)
        if let resumed = activeController {
            jiukongShiftTrace("fallback resumed [\(resumed.traceTag)], still active")
        }
    }

    /// The client routes keys to the controller that receives them, even
    /// when activation calls said otherwise. Returns true if this controller
    /// had not been the one served.
    func controllerReceivedEvent(_ controller: InputController) -> Bool {
        precondition(Thread.isMainThread)
        let previous = activeController
        guard controllers.receivedEvent(from: controller) else {
            return false
        }
        handOver(from: previous)
        return true
    }

    private func handOver(from previous: InputController?) {
        if let previous, previous !== activeController {
            previous.cancelPendingReattachment()
            stopPolling()
        }
        if activeController != nil {
            startPolling()
        }
    }

    func isActive(_ controller: InputController) -> Bool {
        activeController === controller
    }

    /// A confirmed tap predating this key must take effect before the key is
    /// interpreted. Waiting for the timer here would leak it in the old mode.
    func clientWillHandleKeyDown(
        at time: TimeInterval,
        from controller: InputController
    ) {
        precondition(Thread.isMainThread)
        guard isActive(controller) else { return }
        applyFallbackTaps(arbiter.dueFallbackTaps(
            beforeKeyDownAt: time,
            now: ProcessInfo.processInfo.systemUptime
        ), to: controller)
    }

    func clientDeliveredKeyDown(
        at time: TimeInterval,
        mode: LanguageMode?,
        from controller: InputController
    ) {
        precondition(Thread.isMainThread)
        guard isActive(controller) else { return }
        let wasWatching = silentClientDetector.isWatching
        silentClientDetector.clientDeliveredKeyDown(at: time, mode: mode)
        if wasWatching, !silentClientDetector.isWatching, let start = watchStartedAt {
            jiukongShiftTrace(
                "silent watch: client delivered a key \(Int((time - start) * 1000))ms after the switch — healthy"
            )
            watchStartedAt = nil
        }
    }

    /// Reports a language switch the user asked for. A switch to Chinese is
    /// watched for a client that stops handing keys to the input method.
    func languageModeSwitched(to mode: LanguageMode, recoversSilentClient: Bool) {
        precondition(Thread.isMainThread)
        switch mode {
        case .chinese:
            let now = ProcessInfo.processInfo.systemUptime
            silentClientDetector.switchedToChinese(at: now)
            self.recoversSilentClient = recoversSilentClient
            watchStartedAt = now
            jiukongShiftTrace(
                "silent watch: armed after switch to chinese"
                    + (recoversSilentClient ? "" : " (trace only, switched within input method)")
            )
        case .english:
            silentClientDetector.stopWatching()
            watchStartedAt = nil
        }
    }

    func inputSourceDidChange(to mode: LanguageMode?, from controller: InputController) {
        guard isActive(controller) else { return }
        if mode == nil {
            arbiter.cancelPendingTaps()
        }
        if mode == nil || (mode == .english && !silentClientDetector.isReattaching) {
            silentClientDetector.stopWatching()
            watchStartedAt = nil
        }
    }

    func reattachmentFinished(from controller: InputController, succeeded: Bool) {
        guard isActive(controller) else { return }
        if succeeded {
            let now = ProcessInfo.processInfo.systemUptime
            silentClientDetector.reattachedToChinese(at: now)
            watchStartedAt = now
            lastPlainKeyDown = nil
        } else {
            silentClientDetector.stopWatching()
            watchStartedAt = nil
        }
    }

    /// Reports that the event path finished judging a Shift gesture. Returns
    /// false when this fallback already switched the language for that tap.
    func clientPathConcludedGesture(
        _ gesture: ShiftToggleController.GestureConclusion,
        from controller: InputController
    ) -> Bool {
        precondition(Thread.isMainThread)
        guard isActive(controller) else { return false }
        return arbiter.clientPathConcludedGesture(
            pressedAt: gesture.pressTime,
            releasedAt: gesture.releaseTime,
            side: gesture.side,
            allowFallbackRecovery: gesture.allowsFallbackRecovery,
            observedReleaseCounter: gesture.observedReleaseCounter
        )
    }

    private func startPolling() {
        guard timer == nil else {
            return
        }

        shiftTapDetector.reset()
        arbiter.cancelPendingTaps()
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
        arbiter.cancelPendingTaps()
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
        let previousPoll = lastPollTime
        recordCadence(now: now)
        let flags = CGEventSource.flagsState(Self.eventState)
        let sample = Self.sampleKeyboard(now: now, flags: flags)

        if let tap = shiftTapDetector.ingest(sample) {
            jiukongShiftTrace(
                "fallback tap side=\(tap.side == .left ? "L" : "R")"
                    + " press=\(String(format: "%.4f", tap.pressTime))"
                    + " release=\(String(format: "%.4f", tap.releaseTime))"
                    + " releaseCounter=\(tap.releaseCounter.map(String.init) ?? "-")"
                    + " seenAfterMs=\(Int((now - tap.releaseTime) * 1000))"
            )
            arbiter.fallbackObserved(tap)
        } else if let rejection = shiftTapDetector.lastRejection {
            jiukongShiftTrace(
                "fallback tap rejected reason=\(rejection)"
                    + " release=\(String(format: "%.4f", sample.lastModifierChangeTime))"
            )
        }
        if let controller = activeController {
            applyFallbackTaps(arbiter.dueFallbackTaps(now: now), to: controller)
        }

        let wasWatching = silentClientDetector.isWatching
        notePlainKeyDowns(in: sample, flags: flags, now: now)
        if silentClientDetector.shouldReattach(
            now: now,
            lastPlainKeyDown: lastPlainKeyDown,
            mainThreadWasBusy: previousPoll.map {
                now - $0 > Self.busyMainThreadGap
            } ?? false
        ) {
            jiukongShiftTrace(
                "silent watch: SILENT CLIENT — plain key at "
                    + String(format: "%.4f", silentClientDetector.firstUndeliveredKey ?? 0)
                    + " (latest "
                    + String(format: "%.4f", lastPlainKeyDown ?? 0)
                    + ") never delivered; "
                    + (recoversSilentClient ? "reattaching" : "not reattaching (switched within input method)")
                    + ", hasController=\(activeController != nil)"
            )
            if recoversSilentClient {
                activeController?.reattachSilentClient()
            } else {
                silentClientDetector.stopWatching()
                watchStartedAt = nil
            }
        } else if wasWatching, !silentClientDetector.isWatching, watchStartedAt != nil {
            jiukongShiftTrace("silent watch: gave up or expired")
            watchStartedAt = nil
        }
    }

    private func applyFallbackTaps(_ taps: [SystemShiftTap], to controller: InputController) {
        for tap in taps {
            guard isActive(controller) else { return }
            let allowed = preferences.current.shiftKeyPreference.allows(tap.side)
            jiukongShiftTrace(
                "fallback SWITCHING release=\(String(format: "%.4f", tap.releaseTime))"
                    + " allowed=\(allowed) hasController=\(activeController != nil)"
            )
            guard allowed else {
                continue
            }
            controller.toggleLanguageModeForUndeliveredShiftTap(tap)
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
        if gap > Self.busyMainThreadGap {
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

    /// A gap this long between samples means the main thread was blocked, so
    /// key events the client already sent may still be waiting to be handled.
    private static let busyMainThreadGap: TimeInterval = 0.05

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
