import Foundation

/// Decides which input controller the client is currently talking to.
///
/// `activateServer` and `deactivateServer` do not arrive in a tidy order when
/// switching apps. Traces show LINE and Finder activating again after the
/// next app's controller had activated, then deactivating: following only
/// the latest call left no current controller while VS Code, never
/// deactivated, kept delivering every Shift tap to a controller treated as
/// stale. A controller that has not deactivated therefore resumes, and a
/// controller that receives an event is the one the client routes keys to.
/// Traces never showed an event reaching a controller after it deactivated.
struct ActiveControllerTracker<Controller: AnyObject> {
    private struct Entry {
        weak var controller: Controller?
    }

    /// Controllers activated and not yet deactivated, oldest first.
    private var activated: [Entry] = []
    private(set) weak var current: Controller?

    /// Returns true when the current controller changed.
    @discardableResult
    mutating func activated(_ controller: Controller) -> Bool {
        promote(controller)
    }

    /// Returns true when the current controller changed.
    @discardableResult
    mutating func deactivated(_ controller: Controller) -> Bool {
        activated.removeAll { $0.controller == nil || $0.controller === controller }
        guard current === controller else {
            return false
        }
        current = activated.last?.controller
        return true
    }

    /// Returns true when the current controller changed.
    @discardableResult
    mutating func receivedEvent(from controller: Controller) -> Bool {
        guard current !== controller else {
            return false
        }
        return promote(controller)
    }

    private mutating func promote(_ controller: Controller) -> Bool {
        activated.removeAll { $0.controller == nil || $0.controller === controller }
        activated.append(Entry(controller: controller))
        let changed = current !== controller
        current = controller
        return changed
    }
}
