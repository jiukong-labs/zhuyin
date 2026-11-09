import AppKit
import Carbon
import IOKit

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

    /// A key reached Jiukong, so a password field has not taken over yet.
    func jiukongTyping() {
        precondition(Thread.isMainThread)
        restorer.noteJiukongTyping(Self.currentSecureInput())
    }

    /// A client activated Jiukong. That client can be the password field
    /// itself, just before macOS selects ABC for it.
    func jiukongActivated() {
        precondition(Thread.isMainThread)
        restorer.noteJiukongActivated(Self.currentSecureInput())
    }

    @objc private func selectedInputSourceDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.sourceDidChange()
        }
    }

    private func sourceDidChange() {
        let sourceID = Self.currentInputSourceID()
        let secureInput = Self.currentSecureInput()
        let wasWaiting = restorer.isWaiting
        let outcome = restorer.sourceChanged(
            to: mode(forSourceID: sourceID),
            sourceID: sourceID,
            secureInput: secureInput,
            at: ProcessInfo.processInfo.systemUptime
        )
        if restorer.isWaiting, !wasWaiting {
            jiukongShiftTrace(
                "secure field guard: watching switch to \(sourceID ?? "?")"
                    + " \(Self.describe(secureInput))"
            )
            startPolling()
        }
        finish(outcome, sourceID: sourceID, secureInput: secureInput)
    }

    private func poll() {
        let sourceID = Self.currentInputSourceID()
        let secureInput = Self.currentSecureInput()
        finish(
            restorer.poll(
                secureInput: secureInput,
                currentSourceID: sourceID,
                at: ProcessInfo.processInfo.systemUptime
            ),
            sourceID: sourceID,
            secureInput: secureInput
        )
    }

    private func finish(
        _ outcome: SecureFieldSourceRestorer.Outcome,
        sourceID: String?,
        secureInput: SecureFieldSourceRestorer.SecureInput
    ) {
        switch outcome {
        case .none:
            return
        case .restore(let mode):
            let reason = secureInput.enabled
                ? "password field's app left (\(Self.describe(secureInput)))"
                : "password field ended"
            jiukongShiftTrace(
                "secure field guard: \(reason), \(sourceID ?? "?") still selected;"
                    + " selecting \(mode.rawValue)"
            )
            select(mode)
        case .dismissed:
            jiukongShiftTrace(
                "secure field guard: no password field, \(sourceID ?? "?") was chosen"
            )
        case .notWatched:
            jiukongShiftTrace(
                "secure field guard: switch to \(sourceID ?? "?") left alone,"
                    + " secure input was on while typing (\(Self.describe(secureInput)))"
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
            try InputSourceRegistrar.select(
                language: mode,
                style: PreferencesController.shared.current.shiftSwitchStyle,
                bundleIdentifier: ownInputSourceID
            )
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

    private static func currentSecureInput() -> SecureFieldSourceRestorer.SecureInput {
        guard IsSecureEventInputEnabled() else {
            return .off
        }
        return SecureFieldSourceRestorer.SecureInput(
            enabled: true,
            holderPID: secureInputHolderPID(),
            frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier
        )
    }

    /// The app that turned secure input on, as the console-user record on
    /// the I/O Registry root names it. `CGSessionCopyCurrentDictionary`
    /// carries the same key but names whatever app is in front: with Chrome
    /// still holding secure input, it named VS Code once VS Code came to the
    /// front, and Jiukong took VS Code for an app with its own password field.
    private static func secureInputHolderPID() -> pid_t? {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != IO_OBJECT_NULL else {
            return nil
        }
        defer { IOObjectRelease(root) }
        guard let users = IORegistryEntryCreateCFProperty(
            root,
            "IOConsoleUsers" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? [[String: Any]] else {
            return nil
        }
        let userID = getuid()
        for user in users {
            guard (user["kCGSSessionUserIDKey"] as? NSNumber)?.uint32Value == userID,
                  let pid = user["kCGSSessionSecureInputPID"] as? NSNumber else {
                continue
            }
            return pid.int32Value
        }
        return nil
    }

    private static func describe(_ secureInput: SecureFieldSourceRestorer.SecureInput) -> String {
        guard secureInput.enabled else {
            return "secureInput=false"
        }
        return "secureInput=true holder=\(appName(secureInput.holderPID))"
            + " front=\(appName(secureInput.frontmostPID))"
    }

    private static func appName(_ pid: pid_t?) -> String {
        guard let pid else {
            return "?"
        }
        let bundleIdentifier = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        return "\(bundleIdentifier ?? "pid")[\(pid)]"
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
