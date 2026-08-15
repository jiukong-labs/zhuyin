import AppKit
import Carbon
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
    private lazy var candidatePresenter = CandidateWindowPresenter.shared
    private lazy var languageModeHUD = LanguageModeHUD.shared
    private let languageModeController = LanguageModeController.shared
    private var inputSession = BopomofoInputSession()
    private var shiftToggleController = ShiftToggleController()
    private var candidateSession: CandidateSession?
    private var candidateSyllable: BopomofoSyllable?
    private var lastCandidateAnchor: NSRect?
    private var languageModeHUDToken: UUID?

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

        super.init(server: server, delegate: delegate, client: inputClient)

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(selectedInputSourceDidChange(_:)),
            name: Self.selectedInputSourceChangedNotification,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(
            self,
            name: Self.selectedInputSourceChangedNotification,
            object: nil
        )
    }

    override func recognizedEvents(_ sender: Any!) -> Int {
        let eventMask: NSEvent.EventTypeMask = [
            .keyDown,
            .flagsChanged,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown
        ]
        return Int(eventMask.rawValue)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event,
              let inputClient = sender as? any IMKTextInput else {
            return false
        }

        switch event.type {
        case .flagsChanged:
            return handleModifierChange(event, inputClient: inputClient)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            shiftToggleController.reset()
            finishComposition(using: inputClient)
            return false
        case .keyDown:
            shiftToggleController.noteKeyDown()
        default:
            return false
        }

        guard languageModeController.mode == .chinese else {
            return false
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if let candidateSession,
           let command = CandidateCommandRouter.command(
               keyCode: event.keyCode,
               modifierFlags: event.modifierFlags,
               isExpanded: candidateSession.isExpanded
           ) {
            perform(command, inputClient: inputClient)
            return true
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

    override func activateServer(_ sender: Any!) {
        shiftToggleController.reset()
        super.activateServer(sender)
    }

    override func deactivateServer(_ sender: Any!) {
        resetTransientInputState()
        finishComposition(using: sender)
        super.deactivateServer(sender)
    }

    override func inputControllerWillClose() {
        resetTransientInputState()
        finishComposition(using: client())
        super.inputControllerWillClose()
    }

    override func hidePalettes() {
        resetTransientInputState()
        finishComposition(using: client())
        super.hidePalettes()
    }

    @objc private func selectedInputSourceDidChange(_ notification: Notification) {
        guard CandidateInputSourcePolicy.shouldFinishPresentation(
            currentInputSourceID: Self.currentInputSourceID(),
            ownInputSourceID: Bundle.main.object(
                forInfoDictionaryKey: "TISInputSourceID"
            ) as? String
        ) else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.resetTransientInputState()
            self.finishComposition(using: self.client())
        }
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

    private func handleModifierChange(
        _ event: NSEvent,
        inputClient: any IMKTextInput
    ) -> Bool {
        let shouldToggle = shiftToggleController.handleFlagsChanged(
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags,
            preference: .both
        )
        guard shouldToggle else {
            return false
        }

        finishComposition(using: inputClient)
        let mode = languageModeController.toggle()
        languageModeHUDToken = languageModeHUD.show(
            mode: mode,
            anchor: candidateAnchor(on: inputClient),
            clientWindowLevel: inputClient.windowLevel()
        )
        return false
    }

    private func resetTransientInputState() {
        shiftToggleController.reset()
        if let languageModeHUDToken {
            languageModeHUD.hide(token: languageModeHUDToken)
            self.languageModeHUDToken = nil
        }
    }

    private func inputClient(from sender: Any?) -> (any IMKTextInput)? {
        if let inputClient = sender as? any IMKTextInput {
            return inputClient
        }

        return client()
    }

    private static let selectedInputSourceChangedNotification = Notification.Name(
        kTISNotifySelectedKeyboardInputSourceChanged as String
    )

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

            lastCandidateAnchor = nil
            candidateSession = session
            candidateSyllable = syllable
            setMarkedText(pronunciation, on: inputClient)
            presentCandidates(session, inputClient: inputClient)
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

        _ = commitPreferredCandidate(to: inputClient)
        return false
    }

    private func finishCandidateBeforePassThrough(
        to inputClient: any IMKTextInput
    ) {
        guard candidateSession != nil else {
            return
        }

        _ = commitPreferredCandidate(to: inputClient)
    }

    private func perform(
        _ command: CandidateCommand,
        inputClient: any IMKTextInput
    ) {
        guard let session = candidateSession else {
            return
        }

        switch CandidateCommandReducer.reduce(command, session: session) {
        case let .update(updatedSession):
            candidateSession = updatedSession
            presentCandidates(updatedSession, inputClient: inputClient)
        case let .commit(candidate):
            commitCandidate(candidate, to: inputClient)
        case .cancel:
            cancelActiveCandidate(to: inputClient)
        case .deleteBackward:
            resumeEditingAfterCandidateBackspace(to: inputClient)
        case .handledWithoutChange:
            break
        }
    }

    @discardableResult
    private func commitPreferredCandidate(
        to inputClient: any IMKTextInput
    ) -> Bool {
        guard let session = candidateSession else {
            return false
        }

        commitCandidate(session.preferredCandidate, to: inputClient)
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

    private func resumeEditingAfterCandidateBackspace(
        to inputClient: any IMKTextInput
    ) {
        guard let completedSyllable = candidateSyllable else {
            cancelActiveCandidate(to: inputClient)
            return
        }

        discardCandidateState()
        apply(
            inputSession.resumeEditingAndDeleteBackward(completedSyllable),
            to: inputClient
        )
    }

    private func discardCandidateState() {
        let sessionID = candidateSession?.id
        candidateSession = nil
        candidateSyllable = nil
        lastCandidateAnchor = nil
        if let sessionID {
            candidatePresenter.hide(sessionID: sessionID)
        }
    }

    private func presentCandidates(
        _ session: CandidateSession,
        inputClient: any IMKTextInput
    ) {
        candidatePresenter.present(
            session: session,
            anchor: candidateAnchor(on: inputClient),
            clientWindowLevel: inputClient.windowLevel(),
            delegate: self
        )
    }

    private func candidateAnchor(on inputClient: any IMKTextInput) -> NSRect {
        let markedRange = inputClient.markedRange()
        if markedRange.location != NSNotFound,
           markedRange.length != NSNotFound,
           markedRange.location <= Int.max - markedRange.length {
            let caretRange = NSRange(
                location: markedRange.location + markedRange.length,
                length: 0
            )
            if let caretRect = firstValidRect(
                for: caretRange,
                inputClient: inputClient
            ) {
                lastCandidateAnchor = caretRect
                return caretRect
            }
        }

        let selectedRange = inputClient.selectedRange()
        if selectedRange.location != NSNotFound,
           let caretRect = firstValidRect(
               for: NSRange(location: selectedRange.location, length: 0),
               inputClient: inputClient
           ) {
            lastCandidateAnchor = caretRect
            return caretRect
        }

        var lineRect = NSRect.zero
        _ = inputClient.attributes(
            forCharacterIndex: 0,
            lineHeightRectangle: &lineRect
        )
        lineRect = lineRect.standardized
        if isValidAnchor(lineRect) {
            lastCandidateAnchor = lineRect
            return lineRect
        }

        if let lastCandidateAnchor {
            return lastCandidateAnchor
        }

        let fallbackFrame = NSScreen.main?.visibleFrame ?? NSRect(
            x: 0,
            y: 0,
            width: 1,
            height: 1
        )
        return NSRect(
            x: fallbackFrame.midX,
            y: fallbackFrame.midY,
            width: 1,
            height: 1
        )
    }

    private func firstValidRect(
        for characterRange: NSRange,
        inputClient: any IMKTextInput
    ) -> NSRect? {
        var actualRange = NSRange(location: NSNotFound, length: 0)
        let rect = inputClient.firstRect(
            forCharacterRange: characterRange,
            actualRange: &actualRange
        ).standardized
        return isValidAnchor(rect) ? rect : nil
    }

    private func isValidAnchor(_ rect: NSRect) -> Bool {
        rect.origin.x.isFinite
            && rect.origin.y.isFinite
            && rect.size.width.isFinite
            && rect.size.height.isFinite
            && rect.size.height > 0
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

extension InputController: CandidateWindowPresenterDelegate {
    func candidateWindowPresenter(
        _ presenter: CandidateWindowPresenter,
        requestsFinalizationOf sessionID: UUID
    ) {
        guard candidateSession?.id == sessionID else {
            return
        }

        if let inputClient = inputClient(from: client()) {
            _ = commitPreferredCandidate(to: inputClient)
        } else {
            discardCandidateState()
        }
    }

    func candidateWindowPresenter(
        _ presenter: CandidateWindowPresenter,
        choseCandidateAt index: Int,
        sessionID: UUID
    ) {
        guard let session = candidateSession,
              session.id == sessionID,
              let candidate = session.candidate(at: index),
              let inputClient = inputClient(from: client()) else {
            return
        }

        commitCandidate(candidate, to: inputClient)
    }
}
