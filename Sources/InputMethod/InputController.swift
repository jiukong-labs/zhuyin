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
    /// Whether Left/Right has entered explicit text-caret positioning. The
    /// following unit is optional because an active caret at the text end has
    /// no unit on its right.
    private var isRevisionCaretActive = false
    private var revisingUnitID: UUID?
    /// The reading replaced by the currently open revision chooser. This is
    /// intentionally independent from `revisingUnitID`: candidates target the
    /// character before the caret while the latter remains the unit after it.
    private var revisionCandidateUnitID: UUID?
    /// The existing unit a not-yet-accepted candidate should be inserted
    /// before, captured when a new reading is typed while the caret is
    /// positioned via revision-focus navigation (rather than appended at the
    /// end of the buffer as usual). Cleared whenever the candidate it belongs
    /// to is accepted or abandoned.
    private var pendingInsertionAnchorUnitID: UUID?
    /// Distinguishes pronunciation revision from ordinary new input and
    /// prevents an extra Backspace after the final component from leaking into
    /// unrelated text.
    private var isEditingRevisionPronunciation = false
    private var lastCandidateAnchor: NSRect?
    /// A caret captured before the client receives its first marked text.
    /// Some web-backed editors can report the insertion point correctly only
    /// before composition begins, so keep it for the life of that composition.
    private var compositionFallbackAnchor: NSRect?
    /// The most recent click delivered for this client. This remains useful
    /// when a web editor never exposes usable text geometry at all.
    private var lastClientClickAnchor: NSRect?
    private var phraseSelectionPresentationID: UUID?
    private var savedPhraseConfirmation: SavedUserPhraseConfirmation?

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        do {
            let dictionary = try CharacterDictionary(bundle: .main)
            let preferences = PreferencesController.shared
            candidateProvider = CharacterCandidateProvider(
                dictionary: dictionary,
                learning: UserLearningService.shared,
                isAutomaticLearningEnabled: {
                    preferences.current.automaticLearningEnabled
                },
                showsRareCandidates: {
                    preferences.current.showsRareCandidates
                },
                isCandidateDisplayable: {
                    CandidateTextDisplayability.canRender($0)
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
            hideSavedPhraseConfirmation()
            finishComposition(reason: .lifecycle, using: inputClient)
            let clickLocation = NSEvent.mouseLocation
            let clickAnchor = NSRect(
                x: clickLocation.x,
                y: clickLocation.y,
                width: 1,
                height: 1
            )
            lastClientClickAnchor = clickAnchor
            logCandidateAnchor(clickAnchor, source: "recordClientClick")
            return false
        case .keyDown:
            shiftToggleController.noteKeyDown()
            hideSavedPhraseConfirmation()
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

        if let command = CompositionDeletionCommandRouter.command(
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags
        ), handleCompositionDeletionCommand(
            command,
            inputClient: inputClient
        ) {
            return true
        }

        if let command = CompositionRevisionCandidateCommandRouter.command(
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags,
            hasRevisionCaret: isRevisionCaretActive,
            isChoosingCandidates:
                candidateSession?.revisionMode == .choosing
        ), handleCompositionRevisionCandidateCommand(
            command,
            inputClient: inputClient
        ) {
            return true
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

        if let asciiText = OptionASCIIShortcut.text(
            for: resolvedKey,
            modifierFlags: event.modifierFlags
        ) {
            finishComposition(
                reason: .implicitPassThrough,
                using: inputClient
            )
            commitText(asciiText, to: inputClient)
            return true
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

        // A positioned caret is about to be superseded by a freshly typed
        // reading: remember it as where the resulting candidate should be
        // inserted, rather than at the buffer's end. Left untouched (not
        // cleared) on every later keystroke of the same syllable, so a
        // backspace-and-retype mid-syllable does not lose the anchor.
        if isRevisionCaretActive, let revisingUnitID {
            pendingInsertionAnchorUnitID = revisingUnitID
        }
        isRevisionCaretActive = false
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
        super.activateServer(sender)
        shiftToggleController.reset()
        synchronizeLanguageModeWithCurrentInputSource()
        UserLearningService.shared.refreshCloudIfNeeded()
        startCursorIndicator()
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
                self.languageModeController.synchronize(withSystemMode: mode)
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
            preference: preferences.current.shiftKeyPreference,
            systemKeyDownEventCount: CGEventSource.counterForEventType(
                .combinedSessionState,
                eventType: .keyDown
            )
        )
        guard shouldToggle else {
            return false
        }

        finishComposition(reason: .lifecycle, using: inputClient)
        let mode = languageModeController.mode.toggled
        guard let parentID = Bundle.main.object(
            forInfoDictionaryKey: "TISInputSourceID"
        ) as? String else {
            return false
        }

        do {
            try InputSourceRegistrar.select(
                mode: mode,
                bundleIdentifier: parentID
            )
        } catch {
            NSLog(
                "Jiukong Zhuyin could not select the %@ mode: %@",
                mode.rawValue,
                error.localizedDescription
            )
            return false
        }

        languageModeController.synchronize(withSystemMode: mode)
        cursorIndicator.update(mode: mode)
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

    /// `SystemInputSourceObserver` is the process-wide owner of whether the
    /// indicator is showing at all, but it only reacts to the system's
    /// selected-input-source notification. Re-applying here too means a
    /// settings-window change or the bootstrap mode selected in
    /// `synchronizeLanguageModeWithCurrentInputSource()` is reflected
    /// immediately on activation instead of waiting for that notification to
    /// round-trip back.
    private func startCursorIndicator() {
        cursorIndicator.apply(preferences.current.cursorIndicator)
        cursorIndicator.update(mode: languageModeController.mode)
        cursorIndicator.setActive(true)
    }

    private func synchronizeLanguageModeWithCurrentInputSource() {
        let parentID = Bundle.main.object(
            forInfoDictionaryKey: "TISInputSourceID"
        ) as? String
        let currentInputSourceID = Self.currentInputSourceID()
        guard let mode = LanguageMode.mode(
            forInputSourceID: currentInputSourceID,
            parentID: parentID
        ) else {
            // A freshly enabled input method can initially activate through
            // its parent source. Select the concrete mode immediately so the
            // system input menu uses that mode's 中/A icon instead of the
            // application icon.
            guard currentInputSourceID == parentID,
                  let parentID else {
                return
            }
            do {
                try InputSourceRegistrar.select(
                    mode: languageModeController.mode,
                    bundleIdentifier: parentID
                )
            } catch {
                NSLog(
                    "Jiukong Zhuyin could not select its initial mode: %@",
                    error.localizedDescription
                )
            }
            return
        }
        languageModeController.synchronize(withSystemMode: mode)
    }

    private func resetTransientInputState() {
        shiftToggleController.reset()
        hideSavedPhraseConfirmation()
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
            captureCompositionFallbackAnchorIfNeeded(on: inputClient)
            compositionBuffer.clearSelection()
            updateMarkedComposition(on: inputClient)
        case .clearMarkedText:
            updateMarkedComposition(on: inputClient)
        case let .completeSyllable(syllable):
            compositionBuffer.clearSelection()
            beginCandidateSelection(for: syllable, inputClient: inputClient)
        case let .commitText(text):
            compositionBuffer.clearSelection()
            _ = storeLiteralReading(text)
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
        isRevisionCaretActive = false
        revisingUnitID = nil
        revisionCandidateUnitID = nil
        guard let candidateProvider else {
            NSLog("Jiukong Zhuyin character conversion is unavailable.")
            appendLiteralReading(pronunciation, to: inputClient)
            return
        }

        do {
            let candidates = try candidateProvider.candidates(
                for: pronunciation,
                phraseQueries: phraseLookupQueries(appending: pronunciation)
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

    /// Routes phrase lookup to context ending just before the pending
    /// insertion anchor when one is set, or the trailing end of the buffer
    /// otherwise.
    private func phraseLookupQueries(
        appending pronunciation: String
    ) -> [CompositionPhraseQuery] {
        // Pronunciation revision replaces one removed character. It must not
        // absorb preceding readings into a phrase candidate while doing so.
        if isEditingRevisionPronunciation {
            return []
        }
        if let pendingInsertionAnchorUnitID {
            return compositionBuffer.phraseLookupQueries(
                appending: pronunciation,
                before: pendingInsertionAnchorUnitID
            )
        }
        return compositionBuffer.phraseLookupQueries(appending: pronunciation)
    }

    private func handleCompositionCursorCommand(
        _ command: CompositionCursorCommand,
        inputClient: any IMKTextInput
    ) {
        let targetUnitID: UUID?

        if candidateSession != nil, !isRevisionCaretActive {
            // Finish the active final reading before moving inside the buffer.
            _ = acceptPreferredCandidate(reason: .implicitPassThrough)
            if let revisingUnitID {
                // The reading just accepted landed mid-buffer (the caret had
                // been positioned there before typing it), so navigate from
                // it like any other positioned unit instead of assuming it
                // landed at the buffer's end.
                switch command {
                case .previousReading:
                    targetUnitID = compositionBuffer.readingUnitID(
                        before: revisingUnitID
                    ) ?? revisingUnitID
                case .nextReading:
                    targetUnitID = compositionBuffer.readingUnitID(
                        after: revisingUnitID
                    )
                }
            } else {
                switch command {
                case .previousReading:
                    targetUnitID = compositionBuffer.lastReadingUnitID
                case .nextReading:
                    targetUnitID = nil
                }
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

        beginRevisionPositioning(
            for: targetUnitID,
            inputClient: inputClient
        )
    }

    private func beginRevisionPositioning(
        for unitID: UUID?,
        inputClient: any IMKTextInput
    ) {
        isEditingRevisionPronunciation = false
        pendingInsertionAnchorUnitID = nil
        compositionFallbackAnchor = nil
        if candidateSession != nil {
            clearCandidatePresentation()
        }
        if let unitID,
           compositionBuffer.revisionFocus(for: unitID) == nil {
            isRevisionCaretActive = false
            revisingUnitID = nil
            updateMarkedComposition(on: inputClient)
            return
        }

        compositionBuffer.clearSelection()
        isRevisionCaretActive = true
        revisingUnitID = unitID
        candidateSyllable = nil
        updateMarkedComposition(on: inputClient)
    }

    private func handleCompositionRevisionCandidateCommand(
        _ command: CompositionRevisionCandidateCommand,
        inputClient: any IMKTextInput
    ) -> Bool {
        switch command {
        case .openCandidates:
            guard !inputSession.hasComposition,
                  candidateSession == nil,
                  isRevisionCaretActive else {
                return false
            }
            beginRevisionCandidateSelection(
                before: revisingUnitID,
                inputClient: inputClient
            )
            return true
        case .returnToPositioning:
            guard candidateSession?.revisionMode == .choosing else {
                return false
            }
            returnToRevisionPositioning(inputClient: inputClient)
            return true
        }
    }

    private func beginRevisionCandidateSelection(
        before caretFollowingUnitID: UUID?,
        inputClient: any IMKTextInput
    ) {
        isEditingRevisionPronunciation = false
        pendingInsertionAnchorUnitID = nil
        revisionCandidateUnitID = nil
        guard let focus = compositionBuffer.revisionFocusForCandidate(
            atCaretFollowing: caretFollowingUnitID
        ),
              let unit = compositionBuffer.unit(withID: focus.unitID),
              unit.kind == .reading else {
            updateMarkedComposition(on: inputClient)
            return
        }

        compositionBuffer.clearSelection()
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
            _ = session.beginRevisionChoosing()

            lastCandidateAnchor = nil
            revisionCandidateUnitID = unit.id
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
        // A raw syllable and an expanded candidate list still own their
        // arrows. A revision caret, however, is a valid phrase-selection
        // starting point; a compact chooser is closed before extending from
        // that focused unit.
        guard !inputSession.hasComposition else {
            return true
        }
        guard !compositionBuffer.isEmpty else {
            return false
        }

        if isEditingRevisionPronunciation {
            isEditingRevisionPronunciation = false
            pendingInsertionAnchorUnitID = nil
        }

        let selectionAnchor: CompositionPhraseSelectionAnchor =
            isRevisionCaretActive
                ? .caret(followingUnitID: revisingUnitID)
                : .bufferEdge
        if let candidateSession {
            guard candidateSession.revisionFocus != nil,
                  !candidateSession.isExpanded,
                  isRevisionCaretActive else {
                return true
            }
            clearCandidatePresentation()
        }

        let didExtendSelection: Bool
        switch command {
        case .extendLeft:
            didExtendSelection = compositionBuffer.extendSelectionLeft(
                from: selectionAnchor
            )
        case .extendRight:
            didExtendSelection = compositionBuffer.extendSelectionRight(
                from: selectionAnchor
            )
        }
        guard didExtendSelection else {
            updateMarkedComposition(on: inputClient)
            return true
        }

        isRevisionCaretActive = false
        revisingUnitID = nil
        updateMarkedComposition(on: inputClient)
        presentPhraseSelection(on: inputClient)
        return true
    }

    /// An explicit inline cursor or phrase range owns both physical deletion
    /// keys before candidate routing. Backspace reopens the reading immediately
    /// left of the cursor; forward Delete reopens the reading immediately to
    /// its right. Both remove one Bopomofo component per key press.
    private func handleCompositionDeletionCommand(
        _ command: CompositionDeletionCommand,
        inputClient: any IMKTextInput
    ) -> Bool {
        if isEditingRevisionPronunciation {
            if inputSession.hasComposition {
                _ = apply(
                    inputSession.handle(.deleteBackward),
                    to: inputClient
                )
            }
            // Once the chosen character has become a raw reading, either
            // physical deletion key continues removing its components. After
            // the initial is gone, keep consuming repeats so they cannot reach
            // an unrelated marked unit or client character.
            return true
        }

        guard !inputSession.hasComposition,
              !compositionBuffer.isEmpty,
              isRevisionCaretActive || compositionBuffer.hasSelection else {
            return false
        }

        if isRevisionCaretActive {
            switch command {
            case .deleteBackward:
                resumeEditingPreviousRevisionUnitAfterBackspace(
                    before: revisingUnitID,
                    inputClient: inputClient
                )
            case .deleteForward:
                if let revisingUnitID {
                    resumeEditingFocusedRevisionUnitAfterForwardDelete(
                        at: revisingUnitID,
                        inputClient: inputClient
                    )
                }
            }
        } else {
            if candidateSession != nil {
                clearCandidatePresentation()
            }
            _ = compositionBuffer.deleteBackward()
            isRevisionCaretActive = false
            revisingUnitID = nil
            updateMarkedComposition(on: inputClient)
        }
        return true
    }

    private func handleBufferOnlyCommand(
        _ key: KeyboardKey,
        inputClient: any IMKTextInput
    ) -> Bool {
        guard candidateSession == nil,
              !inputSession.hasComposition,
              !compositionBuffer.isEmpty
                || isEditingRevisionPronunciation else {
            return false
        }

        switch key {
        case .returnKey, .keypadEnter:
            let confirmation: SavedUserPhraseConfirmation?
            if let phrase = compositionBuffer.selectedPhrase,
               candidateProvider?.addUserPhrase(
                    phrase: phrase.text,
                    pronunciationSequence: phrase.pronunciationSequence
               ) == true {
                confirmation = SavedUserPhraseConfirmation(
                    phrase: phrase.text,
                    pronunciationSequence: phrase.pronunciationSequence
                )
            } else {
                confirmation = nil
            }
            flushComposition(reason: .returnKey, to: inputClient)
            if let confirmation {
                presentSavedPhraseConfirmation(
                    confirmation,
                    on: inputClient
                )
            }
            return true
        case .escape:
            if isEditingRevisionPronunciation {
                isEditingRevisionPronunciation = false
                pendingInsertionAnchorUnitID = nil
                updateMarkedComposition(on: inputClient)
                return true
            }
            if isRevisionCaretActive {
                isRevisionCaretActive = false
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
            if isRevisionCaretActive {
                resumeEditingPreviousRevisionUnitAfterBackspace(
                    before: revisingUnitID,
                    inputClient: inputClient
                )
            } else {
                compositionBuffer.deleteBackward()
                updateMarkedComposition(on: inputClient)
            }
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
        inputClient: any IMKTextInput
    ) {
        guard candidateSession?.revisionFocus != nil else {
            cancelActiveCandidate(to: inputClient)
            return
        }
        clearCandidatePresentation()
        updateMarkedComposition(on: inputClient)
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
        let insertionAnchorUnitID = pendingInsertionAnchorUnitID
        _ = acceptPreferredCandidate(reason: .punctuation)
        isRevisionCaretActive = false
        revisingUnitID = nil

        if let rawText = inputSession.takeRawComposition() {
            _ = storeLiteralReading(rawText)
        }
        isEditingRevisionPronunciation = false
        pendingInsertionAnchorUnitID = nil

        compositionBuffer.clearSelection()
        if let insertionAnchorUnitID,
           compositionBuffer.insert(
               text: punctuation,
               pronunciation: punctuation,
               before: insertionAnchorUnitID,
               kind: .punctuation
           ) == nil {
            _ = compositionBuffer.appendPunctuation(punctuation)
        } else if insertionAnchorUnitID == nil {
            _ = compositionBuffer.appendPunctuation(punctuation)
        }
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
        let revisionUnitID = revisionCandidateUnitID
        let insertionAnchorUnitID = pendingInsertionAnchorUnitID
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

        if let insertionAnchorUnitID {
            let insertedUnits = compositionBuffer.insertCandidate(
                candidate,
                before: insertionAnchorUnitID,
                reason: reason
            )
            guard !insertedUnits.isEmpty else {
                if let fallbackReading {
                    _ = compositionBuffer.append(
                        text: fallbackReading,
                        pronunciation: fallbackReading
                    )
                }
                NSLog("Jiukong Zhuyin rejected an inconsistent insertion candidate.")
                return false
            }
            // The anchor itself keeps the caret, exactly like a text cursor
            // sitting right before it: each further reading keeps landing at
            // the same spot, so consecutively typed syllables accumulate to
            // its left in the order they were typed.
            isRevisionCaretActive = true
            revisingUnitID = insertionAnchorUnitID
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
        if isRevisionCaretActive {
            clearCandidatePresentation()
        } else {
            discardCandidateState()
        }
        updateMarkedComposition(on: inputClient)
    }

    private func resumeEditingAfterCandidateBackspace(
        to inputClient: any IMKTextInput
    ) {
        if isRevisionCaretActive {
            resumeEditingPreviousRevisionUnitAfterBackspace(
                before: revisingUnitID,
                inputClient: inputClient
            )
            return
        }
        guard let completedSyllable = candidateSyllable else {
            cancelActiveCandidate(to: inputClient)
            return
        }

        // Backspacing into the same syllable's partial composition continues
        // the same pending insertion, so its anchor must survive the reset.
        let insertionAnchorUnitID = pendingInsertionAnchorUnitID
        let wasEditingRevisionPronunciation = isEditingRevisionPronunciation
        discardCandidateState()
        pendingInsertionAnchorUnitID = insertionAnchorUnitID
        isEditingRevisionPronunciation = wasEditingRevisionPronunciation
        _ = apply(
            inputSession.resumeEditingAndDeleteBackward(completedSyllable),
            to: inputClient
        )
    }

    /// Removes the reading immediately before the revision caret, restores its
    /// exact stored pronunciation to the parser, and applies one Backspace.
    /// The following unit remains the insertion anchor, so the partial reading
    /// and its eventual replacement stay directly before it.
    private func resumeEditingPreviousRevisionUnitAfterBackspace(
        before focusedUnitID: UUID?,
        inputClient: any IMKTextInput
    ) {
        guard let unitID = compositionBuffer.readingUnitID(
            immediatelyBeforeCaretAt: focusedUnitID
        ) else {
            return
        }
        resumeEditingRevisionUnitPronunciation(
            unitID,
            insertionAnchorUnitID: focusedUnitID,
            inputClient: inputClient
        )
    }

    /// Restores the reading on the right side of the revision caret and uses
    /// the following surviving unit as its insertion anchor. A final focused
    /// unit has no anchor and naturally remains at the buffer end.
    private func resumeEditingFocusedRevisionUnitAfterForwardDelete(
        at focusedUnitID: UUID,
        inputClient: any IMKTextInput
    ) {
        resumeEditingRevisionUnitPronunciation(
            focusedUnitID,
            insertionAnchorUnitID: compositionBuffer.unitID(
                immediatelyAfter: focusedUnitID
            ),
            inputClient: inputClient
        )
    }

    /// Removes one converted reading, restores its exact pronunciation to the
    /// parser, and immediately deletes the tone component. `insertionAnchor`
    /// preserves the removed unit's original position while it is raw.
    private func resumeEditingRevisionUnitPronunciation(
        _ unitID: UUID,
        insertionAnchorUnitID: UUID?,
        inputClient: any IMKTextInput
    ) {
        guard let unit = compositionBuffer.unit(withID: unitID),
              unit.kind == .reading,
              let syllable = BopomofoSyllable(
                  pronunciation: unit.pronunciation
              ) else {
            clearCandidatePresentation()
            updateMarkedComposition(on: inputClient)
            return
        }

        clearCandidatePresentation()
        guard compositionBuffer.deleteUnit(withID: unitID) != nil else {
            updateMarkedComposition(on: inputClient)
            return
        }

        isRevisionCaretActive = false
        revisingUnitID = nil
        pendingInsertionAnchorUnitID = insertionAnchorUnitID
        isEditingRevisionPronunciation = true
        _ = apply(
            inputSession.resumeEditingAndDeleteBackward(syllable),
            to: inputClient
        )
    }

    private func discardCandidateState() {
        clearCandidatePresentation()
        isRevisionCaretActive = false
        revisingUnitID = nil
    }

    private func clearCandidatePresentation() {
        let sessionID = candidateSession?.id
        candidateSession = nil
        candidateSyllable = nil
        revisionCandidateUnitID = nil
        lastCandidateAnchor = nil
        pendingInsertionAnchorUnitID = nil
        isEditingRevisionPronunciation = false
        if let sessionID {
            candidatePresenter.hide(sessionID: sessionID)
        }
    }

    private func presentPhraseSelection(
        on inputClient: any IMKTextInput
    ) {
        guard let status = compositionBuffer.phraseSelectionStatus else {
            hidePhraseSelectionPresentation()
            return
        }

        let presentationID = phraseSelectionPresentationID ?? UUID()
        phraseSelectionPresentationID = presentationID
        candidatePresenter.presentPhraseSelection(
            id: presentationID,
            displayText: status.displayText,
            anchor: candidateAnchor(on: inputClient),
            clientWindowLevel: inputClient.windowLevel()
        )
    }

    private func hidePhraseSelectionPresentation() {
        guard let phraseSelectionPresentationID else {
            return
        }
        self.phraseSelectionPresentationID = nil
        candidatePresenter.hidePhraseSelection(
            id: phraseSelectionPresentationID
        )
    }

    private func presentSavedPhraseConfirmation(
        _ confirmation: SavedUserPhraseConfirmation,
        on inputClient: any IMKTextInput
    ) {
        savedPhraseConfirmation = confirmation
        candidatePresenter.presentSavedPhraseConfirmation(
            confirmation,
            anchor: candidateAnchor(on: inputClient),
            clientWindowLevel: inputClient.windowLevel(),
            delegate: self
        )
    }

    private func hideSavedPhraseConfirmation() {
        guard let savedPhraseConfirmation else {
            return
        }
        self.savedPhraseConfirmation = nil
        candidatePresenter.hideSavedPhraseConfirmation(
            id: savedPhraseConfirmation.id
        )
    }

    private func appendLiteralReading(
        _ pronunciation: String,
        to inputClient: any IMKTextInput
    ) {
        if let anchorUnitID = storeLiteralReading(pronunciation),
           compositionBuffer.revisionFocus(for: anchorUnitID) != nil {
            // The anchor keeps the caret; see the matching comment in
            // `acceptCandidate`.
            isRevisionCaretActive = true
            revisingUnitID = anchorUnitID
        }
        updateMarkedComposition(on: inputClient)
    }

    /// Stores a raw reading at the positioned caret when one exists, or at
    /// the buffer end otherwise. Returning the surviving anchor lets an
    /// interactive caller keep the revision caret there; final commit callers can
    /// ignore it.
    @discardableResult
    private func storeLiteralReading(_ pronunciation: String) -> UUID? {
        isEditingRevisionPronunciation = false
        if let anchorUnitID = pendingInsertionAnchorUnitID {
            pendingInsertionAnchorUnitID = nil
            if compositionBuffer.insert(
                text: pronunciation,
                pronunciation: pronunciation,
                before: anchorUnitID
            ) != nil {
                return anchorUnitID
            }
        }

        pendingInsertionAnchorUnitID = nil
        _ = compositionBuffer.append(
            text: pronunciation,
            pronunciation: pronunciation
        )
        return nil
    }

    /// Detaches every mutable input state before calling into the client. This
    /// makes lifecycle re-entry unable to insert or learn the same text twice.
    private func flushComposition(
        reason: CandidateCommitReason,
        to inputClient: any IMKTextInput
    ) {
        hidePhraseSelectionPresentation()
        _ = acceptPreferredCandidate(reason: reason)
        isRevisionCaretActive = false
        revisingUnitID = nil

        if let rawText = inputSession.takeRawComposition() {
            _ = storeLiteralReading(rawText)
        }
        isEditingRevisionPronunciation = false
        pendingInsertionAnchorUnitID = nil

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
        hidePhraseSelectionPresentation()
        discardCandidateState()
        _ = inputSession.discardComposition()
        compositionBuffer.discard()
        compositionFallbackAnchor = nil
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
        let localAnchorRange: NSRange
        if isRevisionCaretActive {
            localAnchorRange = compositionBuffer.markedSelectionRange(
                focusedUnitID: revisingUnitID
            )
        } else if compositionBuffer.hasSelection {
            localAnchorRange = compositionBuffer.markedSelectionRange
        } else {
            localAnchorRange = NSRange(
                location: markedRange.length,
                length: 0
            )
        }

        // A non-empty revision/phrase range is the text that must remain
        // visible. Some web-backed clients report its trailing caret on a
        // different visual line, so query the actual glyph rectangle first.
        let requestedAnchorRanges = CandidateAnchorRanges.requestedRanges(
            markedRange: markedRange,
            localAnchorRange: localAnchorRange
        )
        jiukongDebugLog(
            "candidateAnchor marked=\(NSStringFromRange(markedRange)) local=\(NSStringFromRange(localAnchorRange)) selected=\(NSStringFromRange(inputClient.selectedRange()))"
        )
        for anchorRange in requestedAnchorRanges {
            if let anchorRect = firstValidRect(
                for: anchorRange,
                inputClient: inputClient
            ) {
                lastCandidateAnchor = anchorRect
                logCandidateAnchor(anchorRect, source: "markedRange")
                return anchorRect
            }
        }

        let selectedRange = inputClient.selectedRange()
        if selectedRange.location != NSNotFound,
           let caretRect = firstValidRect(
               for: NSRange(location: selectedRange.location, length: 0),
               inputClient: inputClient
           ) {
            lastCandidateAnchor = caretRect
            logCandidateAnchor(caretRect, source: "selectedRange")
            return caretRect
        }

        if let selectionRect = visibleSelectionAnchor(on: inputClient) {
            lastCandidateAnchor = selectionRect
            logCandidateAnchor(selectionRect, source: "visibleSelection")
            return selectionRect
        }

        if let lineCharacterIndex = CandidateAnchorRanges
            .lineHeightCharacterIndex(
                markedRange: markedRange,
                localAnchorRange: localAnchorRange,
                selectedRange: selectedRange
            ) {
            var lineRect = NSRect.zero
            _ = inputClient.attributes(
                forCharacterIndex: lineCharacterIndex,
                lineHeightRectangle: &lineRect
            )
            lineRect = lineRect.standardized
            jiukongDebugLog(
                "candidateAnchor line index=\(lineCharacterIndex) rect=\(NSStringFromRect(lineRect)) valid=\(isValidAnchor(lineRect))"
            )
            if isValidAnchor(lineRect) {
                lastCandidateAnchor = lineRect
                logCandidateAnchor(lineRect, source: "lineHeight")
                return lineRect
            }
        }

        if let lastCandidateAnchor {
            logCandidateAnchor(lastCandidateAnchor, source: "lastValid")
            return lastCandidateAnchor
        }

        if let compositionFallbackAnchor {
            logCandidateAnchor(
                compositionFallbackAnchor,
                source: "precomposition"
            )
            return compositionFallbackAnchor
        }

        if let lastClientClickAnchor {
            logCandidateAnchor(lastClientClickAnchor, source: "lastClientClick")
            return lastClientClickAnchor
        }

        // No client-reported rect was trustworthy (see
        // `CandidateAnchorValidation`) and there is no prior anchor to
        // reuse. Anchoring near the mouse keeps the panel close to where
        // the user is actually looking instead of a fixed screen position,
        // matching the cursor indicator's handling of web-backed clients.
        let mouseLocation = NSEvent.mouseLocation
        let mouseAnchor = NSRect(
            x: mouseLocation.x,
            y: mouseLocation.y,
            width: 1,
            height: 1
        )
        logCandidateAnchor(mouseAnchor, source: "currentMouse")
        return mouseAnchor
    }

    private func captureCompositionFallbackAnchorIfNeeded(
        on inputClient: any IMKTextInput
    ) {
        guard compositionFallbackAnchor == nil,
              inputClient.markedRange().location == NSNotFound else {
            return
        }

        if let selectionRect = visibleSelectionAnchor(on: inputClient) {
            compositionFallbackAnchor = selectionRect
            logCandidateAnchor(selectionRect, source: "captureVisibleSelection")
            return
        }

        let selectedRange = inputClient.selectedRange()
        if selectedRange.location != NSNotFound,
           let caretRect = firstValidRect(
               for: NSRange(location: selectedRange.location, length: 0),
               inputClient: inputClient
           ) {
            compositionFallbackAnchor = caretRect
            logCandidateAnchor(caretRect, source: "captureSelectedRange")
            return
        }

        if let lastClientClickAnchor {
            compositionFallbackAnchor = lastClientClickAnchor
            logCandidateAnchor(lastClientClickAnchor, source: "captureLastClick")
        }
    }

    /// macOS 14 added a selection rectangle specifically for positioning text
    /// accessories. Prefer it when the client exposes it; older or proxied
    /// clients continue through the established range queries.
    private func visibleSelectionAnchor(
        on inputClient: any IMKTextInput
    ) -> NSRect? {
        guard #available(macOS 14.0, *),
              let textInputClient = inputClient as? any NSTextInputClient,
              let rect = textInputClient.unionRectInVisibleSelectedRange?
                  .standardized,
              isValidAnchor(rect) else {
            return nil
        }
        return rect
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
        let isValid = isValidAnchor(rect)
        jiukongDebugLog(
            "candidateAnchor firstRect requested=\(NSStringFromRange(characterRange)) actual=\(NSStringFromRange(actualRange)) rect=\(NSStringFromRect(rect)) valid=\(isValid)"
        )
        return isValid ? rect : nil
    }

    private func logCandidateAnchor(_ rect: NSRect, source: String) {
        jiukongDebugLog(
            "candidateAnchor chose source=\(source) rect=\(NSStringFromRect(rect)) mouse=\(NSStringFromPoint(NSEvent.mouseLocation))"
        )
    }

    private func isValidAnchor(_ rect: NSRect) -> Bool {
        // Outlook's web-backed editor can return a non-empty stub rect at the
        // top-left of `visibleFrame` (below the menu bar), while other clients
        // use the full-screen corner. Validate against both coordinate-space
        // boundaries before trusting the client-provided caret rectangle.
        let screenBoundaryFrames = NSScreen.screens.flatMap {
            [$0.frame, $0.visibleFrame]
        }
        return CandidateAnchorValidation.isPlausibleCaretAnchor(
            rect,
            screenFrames: screenBoundaryFrames
        )
    }

    private func updateMarkedComposition(
        on inputClient: any IMKTextInput
    ) {
        if !compositionBuffer.hasSelection {
            hidePhraseSelectionPresentation()
        }
        let presentation: CompositionPresentation?
        if !isRevisionCaretActive,
           let candidateSession,
           candidateSession.revisionFocus == nil {
            presentation = CompositionPresentation.make(
                buffer: compositionBuffer,
                previewing: candidateSession.highlightedCandidate,
                insertionAnchorUnitID: pendingInsertionAnchorUnitID
            ) ?? CompositionPresentation.make(
                buffer: compositionBuffer,
                activeSuffix: candidateSession.pronunciation
            )
        } else {
            presentation = CompositionPresentation.make(
                buffer: compositionBuffer,
                activeSuffix: inputSession.markedText,
                focusedUnitID: revisingUnitID,
                insertionAnchorUnitID: pendingInsertionAnchorUnitID
            )
        }
        guard let presentation else {
            clearMarkedText(on: inputClient)
            return
        }

        let phraseRange = compositionBuffer.hasSelection
            ? presentation.selectionRange
            : nil
        let markedText: Any
        if let phraseRange {
            markedText = CompositionMarkedTextRenderer.make(
                presentation: presentation,
                highlightedRange: phraseRange
            )
        } else if isRevisionCaretActive {
            markedText = CompositionMarkedTextRenderer.makeUnhighlighted(
                presentation: presentation
            )
        } else {
            markedText = presentation.text as NSString
        }
        let clientSelectionRange = phraseRange == nil
            ? presentation.selectionRange
            : presentation.caretAfterSelectionRange
        inputClient.setMarkedText(
            markedText,
            selectionRange: clientSelectionRange,
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

    func candidateWindowPresenter(
        _ presenter: CandidateWindowPresenter,
        requestsDeletionOfCandidateAt index: Int,
        sessionID: UUID
    ) {
        guard var session = candidateSession,
              session.id == sessionID,
              let candidate = session.candidate(at: index),
              candidate.isUserPhrase,
              let candidateProvider,
              let inputClient = inputClient(from: client()),
              candidateProvider.deleteUserPhrase(
                  phrase: candidate.text,
                  pronunciationSequence: candidate.pronunciationSequence
              ) else {
            return
        }

        do {
            let phraseQueries = session.revisionFocus == nil
                ? phraseLookupQueries(appending: session.pronunciation)
                : []
            let refreshedCandidates = try candidateProvider.candidates(
                for: session.pronunciation,
                phraseQueries: phraseQueries
            )
            if session.replaceCandidates(refreshedCandidates) {
                candidateSession = session
                updateMarkedComposition(on: inputClient)
                presentCandidates(session, inputClient: inputClient)
                return
            }
        } catch {
            NSLog(
                "Jiukong Zhuyin could not refresh candidates after deleting a user phrase: %@",
                error.localizedDescription
            )
        }

        let remainingCandidates = session.candidates.filter {
            $0.id != candidate.id
        }
        if session.replaceCandidates(remainingCandidates) {
            candidateSession = session
            updateMarkedComposition(on: inputClient)
            presentCandidates(session, inputClient: inputClient)
        } else {
            let pronunciation = session.pronunciation
            clearCandidatePresentation()
            appendLiteralReading(pronunciation, to: inputClient)
        }
    }

    func candidateWindowPresenter(
        _ presenter: CandidateWindowPresenter,
        requestsDeletionOf confirmation: SavedUserPhraseConfirmation
    ) {
        guard savedPhraseConfirmation?.id == confirmation.id else {
            return
        }

        let succeeded = candidateProvider?.deleteUserPhrase(
            phrase: confirmation.phrase,
            pronunciationSequence: confirmation.pronunciationSequence
        ) ?? false
        if succeeded {
            savedPhraseConfirmation = nil
        }
        presenter.resolveSavedPhraseDeletion(
            id: confirmation.id,
            succeeded: succeeded
        )
    }
}
