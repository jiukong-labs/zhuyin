import AppKit

struct SavedUserPhraseConfirmation: Equatable {
    let id: UUID
    let phrase: String
    let pronunciationSequence: [String]

    init(
        id: UUID = UUID(),
        phrase: String,
        pronunciationSequence: [String]
    ) {
        self.id = id
        self.phrase = phrase
        self.pronunciationSequence = pronunciationSequence
    }

    var displayText: String {
        "已儲存：【\(phrase)】"
    }

    var deletionToolTip: String {
        "刪除剛儲存的使用者詞「\(phrase)」；不會刪除文件中的文字"
    }
}

protocol CandidateWindowPresenterDelegate: AnyObject {
    func candidateWindowPresenter(
        _ presenter: CandidateWindowPresenter,
        requestsFinalizationOf sessionID: UUID
    )

    func candidateWindowPresenter(
        _ presenter: CandidateWindowPresenter,
        choseCandidateAt index: Int,
        sessionID: UUID
    )

    func candidateWindowPresenter(
        _ presenter: CandidateWindowPresenter,
        requestsActionForCandidateAt index: Int,
        sessionID: UUID
    )

    func candidateWindowPresenter(
        _ presenter: CandidateWindowPresenter,
        requestsDeletionOf confirmation: SavedUserPhraseConfirmation
    )
}

private final class CandidatePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class CandidateButton: NSButton {
    let candidateIndex: Int
    let sessionID: UUID

    init(candidateIndex: Int, sessionID: UUID) {
        self.candidateIndex = candidateIndex
        self.sessionID = sessionID
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CandidateButton does not support NSCoder initialization.")
    }

    override var acceptsFirstResponder: Bool { false }
    override var needsPanelToBecomeKey: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

private final class SavedPhraseDeleteButton: NSButton {
    override var acceptsFirstResponder: Bool { false }
    override var needsPanelToBecomeKey: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

private final class CandidateActionButton: NSButton {
    let candidateIndex: Int
    let sessionID: UUID

    init(candidateIndex: Int, sessionID: UUID) {
        self.candidateIndex = candidateIndex
        self.sessionID = sessionID
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError(
            "CandidateActionButton does not support NSCoder initialization."
        )
    }

    override var acceptsFirstResponder: Bool { false }
    override var needsPanelToBecomeKey: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

private enum CandidateWindowPresentationText {
    /// Nonbreaking spaces keep a visible gap between the candidate and its
    /// control. The ideographic space reserves the slot occupied by the
    /// overlaid button, keeping the complete candidate-gap-× group centered.
    static let actionGap = "\u{00A0}\u{00A0}"
    static let actionSlot = "　"

    /// Every phrase carries the inline remove control, built-in ones included.
    /// A character never does: removing it would leave its reading without a
    /// candidate.
    static func hasInlineAction(_ candidate: Candidate) -> Bool {
        candidate.pinned || candidate.type == .phrase
    }

    static func sizingText(for candidate: Candidate) -> String {
        candidate.text
            + (candidate.pinned ? "\u{00A0}★" : "")
            + (hasInlineAction(candidate) ? actionGap + actionSlot : "")
    }
}

private final class CandidateGridView: NSView {
    var onChoose: ((UUID, Int) -> Void)?
    var onAction: ((UUID, Int) -> Void)?

    private var buttons: [Int: CandidateButton] = [:]
    private var actionButtons: [Int: CandidateActionButton] = [:]
    private var representedIndices: [Int] = []
    private var representedSizingTexts: [String] = []
    private var representedSessionID: UUID?
    private var representedMode: CandidatePresentationMode?

    override var isFlipped: Bool { true }

    func update(with session: CandidateSession) {
        let indices: [Int]
        switch session.presentationMode {
        case .compact:
            indices = Array(session.compactCandidateRange)
        case .expanded:
            indices = Array(session.candidates.indices)
        }
        let sizingTexts = indices.compactMap {
            session.candidate(at: $0).map(
                CandidateWindowPresentationText.sizingText(for:)
            )
        }

        if representedSessionID != session.id
            || representedMode != session.presentationMode
            || representedIndices != indices
            || representedSizingTexts != sizingTexts {
            rebuild(
                indices: indices,
                sizingTexts: sizingTexts,
                session: session
            )
        }

        updateButtonAppearance(for: session)
    }

    func revealHighlightedCandidate(in session: CandidateSession) {
        if let selectedButton = buttons[session.highlightedIndex] {
            scrollToVisible(selectedButton.frame.insetBy(dx: -4, dy: -4))
        }
    }

    func clear() {
        buttons.values.forEach { $0.removeFromSuperview() }
        actionButtons.values.forEach { $0.removeFromSuperview() }
        buttons.removeAll()
        actionButtons.removeAll()
        representedIndices.removeAll()
        representedSizingTexts.removeAll()
        representedSessionID = nil
        representedMode = nil
        setFrameSize(.zero)
    }

    private func rebuild(
        indices: [Int],
        sizingTexts: [String],
        session: CandidateSession
    ) {
        buttons.values.forEach { $0.removeFromSuperview() }
        actionButtons.values.forEach { $0.removeFromSuperview() }
        buttons.removeAll()
        actionButtons.removeAll()
        representedIndices = indices
        representedSizingTexts = sizingTexts
        representedSessionID = session.id
        representedMode = session.presentationMode

        let metrics = CandidateWindowSizing.gridMetrics(
            candidateTexts: sizingTexts,
            mode: session.presentationMode
        )
        setFrameSize(metrics.documentSize)

        for (position, candidateIndex) in indices.enumerated() {
            guard metrics.cellFrames.indices.contains(position) else {
                continue
            }
            let button = CandidateButton(
                candidateIndex: candidateIndex,
                sessionID: session.id
            )
            button.frame = metrics.cellFrames[position]
            button.target = self
            button.action = #selector(candidateClicked(_:))
            button.isBordered = false
            button.focusRingType = .none
            button.alignment = .center
            button.wantsLayer = true
            button.layer?.cornerRadius = 7
            addSubview(button)
            buttons[candidateIndex] = button

            guard let candidate = session.candidate(at: candidateIndex),
                  CandidateWindowPresentationText.hasInlineAction(candidate)
            else {
                continue
            }
            let actionButton = CandidateActionButton(
                candidateIndex: candidateIndex,
                sessionID: session.id
            )
            actionButton.target = self
            actionButton.action = #selector(candidateActionClicked(_:))
            actionButton.isBordered = false
            actionButton.focusRingType = .none
            actionButton.alignment = .center
            addSubview(actionButton)
            actionButtons[candidateIndex] = actionButton
        }
    }

    private func updateButtonAppearance(for session: CandidateSession) {
        for (candidateIndex, button) in buttons {
            guard let candidate = session.candidate(at: candidateIndex) else {
                continue
            }

            let selectionKey: String
            if session.selectionPageRange.contains(candidateIndex) {
                selectionKey = "\(candidateIndex - session.selectionPageRange.lowerBound + 1) "
            } else {
                selectionKey = ""
            }
            let isSelected = candidateIndex == session.highlightedIndex
            let foregroundColor: NSColor = isSelected
                ? .alternateSelectedControlTextColor
                : .labelColor
            let font = NSFont.systemFont(ofSize: 18, weight: .medium)
            let titleText = selectionKey
                + CandidateWindowPresentationText.sizingText(for: candidate)
            button.attributedTitle = NSAttributedString(
                string: titleText,
                attributes: [
                    .font: font,
                    .foregroundColor: foregroundColor
                ]
            )
            button.layer?.backgroundColor = isSelected
                ? NSColor.controlAccentColor.cgColor
                : NSColor.clear.cgColor
            button.layer?.borderWidth = isSelected ? 1 : 0
            button.layer?.borderColor = isSelected
                ? NSColor.selectedControlTextColor.withAlphaComponent(0.7).cgColor
                : NSColor.clear.cgColor
            button.toolTip = "候選 \(candidateIndex + 1)／\(session.candidates.count)：\(candidate.text)"
            button.setAccessibilityLabel(
                "候選 \(candidateIndex + 1)／\(session.candidates.count)，\(candidate.text)"
            )
            button.setAccessibilityValue(isSelected ? "已選取" : nil)

            if let actionButton = actionButtons[candidateIndex] {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: foregroundColor
                ]
                actionButton.attributedTitle = NSAttributedString(
                    string: "×",
                    attributes: attributes
                )
                let titleWidth = (titleText as NSString).size(
                    withAttributes: attributes
                ).width
                let reservedWidth = (CandidateWindowPresentationText
                    .actionSlot as NSString).size(
                    withAttributes: attributes
                ).width
                let actionWidth = max(24, reservedWidth)
                let titleMaxX = button.frame.midX + (titleWidth / 2)
                actionButton.frame = NSRect(
                    x: titleMaxX - reservedWidth
                        - ((actionWidth - reservedWidth) / 2),
                    y: button.frame.minY,
                    width: actionWidth,
                    height: button.frame.height
                )
                let actionLabel: String
                if candidate.pinned {
                    actionLabel = "取消置頂「\(candidate.text)」"
                } else if candidate.isUserPhrase {
                    actionLabel = "刪除使用者詞「\(candidate.text)」"
                } else {
                    actionLabel = "刪除內建詞「\(candidate.text)」"
                }
                actionButton.toolTip = actionLabel
                actionButton.setAccessibilityLabel(actionLabel)
            }
        }

        NSAccessibility.post(
            element: self,
            notification: .selectedChildrenChanged
        )
    }

    @objc private func candidateClicked(_ sender: CandidateButton) {
        onChoose?(sender.sessionID, sender.candidateIndex)
    }

    @objc private func candidateActionClicked(
        _ sender: CandidateActionButton
    ) {
        onAction?(sender.sessionID, sender.candidateIndex)
    }
}

final class CandidateWindowPresenter {
    static let shared = CandidateWindowPresenter()
    private static let savedPhraseDisplayDuration: TimeInterval = 10
    private static let deletionResultDisplayDuration: TimeInterval = 2

    private weak var delegate: CandidateWindowPresenterDelegate?
    private let panel: CandidatePanel
    private let backgroundView: NSVisualEffectView
    private let scrollView: NSScrollView
    private let gridView: CandidateGridView
    private let revisionLabel: NSTextField
    private let savedPhraseDeleteButton: SavedPhraseDeleteButton
    private var savedPhraseHideWorkItem: DispatchWorkItem?
    private(set) var presentedSessionID: UUID?
    private(set) var presentedPhraseSelectionID: UUID?
    private(set) var presentedSavedPhraseConfirmation:
        SavedUserPhraseConfirmation?

    private init() {
        precondition(Thread.isMainThread)
        panel = CandidatePanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        backgroundView = NSVisualEffectView(frame: .zero)
        scrollView = NSScrollView(frame: .zero)
        gridView = CandidateGridView(frame: .zero)
        revisionLabel = NSTextField(labelWithString: "")
        savedPhraseDeleteButton = SavedPhraseDeleteButton(
            title: "×",
            target: nil,
            action: nil
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.worksWhenModal = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [
            .canJoinAllApplications,
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .transient
        ]

        backgroundView.material = .popover
        backgroundView.blendingMode = .behindWindow
        backgroundView.state = .active
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = 10
        backgroundView.layer?.masksToBounds = true
        backgroundView.setAccessibilityLabel("候選字")

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        scrollView.documentView = gridView
        scrollView.autoresizingMask = []
        backgroundView.addSubview(scrollView)

        revisionLabel.alignment = .center
        revisionLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        revisionLabel.textColor = .labelColor
        revisionLabel.lineBreakMode = .byTruncatingTail
        revisionLabel.wantsLayer = true
        revisionLabel.layer?.cornerRadius = 6
        revisionLabel.layer?.backgroundColor = NSColor.controlAccentColor
            .withAlphaComponent(0.18).cgColor
        revisionLabel.isHidden = true
        backgroundView.addSubview(revisionLabel)

        savedPhraseDeleteButton.target = self
        savedPhraseDeleteButton.action = #selector(deleteSavedPhrase(_:))
        savedPhraseDeleteButton.bezelStyle = .circular
        savedPhraseDeleteButton.font = NSFont.systemFont(
            ofSize: 17,
            weight: .semibold
        )
        savedPhraseDeleteButton.focusRingType = .none
        savedPhraseDeleteButton.isHidden = true
        savedPhraseDeleteButton.setAccessibilityLabel(
            "刪除剛儲存的使用者詞"
        )
        backgroundView.addSubview(savedPhraseDeleteButton)
        panel.contentView = backgroundView

        gridView.onChoose = { [weak self] sessionID, candidateIndex in
            guard let self,
                  self.presentedSessionID == sessionID else {
                return
            }

            self.delegate?.candidateWindowPresenter(
                self,
                choseCandidateAt: candidateIndex,
                sessionID: sessionID
            )
        }
        gridView.onAction = { [weak self] sessionID, candidateIndex in
            guard let self,
                  self.presentedSessionID == sessionID else {
                return
            }

            self.delegate?.candidateWindowPresenter(
                self,
                requestsActionForCandidateAt: candidateIndex,
                sessionID: sessionID
            )
        }

    }

    func present(
        session: CandidateSession,
        anchor: NSRect,
        clientWindowLevel: CGWindowLevel,
        delegate: CandidateWindowPresenterDelegate
    ) {
        precondition(Thread.isMainThread)
        clearSavedPhraseConfirmationState()
        if let previousSessionID = presentedSessionID,
           previousSessionID != session.id {
            self.delegate?.candidateWindowPresenter(
                self,
                requestsFinalizationOf: previousSessionID
            )
        }

        self.delegate = delegate
        presentedSessionID = session.id
        presentedPhraseSelectionID = nil
        panel.ignoresMouseEvents = false
        scrollView.isHidden = false
        revisionLabel.alignment = .center
        savedPhraseDeleteButton.isHidden = true

        let scrollerThickness = NSScroller.scrollerWidth(
            for: .regular,
            scrollerStyle: scrollView.scrollerStyle
        )
        let visibleIndices: [Int]
        switch session.presentationMode {
        case .compact:
            visibleIndices = Array(session.compactCandidateRange)
        case .expanded:
            visibleIndices = Array(session.candidates.indices)
        }
        let visibleCandidateTexts = visibleIndices.compactMap {
            session.candidate(at: $0).map(
                CandidateWindowPresentationText.sizingText(for:)
            )
        }
        let candidateViewportSize = CandidateWindowSizing.viewportSize(
            candidateTexts: visibleCandidateTexts,
            mode: session.presentationMode,
            scrollerThickness: scrollerThickness
        )
        let revisionFocus = session.revisionFocus
        let revisionDisplayText = session.revisionDisplayText
        revisionLabel.stringValue = revisionDisplayText ?? ""
        revisionLabel.toolTip = revisionDisplayText
        revisionLabel.isHidden = revisionFocus == nil
        revisionLabel.layer?.backgroundColor = revisionHeaderColor(
            for: session.revisionMode
        ).cgColor
        let desiredSize = CandidateWindowSizing.panelSize(
            candidateViewportSize: candidateViewportSize,
            revisionHeaderContentWidth: revisionFocus == nil
                ? nil
                : revisionLabel.intrinsicContentSize.width
        )
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        let frame = CandidateWindowPlacement.frame(
            anchor: anchor.standardized,
            desiredSize: desiredSize,
            visibleFrames: visibleFrames
        )
        let documentSize = CandidateWindowSizing.documentSize(
            candidateTexts: visibleCandidateTexts,
            mode: session.presentationMode
        )

        let actualCandidateViewportSize = CandidateWindowSizing
            .candidateViewportSize(
                panelSize: frame.size,
                showsRevisionHeader: revisionFocus != nil
            )
        let scrollAxes = CandidateWindowSizing.scrollAxes(
            documentSize: documentSize,
            viewportSize: actualCandidateViewportSize,
            scrollerThickness: scrollerThickness
        )
        scrollView.hasVerticalScroller = scrollAxes.vertical
        scrollView.hasHorizontalScroller = scrollAxes.horizontal
        panel.level = NSWindow.Level(
            rawValue: Int(clientWindowLevel) + 1
        )
        panel.setFrame(frame, display: true)
        scrollView.frame = NSRect(
            origin: .zero,
            size: actualCandidateViewportSize
        )
        if revisionFocus != nil {
            revisionLabel.frame = NSRect(
                x: CandidateWindowSizing.contentInset,
                y: actualCandidateViewportSize.height + 5,
                width: max(
                    1,
                    frame.width - (2 * CandidateWindowSizing.contentInset)
                ),
                height: CandidateWindowSizing.revisionHeaderHeight - 10
            )
            backgroundView.setAccessibilityLabel(
                "候選字，\(revisionLabel.stringValue)"
            )
        } else {
            revisionLabel.frame = .zero
            backgroundView.setAccessibilityLabel("候選字")
        }
        gridView.update(with: session)
        panel.contentView?.layoutSubtreeIfNeeded()
        scrollView.contentView.scroll(to: .zero)
        gridView.revealHighlightedCandidate(in: session)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        panel.orderFrontRegardless()
    }

    /// Shows a header-only phrase-range status. This remains reliable in
    /// clients that ignore marked-text attributes or paint a non-empty marked
    /// selection as the complete composition.
    func presentPhraseSelection(
        id: UUID,
        displayText: String,
        anchor: NSRect,
        clientWindowLevel: CGWindowLevel
    ) {
        precondition(Thread.isMainThread)
        clearSavedPhraseConfirmationState()
        if let previousSessionID = presentedSessionID {
            delegate?.candidateWindowPresenter(
                self,
                requestsFinalizationOf: previousSessionID
            )
        }

        delegate = nil
        presentedSessionID = nil
        presentedPhraseSelectionID = id
        panel.ignoresMouseEvents = true
        scrollView.isHidden = true
        scrollView.frame = .zero
        gridView.clear()

        revisionLabel.alignment = .center
        revisionLabel.stringValue = displayText
        revisionLabel.toolTip = displayText
        revisionLabel.isHidden = false
        revisionLabel.layer?.backgroundColor = NSColor.systemGreen
            .withAlphaComponent(0.22).cgColor

        let desiredSize = CandidateWindowSizing.phraseStatusPanelSize(
            contentWidth: revisionLabel.intrinsicContentSize.width
        )
        let frame = CandidateWindowPlacement.frame(
            anchor: anchor.standardized,
            desiredSize: desiredSize,
            visibleFrames: NSScreen.screens.map(\.visibleFrame)
        )
        panel.level = NSWindow.Level(
            rawValue: Int(clientWindowLevel) + 1
        )
        panel.setFrame(frame, display: true)
        revisionLabel.frame = NSRect(
            x: CandidateWindowSizing.contentInset,
            y: 5,
            width: max(
                1,
                frame.width - (2 * CandidateWindowSizing.contentInset)
            ),
            height: max(1, frame.height - 10)
        )
        backgroundView.setAccessibilityLabel(displayText)
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.orderFrontRegardless()
    }

    /// Confirms a successfully saved user phrase and offers one precise undo
    /// action. The panel stays nonactivating, so clicking × cannot steal the
    /// insertion focus from the client application.
    func presentSavedPhraseConfirmation(
        _ confirmation: SavedUserPhraseConfirmation,
        anchor: NSRect,
        clientWindowLevel: CGWindowLevel,
        delegate: CandidateWindowPresenterDelegate
    ) {
        precondition(Thread.isMainThread)
        clearSavedPhraseConfirmationState()
        if let previousSessionID = presentedSessionID {
            self.delegate?.candidateWindowPresenter(
                self,
                requestsFinalizationOf: previousSessionID
            )
        }

        self.delegate = delegate
        presentedSessionID = nil
        presentedPhraseSelectionID = nil
        presentedSavedPhraseConfirmation = confirmation
        panel.ignoresMouseEvents = false
        scrollView.isHidden = true
        scrollView.frame = .zero
        gridView.clear()

        revisionLabel.alignment = .left
        revisionLabel.stringValue = confirmation.displayText
        revisionLabel.toolTip = confirmation.displayText
        revisionLabel.isHidden = false
        revisionLabel.layer?.backgroundColor = NSColor.systemGreen
            .withAlphaComponent(0.22).cgColor

        savedPhraseDeleteButton.toolTip = confirmation.deletionToolTip
        savedPhraseDeleteButton.isHidden = false

        let desiredSize = CandidateWindowSizing
            .savedPhraseConfirmationPanelSize(
                contentWidth: revisionLabel.intrinsicContentSize.width
            )
        let frame = CandidateWindowPlacement.frame(
            anchor: anchor.standardized,
            desiredSize: desiredSize,
            visibleFrames: NSScreen.screens.map(\.visibleFrame)
        )
        panel.level = NSWindow.Level(
            rawValue: Int(clientWindowLevel) + 1
        )
        panel.setFrame(frame, display: true)
        layoutSavedPhraseConfirmationContent()
        backgroundView.setAccessibilityLabel(
            "\(confirmation.displayText)，可刪除"
        )
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.orderFrontRegardless()
        scheduleSavedPhraseHide(
            id: confirmation.id,
            after: Self.savedPhraseDisplayDuration
        )
    }

    func resolveSavedPhraseDeletion(
        id: UUID,
        succeeded: Bool
    ) {
        precondition(Thread.isMainThread)
        guard let confirmation = presentedSavedPhraseConfirmation,
              confirmation.id == id else {
            return
        }

        savedPhraseHideWorkItem?.cancel()
        savedPhraseHideWorkItem = nil
        if succeeded {
            revisionLabel.stringValue = "已刪除：【\(confirmation.phrase)】"
            revisionLabel.toolTip = revisionLabel.stringValue
            savedPhraseDeleteButton.isHidden = true
            delegate = nil
            backgroundView.setAccessibilityLabel(revisionLabel.stringValue)
            layoutSavedPhraseConfirmationContent()
            scheduleSavedPhraseHide(
                id: id,
                after: Self.deletionResultDisplayDuration
            )
        } else {
            revisionLabel.stringValue = "無法刪除：【\(confirmation.phrase)】"
            revisionLabel.toolTip = revisionLabel.stringValue
            backgroundView.setAccessibilityLabel(
                "\(revisionLabel.stringValue)，請再試一次"
            )
            layoutSavedPhraseConfirmationContent()
            scheduleSavedPhraseHide(
                id: id,
                after: Self.savedPhraseDisplayDuration
            )
        }
    }

    private func revisionHeaderColor(
        for mode: CandidateRevisionMode?
    ) -> NSColor {
        switch mode {
        case .locating:
            return NSColor.controlAccentColor.withAlphaComponent(0.18)
        case .choosing:
            return NSColor.systemOrange.withAlphaComponent(0.22)
        case nil:
            return .clear
        }
    }

    func hide(sessionID: UUID) {
        precondition(Thread.isMainThread)
        guard presentedSessionID == sessionID else {
            return
        }

        presentedSessionID = nil
        delegate = nil
        panel.orderOut(nil)
        gridView.clear()
    }

    func hidePhraseSelection(id: UUID) {
        precondition(Thread.isMainThread)
        guard presentedPhraseSelectionID == id else {
            return
        }

        presentedPhraseSelectionID = nil
        panel.orderOut(nil)
        revisionLabel.isHidden = true
        gridView.clear()
    }

    func hideSavedPhraseConfirmation(id: UUID) {
        precondition(Thread.isMainThread)
        guard presentedSavedPhraseConfirmation?.id == id else {
            return
        }

        clearSavedPhraseConfirmationState()
        panel.orderOut(nil)
    }

    @objc private func deleteSavedPhrase(_ sender: NSButton) {
        guard let confirmation = presentedSavedPhraseConfirmation else {
            return
        }
        delegate?.candidateWindowPresenter(
            self,
            requestsDeletionOf: confirmation
        )
    }

    private func layoutSavedPhraseConfirmationContent() {
        let inset = CandidateWindowSizing.contentInset
        let buttonWidth = CandidateWindowSizing.savedPhraseActionButtonWidth
        let gap = CandidateWindowSizing.savedPhraseActionGap
        let contentHeight = max(1, backgroundView.bounds.height - 10)
        let buttonIsVisible = !savedPhraseDeleteButton.isHidden
        let reservedButtonWidth = buttonIsVisible ? gap + buttonWidth : 0

        revisionLabel.frame = NSRect(
            x: inset,
            y: 5,
            width: max(
                1,
                backgroundView.bounds.width
                    - (2 * inset)
                    - reservedButtonWidth
            ),
            height: contentHeight
        )
        savedPhraseDeleteButton.frame = buttonIsVisible
            ? NSRect(
                x: backgroundView.bounds.width - inset - buttonWidth,
                y: 5,
                width: buttonWidth,
                height: contentHeight
            )
            : .zero
    }

    private func scheduleSavedPhraseHide(
        id: UUID,
        after duration: TimeInterval
    ) {
        savedPhraseHideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.presentedSavedPhraseConfirmation?.id == id else {
                return
            }
            self.clearSavedPhraseConfirmationState()
            self.panel.orderOut(nil)
        }
        savedPhraseHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + duration,
            execute: workItem
        )
    }

    private func clearSavedPhraseConfirmationState() {
        guard presentedSavedPhraseConfirmation != nil else {
            return
        }
        savedPhraseHideWorkItem?.cancel()
        savedPhraseHideWorkItem = nil
        presentedSavedPhraseConfirmation = nil
        savedPhraseDeleteButton.isHidden = true
        savedPhraseDeleteButton.toolTip = nil
        delegate = nil
    }
}
