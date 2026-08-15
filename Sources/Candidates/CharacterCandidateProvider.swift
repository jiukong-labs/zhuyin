import Foundation

final class CharacterCandidateProvider {
    private let dictionary: CharacterDictionary
    private let learning: (any UserLearningProviding)?
    private let ranker: CandidateRanker
    private let now: () -> Date

    init(
        dictionary: CharacterDictionary,
        learning: (any UserLearningProviding)? = nil,
        ranker: CandidateRanker = CandidateRanker(),
        now: @escaping () -> Date = Date.init
    ) {
        self.dictionary = dictionary
        self.learning = learning
        self.ranker = ranker
        self.now = now
    }

    func candidates(for pronunciation: String) throws -> [Candidate] {
        let learningRecords = learning?.records(for: pronunciation) ?? [:]
        let candidates = try dictionary.candidateEntries(for: pronunciation)
            .enumerated()
            .map { baseRank, entry in
                let learningRecord = learningRecords[entry.text]
                return Candidate(
                    text: entry.text,
                    pronunciation: pronunciation,
                    baseRank: baseRank,
                    sourceOrder: entry.sourceOrder,
                    userFrequency: learningRecord?.selectionCount ?? 0,
                    lastUsed: learningRecord?.lastSelectedAt,
                    pinned: learningRecord?.pinned ?? false
                )
            }

        return ranker.ranked(candidates, at: now())
    }

    func recordCommittedSelection(
        _ candidate: Candidate,
        reason: CandidateCommitReason
    ) {
        guard candidate.type == .character,
              !candidate.text.isEmpty,
              candidate.pronunciationSequence.count == 1,
              let pronunciation = candidate.pronunciationSequence.first,
              !pronunciation.isEmpty,
              reason.recordsCharacterSelection else {
            return
        }

        learning?.recordSelection(
            character: candidate.text,
            pronunciation: pronunciation
        )
    }
}

private extension CandidateCommitReason {
    var recordsCharacterSelection: Bool {
        switch self {
        case .space,
             .returnKey,
             .number,
             .mouse,
             .implicitPassThrough,
             .lifecycle,
             .clientHandoff:
            return true
        }
    }
}
