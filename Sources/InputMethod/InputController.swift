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

    private let dictionary: CharacterDictionary?
    private let candidatePresenter: SystemCandidatePresenter?
    private var inputSession = BopomofoInputSession()
    private var candidateSession: CandidateSession?

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        do {
            dictionary = try CharacterDictionary(bundle: .main)
        } catch {
            dictionary = nil
            NSLog(
                "Jiukong Zhuyin could not load its character dictionary: %@",
                error.localizedDescription
            )
        }

        if let server {
            candidatePresenter = SystemCandidatePresenter(server: server)
            if candidatePresenter == nil {
                NSLog(
                    "Jiukong Zhuyin could not initialize the system candidate panel."
                )
            }
        } else {
            candidatePresenter = nil
            NSLog(
                "Jiukong Zhuyin received an input controller without an IMK server."
            )
        }

        super.init(server: server, delegate: delegate, client: inputClient)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .keyDown,
              let inputClient = sender as? any IMKTextInput else {
            return false
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if let candidateSession {
            if let navigation = SystemCandidateKeyRouting.navigation(
                keyCode: event.keyCode,
                modifierFlags: event.modifierFlags
            ) {
                moveCandidateSelection(navigation)
                return true
            }

            if let selectionKeyIndex = SystemCandidateKeyRouting
                .selectionKeyIndex(
                    keyCode: event.keyCode,
                    modifierFlags: event.modifierFlags
                ) {
                let candidate: String?
                switch candidatePresenter?.candidate(
                    atVisibleIndex: selectionKeyIndex,
                    from: candidateSession
                ) {
                case let .selected(visibleCandidate):
                    candidate = visibleCandidate
                case .emptySlot, .selectionFailed:
                    candidate = nil
                case .notReady, nil:
                    candidate = candidateSession.candidate(
                        atSelectionKeyIndex: selectionKeyIndex
                    )
                }

                if let candidate,
                   let selection = candidateSession.validatedSelection(
                       candidate
                   ) {
                    commitCandidate(selection, to: inputClient)
                }
                return true
            }
        }

        if !modifiers.intersection(Self.passThroughModifiers).isEmpty {
            finishCandidateBeforePassThrough(to: inputClient)
            apply(inputSession.finishBeforePassThrough(), to: inputClient)
            return false
        }

        guard let key = MacVirtualKeyResolver.key(for: event.keyCode) else {
            finishCandidateBeforePassThrough(to: inputClient)
            apply(inputSession.finishBeforePassThrough(), to: inputClient)
            return false
        }

        if handleCandidateMode(key, inputClient: inputClient) {
            return true
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

    override func candidates(_ sender: Any!) -> [Any]! {
        candidateSession?.candidates.map { $0 as NSString } ?? []
    }

    override func candidateSelectionChanged(
        _ candidateString: NSAttributedString!
    ) {
        guard let candidate = candidateString?.string else {
            return
        }

        candidateSession?.updateHighlightedCandidate(candidate)
    }

    override func candidateSelected(_ candidateString: NSAttributedString!) {
        guard let candidate = candidateString?.string,
              let session = candidateSession else {
            return
        }

        guard let selection = session.validatedSelection(candidate) else {
            if let inputClient = inputClient(from: client()) {
                cancelActiveCandidate(to: inputClient)
            } else {
                discardCandidateState()
            }
            return
        }

        guard let inputClient = inputClient(from: client()) else {
            discardCandidateState()
            return
        }

        commitCandidate(selection, to: inputClient)
    }

    private func finishComposition(using sender: Any?) {
        guard candidateSession != nil || inputSession.hasComposition else {
            return
        }

        guard let inputClient = inputClient(from: sender) else {
            discardCandidateState()
            _ = inputSession.discardComposition()
            return
        }

        if commitPreferredCandidate(to: inputClient) {
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
            clearMarkedText(on: inputClient)
        case let .completeSyllable(syllable):
            beginCandidateSelection(for: syllable, inputClient: inputClient)
        case let .commitText(text):
            commitText(text, to: inputClient)
        }
    }

    private func beginCandidateSelection(
        for syllable: BopomofoSyllable,
        inputClient: any IMKTextInput
    ) {
        let pronunciation = syllable.text
        guard let dictionary else {
            NSLog("Jiukong Zhuyin character conversion is unavailable.")
            commitText(pronunciation, to: inputClient)
            return
        }

        guard let candidatePresenter else {
            NSLog("Jiukong Zhuyin candidate presentation is unavailable.")
            commitText(pronunciation, to: inputClient)
            return
        }

        do {
            let candidates = try dictionary.candidates(for: pronunciation)
            guard let session = CandidateSession(
                pronunciation: pronunciation,
                candidates: candidates
            ) else {
                NSLog("Jiukong Zhuyin dictionary lookup returned no candidates.")
                commitText(pronunciation, to: inputClient)
                return
            }

            candidateSession = session
            setMarkedText(pronunciation, on: inputClient)
            candidatePresenter.updateAndShow()
        } catch {
            NSLog(
                "Jiukong Zhuyin dictionary lookup failed: %@",
                error.localizedDescription
            )
            commitText(pronunciation, to: inputClient)
        }
    }

    /// Returns true only when the current key was consumed by candidate mode.
    private func handleCandidateMode(
        _ key: KeyboardKey,
        inputClient: any IMKTextInput
    ) -> Bool {
        guard candidateSession != nil else {
            return false
        }

        switch key {
        case .escape, .deleteBackward:
            cancelActiveCandidate(to: inputClient)
            return true
        case .returnKey, .keypadEnter:
            _ = commitPreferredCandidate(to: inputClient)
            return true
        default:
            if candidatePresenter?.isVisible == true {
                _ = commitPreferredCandidate(to: inputClient)
            } else {
                cancelActiveCandidate(to: inputClient)
            }
            return false
        }
    }

    private func finishCandidateBeforePassThrough(
        to inputClient: any IMKTextInput
    ) {
        guard candidateSession != nil else {
            return
        }

        if candidatePresenter?.isVisible == true {
            _ = commitPreferredCandidate(to: inputClient)
        } else {
            cancelActiveCandidate(to: inputClient)
        }
    }

    private func moveCandidateSelection(_ navigation: CandidateNavigation) {
        guard let candidate = candidateSession?.candidate(after: navigation) else {
            return
        }

        _ = candidatePresenter?.selectCandidate(candidate)
        candidateSession?.updateHighlightedCandidate(candidate)
    }

    @discardableResult
    private func commitPreferredCandidate(
        to inputClient: any IMKTextInput
    ) -> Bool {
        guard let session = candidateSession else {
            return false
        }

        let panelSelection = candidatePresenter?.selectedCandidateText
            .flatMap(session.validatedSelection)
        let preferredSelection = session.highlightedCandidate
            ?? panelSelection
            ?? session.preferredCandidate
        commitCandidate(preferredSelection, to: inputClient)
        return true
    }

    private func commitCandidate(
        _ candidate: String,
        to inputClient: any IMKTextInput
    ) {
        discardCandidateState()
        commitText(candidate, to: inputClient)
    }

    private func cancelActiveCandidate(to inputClient: any IMKTextInput) {
        discardCandidateState()
        clearMarkedText(on: inputClient)
    }

    private func discardCandidateState() {
        candidateSession = nil
        candidatePresenter?.hide()
    }

    private func setMarkedText(
        _ text: String,
        on inputClient: any IMKTextInput
    ) {
        let markedText = text as NSString
        inputClient.setMarkedText(
            markedText,
            selectionRange: NSRange(location: markedText.length, length: 0),
            replacementRange: Self.currentSelectionRange
        )
    }

    private func clearMarkedText(on inputClient: any IMKTextInput) {
        inputClient.setMarkedText(
            "" as NSString,
            selectionRange: NSRange(location: 0, length: 0),
            replacementRange: Self.currentSelectionRange
        )
    }

    private func commitText(_ text: String, to inputClient: any IMKTextInput) {
        inputClient.insertText(
            text as NSString,
            replacementRange: Self.currentSelectionRange
        )
    }
}
