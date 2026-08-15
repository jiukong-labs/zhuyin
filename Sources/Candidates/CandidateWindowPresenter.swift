import AppKit

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

private final class CandidateGridView: NSView {
    var onChoose: ((UUID, Int) -> Void)?

    private var buttons: [Int: CandidateButton] = [:]
    private var representedIndices: [Int] = []
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

        if representedSessionID != session.id
            || representedMode != session.presentationMode
            || representedIndices != indices {
            rebuild(
                indices: indices,
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
        buttons.removeAll()
        representedIndices.removeAll()
        representedSessionID = nil
        representedMode = nil
        setFrameSize(.zero)
    }

    private func rebuild(indices: [Int], session: CandidateSession) {
        buttons.values.forEach { $0.removeFromSuperview() }
        buttons.removeAll()
        representedIndices = indices
        representedSessionID = session.id
        representedMode = session.presentationMode

        let columnCount: Int
        switch session.presentationMode {
        case .compact:
            columnCount = max(1, indices.count)
        case .expanded:
            columnCount = min(
                max(1, indices.count),
                CandidateSession.expandedColumnCount
            )
        }

        let documentSize = CandidateWindowSizing.documentSize(
            candidateCount: indices.count,
            mode: session.presentationMode
        )
        setFrameSize(documentSize)

        for (position, candidateIndex) in indices.enumerated() {
            let row = position / columnCount
            let column = position % columnCount
            let origin = NSPoint(
                x: CandidateWindowSizing.contentInset
                    + CGFloat(column)
                    * (CandidateWindowSizing.cellWidth
                        + CandidateWindowSizing.cellSpacing),
                y: CandidateWindowSizing.contentInset
                    + CGFloat(row)
                    * (CandidateWindowSizing.cellHeight
                        + CandidateWindowSizing.cellSpacing)
            )
            let button = CandidateButton(
                candidateIndex: candidateIndex,
                sessionID: session.id
            )
            button.frame = NSRect(
                origin: origin,
                size: NSSize(
                    width: CandidateWindowSizing.cellWidth,
                    height: CandidateWindowSizing.cellHeight
                )
            )
            button.target = self
            button.action = #selector(candidateClicked(_:))
            button.isBordered = false
            button.focusRingType = .none
            button.alignment = .center
            button.wantsLayer = true
            button.layer?.cornerRadius = 7
            addSubview(button)
            buttons[candidateIndex] = button
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
            button.attributedTitle = NSAttributedString(
                string: selectionKey + candidate,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 18, weight: .medium),
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
            button.toolTip = "候選 \(candidateIndex + 1)／\(session.candidates.count)：\(candidate)"
            button.setAccessibilityLabel(
                "候選 \(candidateIndex + 1)／\(session.candidates.count)，\(candidate)"
            )
            button.setAccessibilityValue(isSelected ? "已選取" : nil)
        }

        NSAccessibility.post(
            element: self,
            notification: .selectedChildrenChanged
        )
    }

    @objc private func candidateClicked(_ sender: CandidateButton) {
        onChoose?(sender.sessionID, sender.candidateIndex)
    }
}

final class CandidateWindowPresenter {
    static let shared = CandidateWindowPresenter()

    private weak var delegate: CandidateWindowPresenterDelegate?
    private let panel: CandidatePanel
    private let backgroundView: NSVisualEffectView
    private let scrollView: NSScrollView
    private let gridView: CandidateGridView
    private(set) var presentedSessionID: UUID?

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
        scrollView.autoresizingMask = [.width, .height]
        backgroundView.addSubview(scrollView)
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

    }

    func present(
        session: CandidateSession,
        anchor: NSRect,
        clientWindowLevel: CGWindowLevel,
        delegate: CandidateWindowPresenterDelegate
    ) {
        precondition(Thread.isMainThread)
        if let previousSessionID = presentedSessionID,
           previousSessionID != session.id {
            self.delegate?.candidateWindowPresenter(
                self,
                requestsFinalizationOf: previousSessionID
            )
        }

        self.delegate = delegate
        presentedSessionID = session.id

        let scrollerThickness = NSScroller.scrollerWidth(
            for: .regular,
            scrollerStyle: scrollView.scrollerStyle
        )
        let desiredSize = CandidateWindowSizing.viewportSize(
            candidateCount: session.presentationMode == .compact
                ? session.compactCandidateRange.count
                : session.candidates.count,
            mode: session.presentationMode,
            scrollerThickness: scrollerThickness
        )
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        let frame = CandidateWindowPlacement.frame(
            anchor: anchor.standardized,
            desiredSize: desiredSize,
            visibleFrames: visibleFrames
        )
        let documentSize = CandidateWindowSizing.documentSize(
            candidateCount: session.presentationMode == .compact
                ? session.compactCandidateRange.count
                : session.candidates.count,
            mode: session.presentationMode
        )

        let scrollAxes = CandidateWindowSizing.scrollAxes(
            documentSize: documentSize,
            viewportSize: frame.size,
            scrollerThickness: scrollerThickness
        )
        scrollView.hasVerticalScroller = scrollAxes.vertical
        scrollView.hasHorizontalScroller = scrollAxes.horizontal
        panel.level = NSWindow.Level(
            rawValue: Int(clientWindowLevel) + 1
        )
        panel.setFrame(frame, display: true)
        scrollView.frame = backgroundView.bounds
        gridView.update(with: session)
        panel.contentView?.layoutSubtreeIfNeeded()
        scrollView.contentView.scroll(to: .zero)
        gridView.revealHighlightedCandidate(in: session)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        panel.orderFrontRegardless()
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
}
