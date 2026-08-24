import Foundation

final class CharacterCandidateProvider {
    private let dictionary: CharacterDictionary
    private let learning: (any UserLearningProviding)?
    private let ranker: CandidateRanker
    private let isAutomaticLearningEnabled: () -> Bool
    private let showsRareCandidates: () -> Bool
    private let isCandidateDisplayable: (String) -> Bool
    private let now: () -> Date

    init(
        dictionary: CharacterDictionary,
        learning: (any UserLearningProviding)? = nil,
        ranker: CandidateRanker = CandidateRanker(),
        isAutomaticLearningEnabled: @escaping () -> Bool = { true },
        showsRareCandidates: @escaping () -> Bool = { false },
        isCandidateDisplayable: @escaping (String) -> Bool = { _ in true },
        now: @escaping () -> Date = Date.init
    ) {
        self.dictionary = dictionary
        self.learning = learning
        self.ranker = ranker
        self.isAutomaticLearningEnabled = isAutomaticLearningEnabled
        self.showsRareCandidates = showsRareCandidates
        self.isCandidateDisplayable = isCandidateDisplayable
        self.now = now
    }

    func candidates(
        for pronunciation: String,
        phraseQueries: [CompositionPhraseQuery] = []
    ) throws -> [Candidate] {
        let learningRecords = learning?.records(for: pronunciation) ?? [:]
        let includesRareCandidates = showsRareCandidates()
        let characterCandidates = try dictionary.candidateEntries(for: pronunciation)
            .filter {
                includesRareCandidates
                    || $0.isInGeneralCandidateRepertoire
            }
            .enumerated()
            .map { baseRank, entry in
                let learningRecord = learningRecords[entry.text]
                let phraseCount = max(0, entry.firstPartyPhraseCount)
                // Keep the three usage tiers strict while ranking entries
                // within a tier by evidence from Jiukong's own reviewed
                // phrase lexicon. count / (count + 1) stays below one, so it
                // can never cross a tier boundary.
                let firstPartyPhraseBonus = Double(phraseCount)
                    / (Double(phraseCount) + 1)
                return Candidate(
                    text: entry.text,
                    pronunciation: pronunciation,
                    baseRank: baseRank,
                    sourceOrder: entry.sourceOrder,
                    baseFrequency: Double(2 - entry.usageTier)
                        + firstPartyPhraseBonus,
                    userFrequency: learningRecord?.selectionCount ?? 0,
                    lastUsed: learningRecord?.lastSelectedAt,
                    pinned: learningRecord?.pinned ?? false
                )
            }

        let phraseCandidates = try exactPhraseCandidates(
            for: pronunciation,
            queries: phraseQueries
        )
        let displayableCandidates = (phraseCandidates + characterCandidates)
            .filter { isCandidateDisplayable($0.text) }
        return ranker.ranked(
            displayableCandidates,
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

    /// Removes exactly one user-authored phrase identity. Validation keeps an
    /// undo action from broadening into a text-only delete that could remove a
    /// different reading of the same phrase.
    @discardableResult
    func deleteUserPhrase(
        phrase: String,
        pronunciationSequence: [String]
    ) -> Bool {
        guard let identity = try? UserPhraseValidator.validate(
            phrase: phrase,
            pronunciationSequence: pronunciationSequence
        ) else {
            return false
        }
        return learning?.deletePhrase(
            phrase: identity.phrase,
            pronunciationSequence: identity.pronunciationSequence
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
