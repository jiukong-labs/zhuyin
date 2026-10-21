import Foundation

/// System screens that must never be covered by Jiukong's own overlays.
///
/// The App Store and Apple Pay payment sheet stops accepting Touch ID and
/// removes its pay control for as long as another process's window covers any
/// part of it, as a guard against click-jacking. The cursor indicator follows
/// the pointer above every window, so pointing at the sheet disabled it: the
/// payment extension logged "Payment UI is occluded: true" each time the
/// indicator moved onto the sheet and "false" each time it left. The sheet's
/// window belongs to the App Store or the purchasing app, so the window list
/// cannot tell it apart. These screens do take keyboard focus, though, and
/// activate the input method under their own client bundle identifiers.
enum SecureSystemUI {
    static let clientBundleIdentifiers: Set<String> = [
        // Observed activating Jiukong while a payment sheet had focus.
        // App Store purchases:
        "com.apple.AMSUIPaymentViewService",
        // In-app purchases:
        "com.apple.StoreKit.UIService",
        // The sheet's payment and Touch ID area, shared by both:
        "com.apple.PassKit.PaymentAuthorizationUIExtension",
        // macOS password prompts and Touch ID prompts. No occlusion check was
        // seen in their logs; they are authorization screens of the same
        // kind, and the indicator has nothing to show while they have focus.
        "com.apple.SecurityAgent",
        "com.apple.LocalAuthentication.UIAgent",
    ]

    /// Focus passes between the payment services through a gap of about
    /// 20 ms in which an ordinary client is current again. Waiting this long
    /// before showing the overlays keeps them from flashing over the sheet.
    static let releaseDelay: TimeInterval = 0.5

    static func isSecure(clientBundleIdentifier: String?) -> Bool {
        clientBundleIdentifier.map(clientBundleIdentifiers.contains) ?? false
    }
}

/// Decides whether Jiukong's overlays must stay off screen because a secure
/// system screen has keyboard focus.
///
/// The current controller is resolved by `ActiveControllerTracker`, so the
/// overlapping activations seen while focus moves between apps settle the
/// same way they do for Shift handling. Overlays hide as soon as a secure
/// screen becomes current and return `SecureSystemUI.releaseDelay` after
/// focus has left every secure screen.
struct SecureSystemUIFocus<Controller: AnyObject> {
    private struct Client {
        weak var controller: Controller?
        var isSecure: Bool
    }

    private var controllers = ActiveControllerTracker<Controller>()
    private var clients: [Client] = []

    private(set) var hidesOverlays = false
    /// When the overlays may return, while focus is away from secure screens
    /// but the release delay has not passed. Call `refresh(at:)` then.
    private(set) var releaseTime: TimeInterval?

    mutating func activated(
        _ controller: Controller,
        clientBundleIdentifier: String?,
        at now: TimeInterval
    ) {
        clients.removeAll { $0.controller == nil || $0.controller === controller }
        clients.append(
            Client(
                controller: controller,
                isSecure: SecureSystemUI.isSecure(
                    clientBundleIdentifier: clientBundleIdentifier
                )
            )
        )
        controllers.activated(controller)
        update(at: now)
    }

    mutating func deactivated(_ controller: Controller, at now: TimeInterval) {
        controllers.deactivated(controller)
        update(at: now)
    }

    /// The client routes events to this controller, whatever activation said.
    mutating func receivedEvent(from controller: Controller, at now: TimeInterval) {
        controllers.receivedEvent(from: controller)
        update(at: now)
    }

    mutating func refresh(at now: TimeInterval) {
        update(at: now)
    }

    private var focusIsSecure: Bool {
        guard let current = controllers.current else {
            return false
        }
        return clients.contains { $0.controller === current && $0.isSecure }
    }

    private mutating func update(at now: TimeInterval) {
        if focusIsSecure {
            hidesOverlays = true
            releaseTime = nil
            return
        }
        guard hidesOverlays else {
            return
        }
        let releaseTime = self.releaseTime ?? now + SecureSystemUI.releaseDelay
        if now >= releaseTime {
            hidesOverlays = false
            self.releaseTime = nil
        } else {
            self.releaseTime = releaseTime
        }
    }
}
