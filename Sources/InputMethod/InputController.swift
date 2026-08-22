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

    private static let punctuationLayout = PunctuationLayout.standard

    private static let currentSelectionRange = NSRange(
        location: NSNotFound,
        length: NSNotFound
    )

    private let candidateProvider: CharacterCandidateProvider?
    private lazy var candidatePresenter = CandidateWindowPresenter.shared
    private lazy var languageModeHUD = LanguageModeHUD.shared
    private lazy var cursorIndicator = CursorIndicatorController.shared
    private let languageModeController = LanguageModeController.shared
    private let preferences = PreferencesController.shared
    private var keyboardArrangement = PreferencesController.shared.current
        .keyboardArrangement
    private lazy var inputSession = BopomofoInputSession(
        keyboardLayout: keyboardArrangement.layout
    )
    private var compositionBuffer = CompositionBuffer()
    private var shiftToggleController = ShiftToggleController()
    private var candidateSession: CandidateSession?
    private var candidateSyllable: BopomofoSyllable?
    private var revisingUnitID: UUID?
    private var lastCandidateAnchor: NSRect?
    private var languageModeHUDToken: UUID?

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        do {
            let dictionary = try CharacterDictionary(bundle: .main)
            let preferences = PreferencesController.shared
            candidateProvider = CharacterCandidateProvider(
                dictionary: dictionary,
                learning: UserLearningService.shared,
                isAutomaticLearningEnabled: {
                    preferences.current.automaticLearningEnabled
                }
            )
        } catch {
            candidateProvider = nil
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
            finishComposition(reason: .lifecycle, using: inputClient)
            return false
        case .keyDown:
            shiftToggleController.noteKeyDown()
        default:
            return false
        }

        guard languageModeController.mode == .chinese else {
            return false
        }

        adoptKeyboardArrangementIfChanged(using: inputClient)

        if let command = CompositionSelectionCommandRouter.command(
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags
        ) {
            return handleCompositionSelectionCommand(
                command,
                inputClient: inputClient
            )
        }

        if !compositionBuffer.isEmpty,
           CandidateRevisionInteractionPolicy.routesCompositionCursor(
               candidateSession: candidateSession
           ),
           let command = CompositionCursorCommandRouter.command(
               keyCode: event.keyCode,
               modifierFlags: event.modifierFlags
           ) {
            handleCompositionCursorCommand(
                command,
                inputClient: inputClient
            )
            return true
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let resolvedKey = MacVirtualKeyResolver.key(for: event.keyCode)
        if let candidateSession,
           let command = CandidateCommandRouter.command(
               keyCode: event.keyCode,
               modifierFlags: event.modifierFlags,
               isExpanded: candidateSession.isExpanded,
               isExplicitSelectionContext:
                   candidateSession.revisionFocus != nil,
               mappedBopomofoComponent: resolvedKey.flatMap {
                   keyboardArrangement.layout.component(for: $0)
               },
               highlightedSelectionKeyIndex: candidateSession
                   .highlightedSelectionKeyIndex
           ) {
            if !CandidateRevisionInteractionPolicy.bypassesCandidateCommand(
                command,
                session: candidateSession
            ) {
                perform(command, inputClient: inputClient)
                return true
            }
        }

        // Caps Lock does not change Bopomofo input, so it must not change
        // punctuation either. Any real shortcut modifier still passes through.
        let punctuationModifiers = modifiers.subtracting(.capsLock)
        if punctuationModifiers.subtracting(.shift).isEmpty,
           let key = MacVirtualKeyResolver.key(for: event.keyCode),
           let punctuation = Self.punctuationLayout.punctuation(
               for: key,
               shifted: punctuationModifiers.contains(.shift)
           ) {
            return handlePunctuation(punctuation, inputClient: inputClient)
        }

        if !modifiers.intersection(Self.passThroughModifiers).isEmpty {
            finishComposition(
                reason: .implicitPassThrough,
                using: inputClient
            )
            return false
        }

        guard let key = resolvedKey else {
            finishComposition(
                reason: .implicitPassThrough,
                using: inputClient
            )
            return false
        }

        if handleCandidateMode() {
            return true
        }

        if handleBufferOnlyCommand(key, inputClient: inputClient) {
            return true
        }

        revisingUnitID = nil
        let result = inputSession.handle(key)
        return apply(result, to: inputClient)
    }

    override func commitComposition(_ sender: Any!) {
        finishComposition(reason: .lifecycle, using: sender)
    }

    /// The input-source menu shown from the macOS input menu.
    override func menu() -> NSMenu! {
        let menu = NSMenu(title: "久空輸入法")
        let settingsItem = NSMenuItem(
            title: "偏好設定…",
            action: #selector(showSettings(_:)),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        return menu
    }

    /// Opening settings ends the current composition first, so text cannot be
    /// left marked in a client that is about to lose focus to the window.
    @objc private func showSettings(_ sender: Any?) {
        resetTransientInputState()
        finishComposition(reason: .lifecycle, using: client())
        SettingsWindowController.shared.show()
    }

    override func activateServer(_ sender: Any!) {
        shiftToggleController.reset()
        synchronizeLanguageModeWithCurrentInputSource()
        startCursorIndicator()
        super.activateServer(sender)
    }

    override func deactivateServer(_ sender: Any!) {
        resetTransientInputState()
        finishComposition(reason: .lifecycle, using: sender)
        super.deactivateServer(sender)
    }

    override func inputControllerWillClose() {
        resetTransientInputState()
        finishComposition(reason: .lifecycle, using: client())
        super.inputControllerWillClose()
    }

    override func hidePalettes() {
        resetTransientInputState()
        finishComposition(reason: .lifecycle, using: client())
        super.hidePalettes()
    }

    @objc private func selectedInputSourceDidChange(_ notification: Notification) {
        let currentInputSourceID = Self.currentInputSourceID()
        let ownInputSourceID = Bundle.main.object(
            forInfoDictionaryKey: "TISInputSourceID"
        ) as? String

        if let mode = LanguageMode.mode(
            forInputSourceID: currentInputSourceID,
            parentID: ownInputSourceID
        ) {
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                if self.languageModeController.mode != mode {
                    self.finishComposition(
                        reason: .lifecycle,
                        using: self.client()
                    )
                }
                self.languageModeController.setMode(mode)
                self.cursorIndicator.update(mode: mode)
            }
            return
        }

        guard CandidateInputSourcePolicy.shouldFinishPresentation(
            currentInputSourceID: currentInputSourceID,
            ownInputSourceID: ownInputSourceID
        ) else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.resetTransientInputState()
            self.finishComposition(
                reason: .lifecycle,
                using: self.client()
            )
        }
    }

    private func finishComposition(
        reason: CandidateCommitReason,
        using sender: Any?
    ) {
        guard candidateSession != nil
            || inputSession.hasComposition
            || !compositionBuffer.isEmpty else {
            return
        }

        guard let inputClient = inputClient(from: sender) else {
            discardAllComposition()
            return
        }

        flushComposition(reason: reason, to: inputClient)
    }

    private func handleModifierChange(
        _ event: NSEvent,
        inputClient: any IMKTextInput
    ) -> Bool {
        let shouldToggle = shiftToggleController.handleFlagsChanged(
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags,
            preference: preferences.current.shiftKeyPreference
        )
        guard shouldToggle else {
            return false
        }

        finishComposition(reason: .lifecycle, using: inputClient)
        let mode: LanguageMode = languageModeController.mode == .chinese
            ? .english
            : .chinese

        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return false
        }

        do {
            try InputSourceRegistrar.select(
                mode: mode,
                bundleIdentifier: bundleIdentifier
            )
        } catch {
            NSLog(
                "Jiukong Zhuyin could not select the %@ mode: %@",
                mode.rawValue,
                error.localizedDescription
            )
            return false
        }

        languageModeController.setMode(mode)
        cursorIndicator.update(mode: mode)

        // The persistent indicator already answers "which mode am I in", so the
        // transient HUD would only duplicate it at a different position.
        guard !cursorIndicator.isEnabled else {
            return false
        }

        languageModeHUDToken = languageModeHUD.show(
            mode: mode,
            anchor: candidateAnchor(on: inputClient),
            clientWindowLevel: inputClient.windowLevel()
        )
        return false
    }

    /// Changing the arrangement mid-composition would reinterpret keys the user
    /// already pressed, so the current composition is finalized first.
    private func adoptKeyboardArrangementIfChanged(
        using inputClient: any IMKTextInput
    ) {
        let arrangement = preferences.current.keyboardArrangement
        guard arrangement != keyboardArrangement else {
            return
        }

        finishComposition(reason: .lifecycle, using: inputClient)
        keyboardArrangement = arrangement
        inputSession = BopomofoInputSession(keyboardLayout: arrangement.layout)
    }

    /// The indicator reads its settings when a client starts using this input
    /// method, so a change made in the settings window applies on the next
    /// activation without any observer.
    private func startCursorIndicator() {
        cursorIndicator.apply(preferences.current.cursorIndicator)
        cursorIndicator.update(mode: languageModeController.mode)
        cursorIndicator.setActive(true)
    }

    private func synchronizeLanguageModeWithCurrentInputSource() {
        let parentID = Bundle.main.object(
            forInfoDictionaryKey: "TISInputSourceID"
        ) as? String
        guard let mode = LanguageMode.mode(
            forInputSourceID: Self.currentInputSourceID(),
            parentID: parentID
        ) else {
            return
        }
        languageModeController.setMode(mode)
    }

    private func resetTransientInputState() {
        shiftToggleController.reset()
        cursorIndicator.setActive(false)
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

    @discardableResult
    private func apply(
        _ result: InputSessionResult,
        to inputClient: any IMKTextInput
    ) -> Bool {
        switch result.textAction {
        case .none:
            if !result.handled, !compositionBuffer.isEmpty {
                flushComposition(
                    reason: .implicitPassThrough,
                    to: inputClient
                )
            }
        case .updateMarkedText:
            compositionBuffer.clearSelection()
            updateMarkedComposition(on: inputClient)
        case .clearMarkedText:
            updateMarkedComposition(on: inputClient)
        case let .completeSyllable(syllable):
            compositionBuffer.clearSelection()
            beginCandidateSelection(for: syllable, inputClient: inputClient)
        case let .commitText(text):
            compositionBuffer.clearSelection()
            _ = compositionBuffer.append(
                text: text,
                pronunciation: text
            )
            flushComposition(
                reason: result.handled ? .returnKey : .implicitPassThrough,
                to: inputClient
            )
        }
        return result.handled
    }

    private func beginCandidateSelection(
        for syllable: BopomofoSyllable,
        inputClient: any IMKTextInput
    ) {
        let pronunciation = syllable.text
        revisingUnitID = nil
        guard let candidateProvider else {
            NSLog("Jiukong Zhuyin character conversion is unavailable.")
            appendLiteralReading(pronunciation, to: inputClient)
            return
        }

        do {
            let candidates = try candidateProvider.candidates(
                for: pronunciation,
                phraseQueries: compositionBuffer.phraseLookupQueries(
                    appending: pronunciation
                )
            )
            guard let session = CandidateSession(
                pronunciation: pronunciation,
                candidates: candidates
            ) else {
                NSLog("Jiukong Zhuyin dictionary lookup returned no candidates.")
                appendLiteralReading(pronunciation, to: inputClient)
                return
            }

            lastCandidateAnchor = nil
            candidateSession = session
            candidateSyllable = syllable
            updateMarkedComposition(on: inputClient)
        } catch {
            NSLog(
                "Jiukong Zhuyin dictionary lookup failed: %@",
                error.localizedDescription
            )
            appendLiteralReading(pronunciation, to: inputClient)
        }
    }

    private func handleCompositionCursorCommand(
        _ command: CompositionCursorCommand,
        inputClient: any IMKTextInput
    ) {
        let targetUnitID: UUID?

        if candidateSession != nil, revisingUnitID == nil {
            // Finish the active final reading before moving inside the buffer.
            _ = acceptPreferredCandidate(reason: .implicitPassThrough)
            switch command {
            case .previousReading:
                targetUnitID = compositionBuffer.lastReadingUnitID
            case .nextReading:
                targetUnitID = nil
            }
        } else {
            if candidateSession != nil {
                clearCandidatePresentation()
            }
            switch command {
            case .previousReading:
                targetUnitID = compositionBuffer.readingUnitID(
                    before: revisingUnitID
                ) ?? revisingUnitID
            case .nextReading:
                if let revisingUnitID {
                    targetUnitID = compositionBuffer.readingUnitID(
                        after: revisingUnitID
                    )
                } else {
                    targetUnitID = nil
                }
            }
        }

        guard let targetUnitID else {
            revisingUnitID = nil
            updateMarkedComposition(on: inputClient)
            return
        }
        beginRevisionCandidateSelection(
            for: targetUnitID,
            inputClient: inputClient
        )
    }

    private func beginRevisionCandidateSelection(
        for unitID: UUID,
        inputClient: any IMKTextInput
    ) {
        guard let focus = compositionBuffer.revisionFocus(for: unitID),
              let unit = compositionBuffer.unit(withID: unitID),
              unit.kind == .reading else {
            revisingUnitID = nil
            updateMarkedComposition(on: inputClient)
            return
        }

        compositionBuffer.clearSelection()
        revisingUnitID = unitID
        candidateSyllable = nil
        guard let candidateProvider else {
            updateMarkedComposition(on: inputClient)
            return
        }

        do {
            let candidates = try candidateProvider.candidates(
                for: unit.pronunciation
            )
            guard var session = CandidateSession(
                pronunciation: unit.pronunciation,
                candidates: candidates,
                revisionFocus: focus
            ) else {
                updateMarkedComposition(on: inputClient)
                return
            }
            if let currentCandidate = session.candidates.first(where: {
                $0.type == .character && $0.text == unit.text
            }) {
                session.updateHighlightedCandidate(currentCandidate.id)
            }

            lastCandidateAnchor = nil
            candidateSession = session
            updateMarkedComposition(on: inputClient)
            presentCandidates(session, inputClient: inputClient)
        } catch {
            NSLog(
                "Jiukong Zhuyin revision lookup failed: %@",
                error.localizedDescription
            )
            updateMarkedComposition(on: inputClient)
        }
    }

    private func handleCompositionSelectionCommand(
        _ command: CompositionSelectionCommand,
        inputClient: any IMKTextInput
    ) -> Bool {
        // An active raw syllable or candidate owns the inline suffix. Consume
        // Shift-arrow without accepting it or leaking selection to the client.
        guard candidateSession == nil, !inputSession.hasComposition else {
            return true
        }
        guard !compositionBuffer.isEmpty else {
            return false
        }

        revisingUnitID = nil
        switch command {
        case .expandBackward:
            compositionBuffer.expandSelectionBackward()
        case .shrinkForward:
            compositionBuffer.shrinkSelectionForward()
        }
        updateMarkedComposition(on: inputClient)
        return true
    }

    private func handleBufferOnlyCommand(
        _ key: KeyboardKey,
        inputClient: any IMKTextInput
    ) -> Bool {
        guard candidateSession == nil,
              !inputSession.hasComposition,
              !compositionBuffer.isEmpty else {
            return false
        }

        switch key {
        case .returnKey, .keypadEnter:
            if let phrase = compositionBuffer.selectedPhrase {
                _ = candidateProvider?.addUserPhrase(
                    phrase: phrase.text,
                    pronunciationSequence: phrase.pronunciationSequence
                )
            }
            flushComposition(reason: .returnKey, to: inputClient)
            return true
        case .escape:
            if revisingUnitID != nil {
                revisingUnitID = nil
                updateMarkedComposition(on: inputClient)
                return true
            }
            if !compositionBuffer.clearSelection() {
                compositionBuffer.discard()
            }
            updateMarkedComposition(on: inputClient)
            return true
        case .deleteBackward:
            if let revisingUnitID {
                let previousUnitID = compositionBuffer.readingUnitID(
                    before: revisingUnitID
                )
                _ = compositionBuffer.deleteUnit(withID: revisingUnitID)
                self.revisingUnitID = previousUnitID
            } else {
                compositionBuffer.deleteBackward()
            }
            updateMarkedComposition(on: inputClient)
            return true
        default:
            return false
        }
    }

    /// Returns true only when the current key was consumed by candidate mode.
    private func handleCandidateMode() -> Bool {
        guard candidateSession != nil else {
            return false
        }

        _ = acceptPreferredCandidate(reason: .implicitPassThrough)
        return false
    }

    private func perform(
        _ command: CandidateCommand,
        inputClient: any IMKTextInput
    ) {
        guard let session = candidateSession else {
            return
        }
        guard CandidateRevisionInteractionPolicy.allowsCandidateCommand(
            command,
            session: session
        ) else {
            return
        }

        switch CandidateCommandReducer.reduce(command, session: session) {
        case let .update(updatedSession):
            candidateSession = updatedSession
            updateMarkedComposition(on: inputClient)
            if updatedSession.presentsCandidatePanel {
                presentCandidates(updatedSession, inputClient: inputClient)
            }
        case let .commit(candidate, reason):
            _ = acceptCandidate(candidate, reason: reason)
            updateMarkedComposition(on: inputClient)
        case .cancel:
            if session.revisionMode == .choosing {
                returnToRevisionPositioning(
                    session,
                    inputClient: inputClient
                )
            } else if session.isExpanded {
                returnToInlineCandidatePreview(
                    session,
                    inputClient: inputClient
                )
            } else {
                cancelActiveCandidate(to: inputClient)
            }
        case .deleteBackward:
            resumeEditingAfterCandidateBackspace(to: inputClient)
        case .handledWithoutChange:
            break
        }
    }

    private func returnToRevisionPositioning(
        _ session: CandidateSession,
        inputClient: any IMKTextInput
    ) {
        guard let focus = session.revisionFocus else {
            cancelActiveCandidate(to: inputClient)
            return
        }

        var updatedSession = session
        _ = updatedSession.collapse()
        if let currentCandidate = updatedSession.candidates.first(where: {
            $0.type == .character && $0.text == focus.text
        }) {
            updatedSession.updateHighlightedCandidate(currentCandidate.id)
        }
        candidateSession = updatedSession
        updateMarkedComposition(on: inputClient)
        presentCandidates(updatedSession, inputClient: inputClient)
    }

    private func returnToInlineCandidatePreview(
        _ session: CandidateSession,
        inputClient: any IMKTextInput
    ) {
        var updatedSession = session
        _ = updatedSession.collapse()
        candidateSession = updatedSession
        candidatePresenter.hide(sessionID: session.id)
        updateMarkedComposition(on: inputClient)
    }

    /// Punctuation ends the active reading without ending the composition: the
    /// current candidate or raw syllable is accepted into the buffer, then the
    /// mark itself is appended as a unit that carries no reading.
    private func handlePunctuation(
        _ punctuation: String,
        inputClient: any IMKTextInput
    ) -> Bool {
        _ = acceptPreferredCandidate(reason: .punctuation)
        revisingUnitID = nil

        if let rawText = inputSession.takeRawComposition() {
            _ = compositionBuffer.append(
                text: rawText,
                pronunciation: rawText
            )
        }

        compositionBuffer.clearSelection()
        _ = compositionBuffer.appendPunctuation(punctuation)
        updateMarkedComposition(on: inputClient)
        return true
    }

    @discardableResult
    private func acceptPreferredCandidate(
        reason: CandidateCommitReason
    ) -> Bool {
        guard let session = candidateSession else {
            return false
        }

        return acceptCandidate(
            session.preferredCandidate,
            reason: reason
        )
    }

    @discardableResult
    private func acceptCandidate(
        _ candidate: Candidate,
        reason: CandidateCommitReason
    ) -> Bool {
        let fallbackReading = candidateSession?.pronunciation
        let revisionUnitID = revisingUnitID
        clearCandidatePresentation()

        if let revisionUnitID {
            guard compositionBuffer.replaceUnit(
                withID: revisionUnitID,
                candidate: candidate,
                reason: reason
            ) else {
                NSLog("Jiukong Zhuyin rejected an inconsistent revision candidate.")
                return false
            }
            return true
        }

        guard compositionBuffer.acceptCandidate(
            candidate,
            reason: reason
        ) else {
            if let fallbackReading {
                _ = compositionBuffer.append(
                    text: fallbackReading,
                    pronunciation: fallbackReading
                )
            }
            NSLog("Jiukong Zhuyin rejected an inconsistent candidate snapshot.")
            return false
        }
        return true
    }

    private func cancelActiveCandidate(to inputClient: any IMKTextInput) {
        if revisingUnitID != nil {
            clearCandidatePresentation()
        } else {
            discardCandidateState()
        }
        updateMarkedComposition(on: inputClient)
    }

    private func resumeEditingAfterCandidateBackspace(
        to inputClient: any IMKTextInput
    ) {
        if revisingUnitID != nil {
            clearCandidatePresentation()
            updateMarkedComposition(on: inputClient)
            return
        }
        guard let completedSyllable = candidateSyllable else {
            cancelActiveCandidate(to: inputClient)
            return
        }

        discardCandidateState()
        _ = apply(
            inputSession.resumeEditingAndDeleteBackward(completedSyllable),
            to: inputClient
        )
    }

    private func discardCandidateState() {
        clearCandidatePresentation()
        revisingUnitID = nil
    }

    private func clearCandidatePresentation() {
        let sessionID = candidateSession?.id
        candidateSession = nil
        candidateSyllable = nil
        lastCandidateAnchor = nil
        if let sessionID {
            candidatePresenter.hide(sessionID: sessionID)
        }
    }

    private func appendLiteralReading(
        _ pronunciation: String,
        to inputClient: any IMKTextInput
    ) {
        _ = compositionBuffer.append(
            text: pronunciation,
            pronunciation: pronunciation
        )
        updateMarkedComposition(on: inputClient)
    }

    /// Detaches every mutable input state before calling into the client. This
    /// makes lifecycle re-entry unable to insert or learn the same text twice.
    private func flushComposition(
        reason: CandidateCommitReason,
        to inputClient: any IMKTextInput
    ) {
        _ = acceptPreferredCandidate(reason: reason)
        revisingUnitID = nil

        if let rawText = inputSession.takeRawComposition() {
            _ = compositionBuffer.append(
                text: rawText,
                pronunciation: rawText
            )
        }

        guard let snapshot = compositionBuffer.takeCommitSnapshot() else {
            return
        }

        commitText(snapshot.text, to: inputClient)
        for pendingSelection in snapshot.pendingCandidateSelections {
            candidateProvider?.recordCommittedSelection(
                pendingSelection.candidate,
                reason: pendingSelection.reason
            )
        }
    }

    private func discardAllComposition() {
        discardCandidateState()
        _ = inputSession.discardComposition()
        compositionBuffer.discard()
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
            let localOffset: Int
            if let revisingUnitID {
                let localRange = compositionBuffer.markedSelectionRange(
                    focusedUnitID: revisingUnitID
                )
                localOffset = localRange.location + localRange.length
            } else {
                localOffset = markedRange.length
            }
            let caretRange = NSRange(
                location: markedRange.location + localOffset,
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

    private func updateMarkedComposition(
        on inputClient: any IMKTextInput
    ) {
        let presentation: CompositionPresentation?
        if revisingUnitID == nil,
           let candidateSession,
           candidateSession.revisionFocus == nil {
            presentation = CompositionPresentation.make(
                buffer: compositionBuffer,
                previewing: candidateSession.highlightedCandidate
            ) ?? CompositionPresentation.make(
                buffer: compositionBuffer,
                activeSuffix: candidateSession.pronunciation
            )
        } else {
            presentation = CompositionPresentation.make(
                buffer: compositionBuffer,
                activeSuffix: inputSession.markedText,
                focusedUnitID: revisingUnitID
            )
        }
        guard let presentation else {
            clearMarkedText(on: inputClient)
            return
        }

        let focusedRange = revisingUnitID.map {
            compositionBuffer.markedSelectionRange(focusedUnitID: $0)
        }
        let markedText: Any
        if let focusedRange {
            markedText = CompositionMarkedTextRenderer.make(
                presentation: presentation,
                focusedRange: focusedRange
            )
        } else {
            markedText = presentation.text as NSString
        }
        inputClient.setMarkedText(
            markedText,
            selectionRange: presentation.selectionRange,
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
            flushComposition(
                reason: .clientHandoff,
                to: inputClient
            )
        } else {
            discardAllComposition()
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

        _ = acceptCandidate(candidate, reason: .mouse)
        updateMarkedComposition(on: inputClient)
    }
}
