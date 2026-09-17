import AppKit
import Carbon

/// Recovers standalone Shift taps that a client never delivered.
///
/// Chromium-based clients intermittently stop forwarding Shift
/// `flagsChanged` events to the input method while still forwarding
/// key-downs, so the Shift toggle silently stops working in those windows.
/// While a client has Jiukong active, this polls the session keyboard state,
/// which needs no extra permission, and switches the language for taps the
/// event path never concluded.
final class ShiftStateFallback {
    static let shared = ShiftStateFallback()

    /// Short enough to see the briefest deliberate tap, which measured around
    /// 45 ms, as held for at least one sample.
    static let pollingInterval: TimeInterval = 0.015

    private let preferences = PreferencesController.shared
    private var detector = SystemShiftTapDetector()
    private var arbiter = ShiftToggleArbiter()
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

        detector.reset()
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
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
        activity = nil
        detector.reset()
    }

    private func poll() {
        let now = ProcessInfo.processInfo.systemUptime
        if let tap = detector.ingest(Self.sampleKeyboard(now: now)) {
            arbiter.fallbackObserved(tap)
        }

        for tap in arbiter.dueFallbackTaps(now: now)
        where preferences.current.shiftKeyPreference.allows(tap.side) {
            activeController?.toggleLanguageModeForUndeliveredShiftTap()
        }
    }

    private static func sampleKeyboard(
        now: TimeInterval
    ) -> SystemKeyboardSample {
        let state = CGEventSourceStateID.combinedSessionState
        let flags = CGEventSource.flagsState(state)
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
