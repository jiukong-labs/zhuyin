import Foundation

/// The process-wide settings owner.
///
/// InputMethodKit creates one controller per client, and the settings window
/// lives in the same process, so every reader shares this cache instead of
/// touching `UserDefaults` on each keystroke. Reads are lock-protected values;
/// change notifications are posted outside the lock so an observer can read
/// `current` without deadlocking.
final class PreferencesController {
    static let didChangeNotification = Notification.Name(
        "tw.idv.jiukong.PreferencesDidChange"
    )

    static let shared = PreferencesController()

    enum ChangeOrigin: String {
        case local
        case cloud
    }

    static let changeOriginUserInfoKey = "origin"

    private let store: PreferencesStoring
    private let notificationCenter: NotificationCenter
    private let lock = NSLock()
    private var cached: Preferences

    init(
        store: PreferencesStoring = UserDefaultsPreferencesStore(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.store = store
        self.notificationCenter = notificationCenter
        cached = store.load()
    }

    var current: Preferences {
        lock.lock()
        defer { lock.unlock() }
        return cached
    }

    /// Applies a change, persists it, and notifies observers only when the
    /// resulting value actually differs from the current one.
    @discardableResult
    func update(
        origin: ChangeOrigin = .local,
        _ transform: (inout Preferences) -> Void
    ) -> Preferences {
        lock.lock()
        var updated = cached
        transform(&updated)
        let changed = updated != cached
        if changed {
            cached = updated
            store.save(updated)
        }
        lock.unlock()

        if changed {
            notificationCenter.post(
                name: Self.didChangeNotification,
                object: self,
                userInfo: [Self.changeOriginUserInfoKey: origin.rawValue]
            )
        }
        return updated
    }

    /// Re-reads the persisted values, for example after the user edits the
    /// defaults domain outside the settings window.
    @discardableResult
    func reload() -> Preferences {
        lock.lock()
        let loaded = store.load()
        let changed = loaded != cached
        cached = loaded
        lock.unlock()

        if changed {
            notificationCenter.post(
                name: Self.didChangeNotification,
                object: self
            )
        }
        return loaded
    }
}
