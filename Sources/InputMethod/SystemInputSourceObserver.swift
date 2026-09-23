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
    private let languageModeController = LanguageModeController.shared
    private let preferences = PreferencesController.shared
    private var ownInputSourceID: String?
    private var shiftSwitchStyle: ShiftSwitchStyle?

    private init() {}

    /// Call once, at process launch.
    func start() {
        precondition(Thread.isMainThread)
        ownInputSourceID = Bundle.main.object(
            forInfoDictionaryKey: "TISInputSourceID"
        ) as? String
        shiftSwitchStyle = preferences.current.shiftSwitchStyle

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(selectedInputSourceDidChange),
            name: Notification.Name(
                kTISNotifySelectedKeyboardInputSourceChanged as String
            ),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        // The settings window lives in the same process as this observer, so
        // a preference change (position, tracking, size, …) should redraw the
        // already-visible indicator immediately rather than waiting for the
        // next input-source switch to pick it up.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesDidChange),
            name: PreferencesController.didChangeNotification,
            object: nil
        )

        refresh(showing: .selectedSource)
    }

    /// Which mode the indicator shows after a refresh.
    private enum DisplayedMode {
        /// A newly selected Jiukong mode is the user's latest choice in
        /// either Shift style, and every controller adopts it too.
        case selectedSource
        /// Anything else must not undo a language toggled inside Jiukong,
        /// which the selected source does not reflect.
        case currentLanguage
    }

    @objc private func selectedInputSourceDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.refresh(showing: .selectedSource)
        }
    }

    @objc private func preferencesDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.applyShiftSwitchStyleChange()
            self?.refresh(showing: .currentLanguage)
        }
    }

    /// Returning to the input-source style selects the mode Jiukong is
    /// actually in, so the input menu icon and later toggles start from it.
    private func applyShiftSwitchStyleChange() {
        let style = preferences.current.shiftSwitchStyle
        guard style != shiftSwitchStyle else {
            return
        }
        shiftSwitchStyle = style
        guard style == .inputSource,
              let ownInputSourceID,
              let selectedMode = LanguageMode.mode(
                  forInputSourceID: Self.currentInputSourceID(),
                  parentID: ownInputSourceID
              ),
              selectedMode != languageModeController.mode else {
            return
        }
        do {
            try InputSourceRegistrar.select(
                mode: languageModeController.mode,
                bundleIdentifier: ownInputSourceID
            )
        } catch {
            NSLog(
                "Jiukong Zhuyin could not select the %@ mode for the input-source Shift style: %@",
                languageModeController.mode.rawValue,
                error.localizedDescription
            )
        }
    }

    private func refresh(showing displayedMode: DisplayedMode) {
        precondition(Thread.isMainThread)
        let currentID = Self.currentInputSourceID()
        jiukongDebugLog(
            "SystemInputSourceObserver.refresh ownInputSourceID=\(ownInputSourceID ?? "nil") currentInputSourceID=\(currentID ?? "nil")"
        )
        guard let ownInputSourceID,
              let currentInputSourceID = currentID,
              let selectedMode = LanguageMode.mode(
                  forInputSourceID: currentInputSourceID,
                  parentID: ownInputSourceID
              )
        else {
            cursorIndicator.setActive(false)
            return
        }

        cursorIndicator.apply(preferences.current.cursorIndicator)
        switch displayedMode {
        case .selectedSource:
            cursorIndicator.update(mode: selectedMode)
        case .currentLanguage:
            cursorIndicator.update(mode: languageModeController.mode)
        }
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
