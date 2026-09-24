import AppKit
import Carbon

/// Selects Jiukong again once a password field that forced an ASCII-capable
/// source has ended and macOS left that source selected.
///
/// Runs for the life of the process, because no Jiukong controller is active
/// while another source is selected. It only polls while waiting for a
/// password field to end.
final class SecureFieldSourceGuard {
    static let shared = SecureFieldSourceGuard()

    private static let pollingInterval: TimeInterval = 0.1

    private var restorer = SecureFieldSourceRestorer(selectedMode: nil)
    private var ownInputSourceID: String?
    private var timer: Timer?
    private var activity: NSObjectProtocol?

    private init() {}

    /// Call once, at process launch.
    func start() {
        precondition(Thread.isMainThread)
        ownInputSourceID = Bundle.main.object(
            forInfoDictionaryKey: "TISInputSourceID"
        ) as? String
        restorer = SecureFieldSourceRestorer(
            selectedMode: mode(forSourceID: Self.currentInputSourceID())
        )

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(selectedInputSourceDidChange),
            name: Notification.Name(
                kTISNotifySelectedKeyboardInputSourceChanged as String
            ),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    /// A client is typing with Jiukong, so a password field has not taken
    /// over yet.
    func jiukongInUse() {
        precondition(Thread.isMainThread)
        restorer.noteJiukongInUse(secureInputEnabled: IsSecureEventInputEnabled())
    }

    @objc private func selectedInputSourceDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.sourceDidChange()
        }
    }

    private func sourceDidChange() {
        let sourceID = Self.currentInputSourceID()
        let secureInputEnabled = IsSecureEventInputEnabled()
        let wasWaiting = restorer.isWaiting
        let outcome = restorer.sourceChanged(
            to: mode(forSourceID: sourceID),
            sourceID: sourceID,
            secureInputEnabled: secureInputEnabled,
            at: ProcessInfo.processInfo.systemUptime
        )
        if restorer.isWaiting, !wasWaiting {
            jiukongShiftTrace(
                "secure field guard: watching switch to \(sourceID ?? "?")"
                    + " secureInput=\(secureInputEnabled)"
            )
            startPolling()
        }
        finish(outcome, sourceID: sourceID)
    }

    private func poll() {
        let sourceID = Self.currentInputSourceID()
        finish(
            restorer.poll(
                secureInputEnabled: IsSecureEventInputEnabled(),
                currentSourceID: sourceID,
                at: ProcessInfo.processInfo.systemUptime
            ),
            sourceID: sourceID
        )
    }

    private func finish(
        _ outcome: SecureFieldSourceRestorer.Outcome,
        sourceID: String?
    ) {
        switch outcome {
        case .none:
            return
        case .restore(let mode):
            jiukongShiftTrace(
                "secure field guard: password field ended, \(sourceID ?? "?") still selected;"
                    + " selecting \(mode.rawValue)"
            )
            select(mode)
        case .dismissed:
            jiukongShiftTrace(
                "secure field guard: no password field, \(sourceID ?? "?") was chosen"
            )
        case .superseded:
            jiukongShiftTrace("secure field guard: source changed to \(sourceID ?? "?")")
        case .gaveUp:
            jiukongShiftTrace("secure field guard: secure input stayed on, gave up")
        }
        stopPolling()
    }

    private func select(_ mode: LanguageMode) {
        guard let ownInputSourceID else {
            return
        }
        do {
            try InputSourceRegistrar.select(mode: mode, bundleIdentifier: ownInputSourceID)
        } catch {
            jiukongShiftTrace(
                "secure field guard: selecting \(mode.rawValue) failed: \(error.localizedDescription)"
            )
        }
    }

    private func startPolling() {
        guard timer == nil else {
            return
        }
        // An agent app without a key window is a candidate for App Nap, which
        // would delay the restore well past the user's next keystrokes.
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Restore Jiukong after a password field"
        )
        let timer = Timer(timeInterval: Self.pollingInterval, repeats: true) { [weak self] _ in
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
    }

    private func mode(forSourceID sourceID: String?) -> LanguageMode? {
        LanguageMode.mode(forInputSourceID: sourceID, parentID: ownInputSourceID)
    }

    private static func currentInputSourceID() -> String? {
        let inputSource = TISCopyCurrentKeyboardInputSource()
            .takeRetainedValue()
        guard let rawValue = TISGetInputSourceProperty(
            inputSource,
            kTISPropertyInputSourceID
        ) else {
            return nil
        }

        return Unmanaged<CFString>
            .fromOpaque(rawValue)
            .takeUnretainedValue() as String
    }
}
