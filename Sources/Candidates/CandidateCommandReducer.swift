enum CandidateCommandEffect: Equatable {
    case update(CandidateSession)
    case commit(Candidate, reason: CandidateCommitReason)
    case cancel
    case deleteBackward
    case handledWithoutChange
}

enum CandidateCommandReducer {
    static func reduce(
        _ command: CandidateCommand,
        session: CandidateSession
    ) -> CandidateCommandEffect {
        var updatedSession = session

        switch command {
        case .expand:
            _ = updatedSession.expand()
            return .update(updatedSession)
        case let .navigate(navigation):
            updatedSession.navigate(navigation)
            return .update(updatedSession)
        case let .select(selectionKeyIndex):
            guard let candidate = session.candidate(
                atSelectionKeyIndex: selectionKeyIndex
            ) else {
                return .handledWithoutChange
            }
            return .commit(
                candidate,
                reason: .number(selectionKeyIndex)
            )
        case .commitFirst:
            return .commit(session.candidates[0], reason: .space)
        case .commitHighlighted:
            return .commit(
                session.highlightedCandidate,
                reason: .returnKey
            )
        case .cancel:
            return .cancel
        case .deleteBackward:
            return .deleteBackward
        }
    }
}
