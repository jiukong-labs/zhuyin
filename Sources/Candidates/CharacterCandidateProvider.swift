import Foundation

final class CharacterCandidateProvider {
    private let dictionary: CharacterDictionary
    private let learning: (any UserLearningProviding)?
    private let ranker: CandidateRanker
    private let isAutomaticLearningEnabled: () -> Bool
    private let now: () -> Date

    init(
        dictionary: CharacterDictionary,
        learning: (any UserLearningProviding)? = nil,
        ranker: CandidateRanker = CandidateRanker(),
        isAutomaticLearningEnabled: @escaping () -> Bool = { true },
        now: @escaping () -> Date = Date.init
    ) {
        self.dictionary = dictionary
        self.learning = learning
        self.ranker = ranker
        self.isAutomaticLearningEnabled = isAutomaticLearningEnabled
        self.now = now
    }

    func candidates(
        for pronunciation: String,
        phraseQueries: [CompositionPhraseQuery] = []
    ) throws -> [Candidate] {
        let learningRecords = learning?.records(for: pronunciation) ?? [:]
        let characterCandidates = try dictionary.candidateEntries(for: pronunciation)
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

        let phraseCandidates = try exactPhraseCandidates(
            for: pronunciation,
            queries: phraseQueries
        )
        return ranker.ranked(
            phraseCandidates + characterCandidates,
            at: now()
        )
    }

    @discardableResult
    func addUserPhrase(
        phrase: String,
        pronunciationSequence: [String]
    ) -> Bool {
        guard let identity = try? UserPhraseValidator.validate(
            phrase: phrase,
            pronunciationSequence: pronunciationSequence
        ) else {
            return false
        }
        return learning?.addPhrase(
            phrase: identity.phrase,
            pronunciationSequence: identity.pronunciationSequence,
            createdAt: now()
        ) ?? false
    }

    /// Implicit learning only. Existing counts still rank candidates while the
    /// setting is off, and an explicit `addUserPhrase` remains available,
    /// because the user asked for that phrase directly.
    func recordCommittedSelection(
        _ candidate: Candidate,
        reason: CandidateCommitReason
    ) {
        guard reason.recordsCandidateSelection,
              isAutomaticLearningEnabled() else {
            return
        }

        switch candidate.type {
        case .character:
            guard !candidate.text.isEmpty,
                  candidate.pronunciationSequence.count == 1,
                  let pronunciation = candidate.pronunciationSequence.first,
                  !pronunciation.isEmpty else {
                return
            }
            learning?.recordSelection(
                character: candidate.text,
                pronunciation: pronunciation
            )
        case .phrase:
            guard let identity = try? UserPhraseValidator.validate(
                phrase: candidate.text,
                pronunciationSequence: candidate.pronunciationSequence
            ), identity.phrase == candidate.text,
                  identity.pronunciationSequence
                    == candidate.pronunciationSequence else {
                return
            }
            let selectedAt = now()
            _ = learning?.addPhrase(
                phrase: candidate.text,
                pronunciationSequence: candidate.pronunciationSequence,
                createdAt: selectedAt
            )
            learning?.recordPhraseSelection(
                phrase: candidate.text,
                pronunciationSequence: candidate.pronunciationSequence,
                at: selectedAt
            )
        }
    }

    private func exactPhraseCandidates(
        for pronunciation: String,
        queries: [CompositionPhraseQuery]
    ) throws -> [Candidate] {
        var seenQueries: Set<[String]> = []
        var seenCandidates: Set<CandidateID> = []
        var result: [Candidate] = []
        for query in queries {
            let readings = query.pronunciationSequence
            guard readings.last == pronunciation,
                  UserPhraseValidator.allowedUnitCount.contains(readings.count),
                  seenQueries.insert(readings).inserted else {
                continue
            }

            for record in learning?.phraseRecords(for: readings) ?? [] {
                guard record.pronunciationSequence == readings,
                      let identity = try? UserPhraseValidator.validate(
                          phrase: record.phrase,
                          pronunciationSequence: readings
                      ), identity.phrase == record.phrase,
                      identity.pronunciationSequence == readings else {
                    continue
                }
                let candidate = Candidate(
                    text: record.phrase,
                    pronunciationSequence: readings,
                    type: .phrase,
                    baseRank: result.count,
                    sourceOrder: record.phraseID,
                    baseFrequency: 0,
                    userFrequency: record.selectionCount,
                    lastUsed: record.lastUsedAt,
                    pinned: record.pinned
                )
                guard seenCandidates.insert(candidate.id).inserted else {
                    continue
                }
                result.append(candidate)
            }

            for entry in try dictionary.phraseEntries(for: readings) {
                guard entry.pronunciationSequence == readings,
                      entry.text.count == readings.count else {
                    continue
                }
                let candidate = Candidate(
                    text: entry.text,
                    pronunciationSequence: readings,
                    type: .phrase,
                    baseRank: result.count,
                    sourceOrder: entry.sourceOrder,
                    baseFrequency: 0
                )
                guard seenCandidates.insert(candidate.id).inserted else {
                    continue
                }
                result.append(candidate)
            }
        }
        return result
    }
}

private extension CandidateCommitReason {
    var recordsCandidateSelection: Bool {
        switch self {
        case .space,
             .returnKey,
             .number,
             .mouse,
             .implicitPassThrough,
             .lifecycle,
             .clientHandoff,
             .punctuation:
            return true
        }
    }
}
