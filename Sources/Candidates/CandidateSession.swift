import Foundation

enum CandidateNavigation: Equatable {
    case previous
    case next
    case up
    case down
    case first
    case last
    case previousPage
    case nextPage
}

enum CandidatePresentationMode: Equatable {
    case compact
    case expanded
}

enum CandidateRevisionMode: Equatable {
    case locating
    case choosing
}

struct CandidateSession: Equatable {
    static let selectionPageSize = 9
    static let expandedColumnCount = 9
    static let expandedVisibleCandidateCount = 27

    let id: UUID
    let pronunciation: String
    let revisionFocus: CompositionRevisionFocus?
    /// The candidates shown for this selection session.
    ///
    /// This ordered value snapshot deliberately does not consult the learning
    /// store again. Learning recorded while a panel is open therefore affects
    /// the next lookup without moving the choices under the user's cursor.
    let candidates: [Candidate]
    private(set) var highlightedIndex = 0
    private(set) var presentationMode: CandidatePresentationMode = .compact
    private var isRevisionChoosing = false

    init?(
        id: UUID = UUID(),
        pronunciation: String,
        candidates: [Candidate],
        revisionFocus: CompositionRevisionFocus? = nil
    ) {
        var seen: Set<CandidateID> = []
        let uniqueCandidates = candidates.filter {
            seen.insert($0.id).inserted
        }
        guard !pronunciation.isEmpty, !uniqueCandidates.isEmpty else {
            return nil
        }

        self.id = id
        self.pronunciation = pronunciation
        self.candidates = uniqueCandidates
        self.revisionFocus = revisionFocus
    }

    var preferredCandidate: Candidate {
        candidates[highlightedIndex]
    }

    var highlightedCandidate: Candidate {
        candidates[highlightedIndex]
    }

    var isExpanded: Bool {
        presentationMode == .expanded
    }

    /// Ordinary compact conversion is windowless. Revision choosing may use a
    /// compact, visible nine-candidate row after its first Down Arrow and only
    /// expands to the full grid after a second Down Arrow.
    var presentsCandidatePanel: Bool {
        isExpanded || revisionMode == .choosing
    }

    var isInlinePreview: Bool {
        revisionFocus == nil && !isExpanded
    }

    var revisionMode: CandidateRevisionMode? {
        guard revisionFocus != nil else {
            return nil
        }
        return isRevisionChoosing ? .choosing : .locating
    }

    var revisionDisplayText: String? {
        guard let revisionFocus else {
            return nil
        }
        switch revisionMode {
        case .locating:
            return revisionFocus.locatingDisplayText
        case .choosing:
            return revisionFocus.choosingDisplayText
        case nil:
            return nil
        }
    }

    var selectionPageRange: Range<Int> {
        let pageStart = (highlightedIndex / Self.selectionPageSize)
            * Self.selectionPageSize
        return pageStart ..< min(
            pageStart + Self.selectionPageSize,
            candidates.count
        )
    }

    var compactCandidateRange: Range<Int> {
        selectionPageRange
    }

    /// The displayed 1-9 slot containing the current highlight.
    var highlightedSelectionKeyIndex: Int {
        highlightedIndex - selectionPageRange.lowerBound
    }

    @discardableResult
    mutating func expand() -> Bool {
        guard presentationMode == .compact else {
            return false
        }

        presentationMode = .expanded
        if revisionFocus != nil {
            isRevisionChoosing = true
        }
        return true
    }

    @discardableResult
    mutating func beginRevisionChoosing() -> Bool {
        guard revisionFocus != nil, !isRevisionChoosing else {
            return false
        }
        isRevisionChoosing = true
        return true
    }

    @discardableResult
    mutating func collapse() -> Bool {
        guard presentationMode == .expanded else {
            return false
        }

        presentationMode = .compact
        return true
    }

    mutating func updateHighlightedCandidate(_ candidateID: CandidateID) {
        guard let index = candidates.firstIndex(where: {
            $0.id == candidateID
        }) else {
            return
        }

        highlightedIndex = index
    }

    @discardableResult
    mutating func navigate(_ navigation: CandidateNavigation) -> Candidate {
        let lastIndex = candidates.index(before: candidates.endIndex)
        let targetIndex: Int

        switch navigation {
        case .previous:
            targetIndex = max(candidates.startIndex, highlightedIndex - 1)
        case .next:
            targetIndex = min(lastIndex, highlightedIndex + 1)
        case .up:
            let candidateIndex = highlightedIndex - Self.expandedColumnCount
            targetIndex = candidates.indices.contains(candidateIndex)
                ? candidateIndex
                : highlightedIndex
        case .down:
            let candidateIndex = highlightedIndex + Self.expandedColumnCount
            targetIndex = candidates.indices.contains(candidateIndex)
                ? candidateIndex
                : highlightedIndex
        case .first:
            targetIndex = candidates.startIndex
        case .last:
            targetIndex = lastIndex
        case .previousPage:
            let pageSize = isExpanded
                ? Self.expandedVisibleCandidateCount
                : Self.selectionPageSize
            targetIndex = max(
                candidates.startIndex,
                highlightedIndex - pageSize
            )
        case .nextPage:
            let pageSize = isExpanded
                ? Self.expandedVisibleCandidateCount
                : Self.selectionPageSize
            targetIndex = min(lastIndex, highlightedIndex + pageSize)
        }

        highlightedIndex = targetIndex
        return candidates[highlightedIndex]
    }

    func candidate(atSelectionKeyIndex selectionKeyIndex: Int) -> Candidate? {
        guard (0 ..< Self.selectionPageSize).contains(selectionKeyIndex) else {
            return nil
        }

        let pageStartIndex = selectionPageRange.lowerBound
        let targetIndex = pageStartIndex + selectionKeyIndex
        return candidate(at: targetIndex)
    }

    func candidate(at index: Int) -> Candidate? {
        candidates.indices.contains(index) ? candidates[index] : nil
    }

    func validatedSelection(_ candidateID: CandidateID) -> Candidate? {
        candidates.first(where: { $0.id == candidateID })
    }
}

enum CandidateRevisionInteractionPolicy {
    static func routesCompositionCursor(
        candidateSession: CandidateSession?
    ) -> Bool {
        candidateSession?.revisionMode != .choosing
    }

    /// Candidate navigation is deliberately dormant in a locating snapshot.
    /// Runtime text positioning normally has no candidate session; its first
    /// Down creates a separate choosing snapshot.
    static func allowsCandidateCommand(
        _ command: CandidateCommand,
        session: CandidateSession
    ) -> Bool {
        guard session.revisionMode == .locating else {
            return true
        }
        if case .navigate = command {
            return false
        }
        return true
    }

    /// While an ordinary candidate is only previewed inline, Down opens the
    /// explicit chooser. Space, Escape, and Backspace retain their editing
    /// meanings; selection numbers, Return, and navigation bypass candidate
    /// routing so they can continue or finalize the composition normally.
    static func bypassesCandidateCommand(
        _ command: CandidateCommand,
        session: CandidateSession
    ) -> Bool {
        guard session.isInlinePreview else {
            return false
        }
        switch command {
        case .expand, .commitFirst, .cancel, .deleteBackward:
            return false
        case .navigate, .select, .commitHighlighted:
            return true
        }
    }
}
