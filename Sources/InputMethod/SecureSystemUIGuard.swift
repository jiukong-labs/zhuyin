import AppKit

/// Keeps the cursor indicator and the language HUD off secure system screens
/// such as the App Store and Apple Pay payment sheet.
///
/// Driven only by controller activation and events, so it does no work until
/// such a screen takes focus, never reads the window list, and needs no
/// screen recording permission. The indicator keeps its level above the
/// input menu everywhere else.
final class SecureSystemUIGuard {
    static let shared = SecureSystemUIGuard()

    private var focus = SecureSystemUIFocus<InputController>()
    private var releaseWorkItem: DispatchWorkItem?
    private var scheduledReleaseTime: TimeInterval?

    private init() {}

    /// True while a secure screen has focus, or lost it within the release
    /// delay.
    var hidesOverlays: Bool {
        focus.hidesOverlays
    }

    func controllerDidActivate(
        _ controller: InputController,
        clientBundleIdentifier: String?
    ) {
        precondition(Thread.isMainThread)
        let wasHiding = focus.hidesOverlays
        focus.activated(
            controller,
            clientBundleIdentifier: clientBundleIdentifier,
            at: ProcessInfo.processInfo.systemUptime
        )
        apply(wasHiding: wasHiding)
    }

    func controllerDidDeactivate(_ controller: InputController) {
        precondition(Thread.isMainThread)
        let wasHiding = focus.hidesOverlays
        focus.deactivated(controller, at: ProcessInfo.processInfo.systemUptime)
        apply(wasHiding: wasHiding)
    }

    func controllerReceivedEvent(_ controller: InputController) {
        precondition(Thread.isMainThread)
        let wasHiding = focus.hidesOverlays
        focus.receivedEvent(from: controller, at: ProcessInfo.processInfo.systemUptime)
        apply(wasHiding: wasHiding)
    }

    private func refresh() {
        let wasHiding = focus.hidesOverlays
        focus.refresh(at: ProcessInfo.processInfo.systemUptime)
        apply(wasHiding: wasHiding)
    }

    private func apply(wasHiding: Bool) {
        let hides = focus.hidesOverlays
        if hides != wasHiding {
            jiukongShiftTrace(
                "secure screen guard: overlays \(hides ? "hidden" : "shown")"
            )
            CursorIndicatorController.shared.setHiddenForSecureSystemUI(hides)
            if hides {
                LanguageModeHUD.shared.dismiss()
            }
        }
        scheduleRelease(at: focus.releaseTime)
    }

    private func scheduleRelease(at releaseTime: TimeInterval?) {
        guard releaseTime != scheduledReleaseTime else {
            return
        }
        releaseWorkItem?.cancel()
        releaseWorkItem = nil
        scheduledReleaseTime = releaseTime
        guard let releaseTime else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }
            self.releaseWorkItem = nil
            self.scheduledReleaseTime = nil
            self.refresh()
        }
        releaseWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now()
                + max(0, releaseTime - ProcessInfo.processInfo.systemUptime),
            execute: workItem
        )
    }
}
