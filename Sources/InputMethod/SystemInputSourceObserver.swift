import AppKit
import Carbon

/// Tracks whether Jiukong Zhuyin is macOS's currently selected keyboard input
/// source, independent of any client's text-field focus.
///
/// `InputController.activateServer`/`deactivateServer` only fire while some
/// client has handed the cursor to this input method, so driving the cursor
/// indicator from those alone hides it whenever focus moves somewhere
/// non-editable (the desktop, a list view, …) even though the system input
/// source has not actually changed away from Jiukong. This process-wide
/// observer is the source of truth for that broader question instead, keyed
/// off the same `kTISNotifySelectedKeyboardInputSourceChanged` notification
/// the per-client controllers already use for their own (composition-aware)
/// bookkeeping.
final class SystemInputSourceObserver {
    static let shared = SystemInputSourceObserver()

    private let cursorIndicator = CursorIndicatorController.shared
    private let preferences = PreferencesController.shared
    private var ownInputSourceID: String?

    private init() {}

    /// Call once, at process launch.
    func start() {
        precondition(Thread.isMainThread)
        ownInputSourceID = Bundle.main.object(
            forInfoDictionaryKey: "TISInputSourceID"
        ) as? String

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(selectedInputSourceDidChange),
            name: Notification.Name(
                kTISNotifySelectedKeyboardInputSourceChanged as String
            ),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        refresh()
    }

    @objc private func selectedInputSourceDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.refresh()
        }
    }

    private func refresh() {
        precondition(Thread.isMainThread)
        let currentID = Self.currentInputSourceID()
        jiukongDebugLog(
            "SystemInputSourceObserver.refresh ownInputSourceID=\(ownInputSourceID ?? "nil") currentInputSourceID=\(currentID ?? "nil")"
        )
        guard let ownInputSourceID,
              let currentInputSourceID = Self.currentInputSourceID(),
              let mode = LanguageMode.mode(
                  forInputSourceID: currentInputSourceID,
                  parentID: ownInputSourceID
              )
        else {
            cursorIndicator.setActive(false)
            return
        }

        cursorIndicator.apply(preferences.current.cursorIndicator)
        cursorIndicator.update(mode: mode)
        cursorIndicator.setActive(true)
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
