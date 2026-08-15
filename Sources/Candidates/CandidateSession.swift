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

struct CandidateSession: Equatable {
    static let selectionPageSize = 9
    static let expandedColumnCount = 9
    static let expandedVisibleCandidateCount = 27

    let id: UUID
    let pronunciation: String
    let candidates: [String]
    private(set) var highlightedIndex = 0
    private(set) var presentationMode: CandidatePresentationMode = .compact

    init?(
        id: UUID = UUID(),
        pronunciation: String,
        candidates: [String]
    ) {
        var seen: Set<String> = []
        let uniqueCandidates = candidates.filter { seen.insert($0).inserted }
        guard !pronunciation.isEmpty, !uniqueCandidates.isEmpty else {
            return nil
        }

        self.id = id
        self.pronunciation = pronunciation
        self.candidates = uniqueCandidates
    }

    var preferredCandidate: String {
        candidates[highlightedIndex]
    }

    var highlightedCandidate: String {
        candidates[highlightedIndex]
    }

    var isExpanded: Bool {
        presentationMode == .expanded
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

    @discardableResult
    mutating func expand() -> Bool {
        guard presentationMode == .compact else {
            return false
        }

        presentationMode = .expanded
        return true
    }

    mutating func updateHighlightedCandidate(_ candidate: String) {
        guard let index = candidates.firstIndex(of: candidate) else {
            return
        }

        highlightedIndex = index
    }

    @discardableResult
    mutating func navigate(_ navigation: CandidateNavigation) -> String {
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

    func candidate(atSelectionKeyIndex selectionKeyIndex: Int) -> String? {
        guard (0 ..< Self.selectionPageSize).contains(selectionKeyIndex) else {
            return nil
        }

        let pageStartIndex = selectionPageRange.lowerBound
        let targetIndex = pageStartIndex + selectionKeyIndex
        return candidate(at: targetIndex)
    }

    func candidate(at index: Int) -> String? {
        candidates.indices.contains(index) ? candidates[index] : nil
    }

    func validatedSelection(_ candidate: String) -> String? {
        candidates.contains(candidate) ? candidate : nil
    }
}
