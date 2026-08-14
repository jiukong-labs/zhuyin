enum CandidateNavigation: Equatable {
    case previous
    case next
    case first
    case last
    case previousPage
    case nextPage
}

struct CandidateSession: Equatable {
    private static let pageSize = 9

    let pronunciation: String
    let candidates: [String]
    private(set) var highlightedCandidate: String?

    init?(pronunciation: String, candidates: [String]) {
        var seen: Set<String> = []
        let uniqueCandidates = candidates.filter { seen.insert($0).inserted }
        guard !pronunciation.isEmpty, !uniqueCandidates.isEmpty else {
            return nil
        }

        self.pronunciation = pronunciation
        self.candidates = uniqueCandidates
    }

    var preferredCandidate: String {
        highlightedCandidate ?? candidates[0]
    }

    mutating func updateHighlightedCandidate(_ candidate: String) {
        guard candidates.contains(candidate) else {
            return
        }

        highlightedCandidate = candidate
    }

    func candidate(after navigation: CandidateNavigation) -> String {
        let currentIndex = highlightedCandidate
            .flatMap(candidates.firstIndex(of:)) ?? 0
        let lastIndex = candidates.index(before: candidates.endIndex)
        let targetIndex: Int

        switch navigation {
        case .previous:
            targetIndex = max(candidates.startIndex, currentIndex - 1)
        case .next:
            targetIndex = min(lastIndex, currentIndex + 1)
        case .first:
            targetIndex = candidates.startIndex
        case .last:
            targetIndex = lastIndex
        case .previousPage:
            targetIndex = max(
                candidates.startIndex,
                currentIndex - Self.pageSize
            )
        case .nextPage:
            targetIndex = min(lastIndex, currentIndex + Self.pageSize)
        }

        return candidates[targetIndex]
    }

    func candidate(atSelectionKeyIndex selectionKeyIndex: Int) -> String? {
        guard (0 ..< Self.pageSize).contains(selectionKeyIndex) else {
            return nil
        }

        let currentIndex = highlightedCandidate
            .flatMap(candidates.firstIndex(of:)) ?? 0
        let pageStartIndex = (currentIndex / Self.pageSize) * Self.pageSize
        let targetIndex = pageStartIndex + selectionKeyIndex
        guard candidates.indices.contains(targetIndex) else {
            return nil
        }

        return candidates[targetIndex]
    }

    func validatedSelection(_ candidate: String) -> String? {
        candidates.contains(candidate) ? candidate : nil
    }
}
