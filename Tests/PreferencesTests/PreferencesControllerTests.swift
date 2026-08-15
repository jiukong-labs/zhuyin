import Foundation
import XCTest

final class PreferencesControllerTests: XCTestCase {
    func testControllerAdoptsStoredPreferencesAtLaunch() {
        let store = ProbePreferencesStore(
            loaded: Preferences(
                shiftKeyPreference: .left,
                automaticLearningEnabled: false
            )
        )

        let controller = PreferencesController(
            store: store,
            notificationCenter: NotificationCenter()
        )

        XCTAssertEqual(controller.current.shiftKeyPreference, .left)
        XCTAssertFalse(controller.current.automaticLearningEnabled)
        XCTAssertEqual(store.loadCount, 1)
    }

    func testUpdatePersistsAndPostsExactlyOnce() {
        let store = ProbePreferencesStore()
        let center = NotificationCenter()
        let controller = PreferencesController(
            store: store,
            notificationCenter: center
        )
        var notifications = 0
        let observer = center.addObserver(
            forName: PreferencesController.didChangeNotification,
            object: controller,
            queue: nil
        ) { _ in
            notifications += 1
        }
        defer { center.removeObserver(observer) }

        controller.update { $0.shiftKeyPreference = .disabled }

        XCTAssertEqual(controller.current.shiftKeyPreference, .disabled)
        XCTAssertEqual(store.saved.map(\.shiftKeyPreference), [.disabled])
        XCTAssertEqual(notifications, 1)
    }

    func testUnchangedUpdateDoesNotWriteOrNotify() {
        let store = ProbePreferencesStore()
        let center = NotificationCenter()
        let controller = PreferencesController(
            store: store,
            notificationCenter: center
        )
        var notifications = 0
        let observer = center.addObserver(
            forName: PreferencesController.didChangeNotification,
            object: controller,
            queue: nil
        ) { _ in
            notifications += 1
        }
        defer { center.removeObserver(observer) }

        controller.update { $0.shiftKeyPreference = .both }

        XCTAssertEqual(store.saved, [])
        XCTAssertEqual(notifications, 0)
    }

    func testObserverCanReadCurrentWhileHandlingTheNotification() {
        let store = ProbePreferencesStore()
        let center = NotificationCenter()
        let controller = PreferencesController(
            store: store,
            notificationCenter: center
        )
        var observed: Preferences?
        let observer = center.addObserver(
            forName: PreferencesController.didChangeNotification,
            object: controller,
            queue: nil
        ) { [weak controller] _ in
            observed = controller?.current
        }
        defer { center.removeObserver(observer) }

        controller.update { $0.automaticLearningEnabled = false }

        XCTAssertEqual(observed?.automaticLearningEnabled, false)
    }

    func testReloadPicksUpAnExternalEditAndNotifiesOnce() {
        let store = ProbePreferencesStore()
        let center = NotificationCenter()
        let controller = PreferencesController(
            store: store,
            notificationCenter: center
        )
        var notifications = 0
        let observer = center.addObserver(
            forName: PreferencesController.didChangeNotification,
            object: controller,
            queue: nil
        ) { _ in
            notifications += 1
        }
        defer { center.removeObserver(observer) }

        store.loaded = Preferences(shiftKeyPreference: .right)
        XCTAssertEqual(controller.reload().shiftKeyPreference, .right)
        XCTAssertEqual(controller.reload().shiftKeyPreference, .right)

        XCTAssertEqual(controller.current.shiftKeyPreference, .right)
        XCTAssertEqual(notifications, 1)
    }

    func testConcurrentReadersAndWritersKeepOneConsistentValue() {
        let store = ProbePreferencesStore()
        let controller = PreferencesController(
            store: store,
            notificationCenter: NotificationCenter()
        )

        DispatchQueue.concurrentPerform(iterations: 200) { iteration in
            if iteration.isMultiple(of: 2) {
                controller.update {
                    $0.shiftKeyPreference = iteration.isMultiple(of: 4)
                        ? .left
                        : .right
                }
            } else {
                _ = controller.current
            }
        }

        XCTAssertTrue(
            [.left, .right].contains(controller.current.shiftKeyPreference)
        )
        XCTAssertEqual(controller.current, store.saved.last)
    }
}

private final class ProbePreferencesStore: PreferencesStoring {
    private let lock = NSLock()
    private var loadedStorage: Preferences
    private var savedStorage: [Preferences] = []
    private var loadCountStorage = 0

    init(loaded: Preferences = .default) {
        loadedStorage = loaded
    }

    var loaded: Preferences {
        get {
            lock.lock()
            defer { lock.unlock() }
            return loadedStorage
        }
        set {
            lock.lock()
            loadedStorage = newValue
            lock.unlock()
        }
    }

    var saved: [Preferences] {
        lock.lock()
        defer { lock.unlock() }
        return savedStorage
    }

    var loadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return loadCountStorage
    }

    func load() -> Preferences {
        lock.lock()
        defer { lock.unlock() }
        loadCountStorage += 1
        return loadedStorage
    }

    func save(_ preferences: Preferences) {
        lock.lock()
        savedStorage.append(preferences)
        lock.unlock()
    }
}
