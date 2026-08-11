import AppKit
import InputMethodKit

/// The per-client InputMethodKit controller.
@objc(JiukongInputController)
final class InputController: IMKInputController {
    private static let passThroughModifiers: NSEvent.ModifierFlags = [
        .command,
        .control,
        .function,
        .option,
        .shift
    ]

    private static let currentSelectionRange = NSRange(
        location: NSNotFound,
        length: NSNotFound
    )

    private var inputSession = BopomofoInputSession()

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .keyDown,
              let inputClient = sender as? any IMKTextInput else {
            return false
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if !modifiers.intersection(Self.passThroughModifiers).isEmpty {
            apply(inputSession.finishBeforePassThrough(), to: inputClient)
            return false
        }

        guard let key = MacVirtualKeyResolver.key(for: event.keyCode) else {
            apply(inputSession.finishBeforePassThrough(), to: inputClient)
            return false
        }

        let result = inputSession.handle(key)
        apply(result, to: inputClient)
        return result.handled
    }

    override func commitComposition(_ sender: Any!) {
        finishComposition(using: sender)
    }

    override func deactivateServer(_ sender: Any!) {
        finishComposition(using: sender)
        super.deactivateServer(sender)
    }

    override func inputControllerWillClose() {
        finishComposition(using: client())
        super.inputControllerWillClose()
    }

    private func finishComposition(using sender: Any?) {
        guard inputSession.hasComposition else {
            return
        }

        guard let inputClient = inputClient(from: sender) else {
            _ = inputSession.discardComposition()
            return
        }

        apply(inputSession.commitComposition(), to: inputClient)
    }

    private func inputClient(from sender: Any?) -> (any IMKTextInput)? {
        if let inputClient = sender as? any IMKTextInput {
            return inputClient
        }

        return client()
    }

    private func apply(_ result: InputSessionResult, to inputClient: any IMKTextInput) {
        switch result.textAction {
        case .none:
            break
        case let .updateMarkedText(text):
            let markedText = text as NSString
            inputClient.setMarkedText(
                markedText,
                selectionRange: NSRange(location: markedText.length, length: 0),
                replacementRange: Self.currentSelectionRange
            )
        case .clearMarkedText:
            inputClient.setMarkedText(
                "" as NSString,
                selectionRange: NSRange(location: 0, length: 0),
                replacementRange: Self.currentSelectionRange
            )
        case let .commitText(text):
            inputClient.insertText(
                text as NSString,
                replacementRange: Self.currentSelectionRange
            )
        }
    }
}
