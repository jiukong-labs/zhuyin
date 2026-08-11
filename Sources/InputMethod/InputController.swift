import AppKit
import InputMethodKit

/// The per-client InputMethodKit controller.
///
/// Milestone 1 deliberately leaves key events unhandled so the active app keeps
/// receiving normal keyboard input. Composition is introduced in Milestone 2.
@objc(JiukongInputController)
final class InputController: IMKInputController {
    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        false
    }
}
