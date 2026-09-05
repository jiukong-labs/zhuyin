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
        let includesRareCandidates = showsRareCandidates()
        var characterCandidates = try dictionaryCandidates(
            for: pronunciation,
            includesRareCandidates: includesRareCandidates,
            rankOffset: 0
        )

        // Neutral tone remains a convenient "don't care which tone"
        // shortcut in fast/casual speech. First tone is different: Space is
        // an explicit tone key in every supported layout, so widening it
        // would let a learned candidate from another tone replace the typed
        // reading and break exact phrase lookup (for example, ㄐㄧㄣ ㄊㄧㄢ
        // must still be able to resolve to 「今天」).
        if let body = CanonicalBopomofoReading.neutralToneBody(
            of: pronunciation
        ) {
            var seenText = Set(characterCandidates.map(\.text))
            let otherTonedReadings = CanonicalBopomofoReading
                .tonedReadings(forBody: body)
                .filter { $0 != pronunciation }
            for tonedReading in otherTonedReadings {
                let tonedCandidates = try dictionaryCandidates(
                    for: tonedReading,
                    includesRareCandidates: includesRareCandidates,
                    rankOffset: characterCandidates.count
                ).filter { seenText.insert($0.text).inserted }
                characterCandidates.append(contentsOf: tonedCandidates)
            }
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

    private func dictionaryCandidates(
        for pronunciation: String,
        includesRareCandidates: Bool,
        rankOffset: Int
    ) throws -> [Candidate] {
        let learningRecords = learning?.records(for: pronunciation) ?? [:]
        return try dictionary.candidateEntries(for: pronunciation)
            .filter {
                includesRareCandidates
                    || $0.isInGeneralCandidateRepertoire
            }
            .enumerated()
            .map { index, entry in
                let learningRecord = learningRecords[entry.text]
                let phraseCount = max(0, entry.firstPartyPhraseCount)
                // The phrase-attestation component orders entries within an
                // MOE tier: count / (count + 1) stays below one, so that
                // component alone cannot cross a tier boundary. The captured
                // first-party selection prior is deliberately stronger and
                // may promote a repeatedly chosen entry across tiers.
                let firstPartyPhraseBonus = Double(phraseCount)
                    / (Double(phraseCount) + 1)
                let defaultSelectionBonus = ranker.frequencyBonus(
                    selectionCount: entry.defaultSelectionCount
                )
                return Candidate(
                    text: entry.text,
                    pronunciation: pronunciation,
                    baseRank: rankOffset + index,
                    sourceOrder: entry.sourceOrder,
                    baseFrequency: Double(2 - entry.usageTier)
                        + firstPartyPhraseBonus
                        + defaultSelectionBonus,
                    userFrequency: learningRecord?.selectionCount ?? 0,
                    lastUsed: learningRecord?.lastSelectedAt,
                    pinned: learningRecord?.pinned ?? false
                )
            }
    }

    @discardableResult
    func addUserPhrase(
        phrase: String,
        pronunciationSequence: [String],
        outputPattern: PhraseOutputPattern? = nil
    ) -> Bool {
        guard let identity = try? UserPhraseValidator.validate(
            phrase: phrase,
            pronunciationSequence: pronunciationSequence,
            outputPattern: outputPattern
        ) else {
            return false
        }
        return learning?.addPhrase(
            phrase: identity.phrase,
            pronunciationSequence: identity.pronunciationSequence,
            outputPattern: identity.outputPattern,
            createdAt: now()
        ) ?? false
    }

    /// Removes exactly one user-authored phrase identity, leaving any built-in
    /// phrase with the same identity alone. This is the undo for an explicit
    /// save, so it must not decide anything about the dictionary's own entry.
    /// Validation keeps the undo from broadening into a text-only delete that
    /// could remove a different reading of the same phrase.
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

    /// Removes one phrase candidate from the candidate window for good.
    ///
    /// A user-authored row is deleted outright. An identity the built-in
    /// dictionary also carries additionally records a suppression in the
    /// user's own database, so a dictionary shipped with a later app update
    /// cannot bring the phrase back and the user's own list keeps converging
    /// on what they type. A phrase the dictionary never had leaves no
    /// suppression, which keeps the restore list to genuine built-in entries.
    @discardableResult
    func deletePhraseCandidate(
        phrase: String,
        pronunciationSequence: [String],
        isUserPhrase: Bool
    ) -> Bool {
        guard let identity = try? UserPhraseValidator.validate(
            phrase: phrase,
            pronunciationSequence: pronunciationSequence
        ) else {
            return false
        }
        var removed = false
        if isUserPhrase {
            removed = learning?.deletePhrase(
                phrase: identity.phrase,
                pronunciationSequence: identity.pronunciationSequence
            ) ?? false
        }

        var suppressed = false
        if dictionaryContainsPhrase(identity) {
            suppressed = learning?.suppressPhrase(
                phrase: identity.phrase,
                pronunciationSequence: identity.pronunciationSequence,
                at: now()
            ) ?? false
        }
        return removed || suppressed
    }

    /// A dictionary read failure must not turn a delete into a silent no-op,
    /// so an unreadable dictionary is treated as not carrying the phrase and
    /// the user-authored removal above still stands.
    private func dictionaryContainsPhrase(
        _ identity: ValidatedUserPhrase
    ) -> Bool {
        let entries = (try? dictionary.phraseEntries(
            for: identity.pronunciationSequence
        )) ?? []
        return entries.contains {
            $0.text == identity.phrase
                && $0.pronunciationSequence == identity.pronunciationSequence
        }
    }

    /// Lets a previously removed built-in phrase appear again.
    @discardableResult
    func restorePhrase(
        phrase: String,
        pronunciationSequence: [String]
    ) -> Bool {
        guard let identity = try? UserPhraseValidator.validate(
            phrase: phrase,
            pronunciationSequence: pronunciationSequence
        ) else {
            return false
        }
        return learning?.restorePhrase(
            phrase: identity.phrase,
            pronunciationSequence: identity.pronunciationSequence
        ) ?? false
    }

    /// Removes only the explicit pin represented by a candidate. Character
    /// selection counts and user-authored phrases remain intact.
    @discardableResult
    func removePin(from candidate: Candidate) -> Bool {
        guard candidate.pinned, let learning else {
            return false
        }

        switch candidate.type {
        case .character:
            guard candidate.text.count == 1,
                  candidate.pronunciationSequence.count == 1,
                  let pronunciation = candidate.pronunciationSequence.first,
                  !pronunciation.isEmpty else {
                return false
            }
            learning.setPinned(
                false,
                character: candidate.text,
                pronunciation: pronunciation
            )
        case .phrase:
            guard let identity = try? UserPhraseValidator.validate(
                phrase: candidate.text,
                pronunciationSequence: candidate.pronunciationSequence,
                outputPattern: candidate.outputPattern
            ) else {
                return false
            }
            learning.setPhrasePinned(
                false,
                phrase: identity.phrase,
                pronunciationSequence: identity.pronunciationSequence
            )
        }
        return true
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
                pronunciationSequence: candidate.pronunciationSequence,
                outputPattern: candidate.outputPattern
            ), identity.phrase == candidate.text,
                  identity.pronunciationSequence
                    == candidate.pronunciationSequence else {
                return
            }
            let selectedAt = now()
            _ = learning?.addPhrase(
                phrase: candidate.text,
                pronunciationSequence: candidate.pronunciationSequence,
                outputPattern: candidate.outputPattern,
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
                  (1 ... UserPhraseValidator.allowedUnitCount.upperBound)
                    .contains(readings.count),
                  seenQueries.insert(readings).inserted else {
                continue
            }

            // A removed built-in phrase is filtered out of the dictionary's
            // own results only. A user-authored row with the same identity is
            // an explicit choice and still shows. Most reading sequences match
            // no phrase at all, so the suppression read only happens when the
            // dictionary actually returned something to filter.
            let matchedEntries = try dictionary.phraseEntries(for: readings)
            let suppressedTexts = matchedEntries.isEmpty
                ? []
                : learning?.suppressedPhrases(for: readings) ?? []
            let dictionaryEntries = matchedEntries
                .filter { !suppressedTexts.contains($0.text) }
            let dictionaryEntriesByText = Dictionary(
                uniqueKeysWithValues: dictionaryEntries.map { ($0.text, $0) }
            )

            for record in learning?.phraseRecords(for: readings) ?? [] {
                guard record.pronunciationSequence == readings,
                      let identity = try? UserPhraseValidator.validate(
                          phrase: record.phrase,
                          pronunciationSequence: readings,
                          outputPattern: record.outputPattern
                      ), identity.phrase == record.phrase,
                      identity.pronunciationSequence == readings,
                      phrasePatternIsCompatible(
                          identity.outputPattern,
                          text: identity.phrase,
                          query: query
                      ) else {
                    continue
                }
                let candidate = Candidate(
                    text: record.phrase,
                    pronunciationSequence: readings,
                    type: .phrase,
                    baseRank: result.count,
                    sourceOrder: record.phraseID,
                    baseFrequency: ranker.frequencyBonus(
                        selectionCount: dictionaryEntriesByText[
                            record.phrase
                        ]?.defaultSelectionCount ?? 0
                    ),
                    userFrequency: record.selectionCount,
                    lastUsed: record.lastUsedAt,
                    pinned: record.pinned,
                    isUserPhrase: true,
                    outputPattern: record.outputPattern
                )
                guard seenCandidates.insert(candidate.id).inserted else {
                    continue
                }
                result.append(candidate)
            }

            for entry in dictionaryEntries {
                guard entry.pronunciationSequence == readings,
                      phrasePatternIsCompatible(
                          entry.outputPattern,
                          text: entry.text,
                          query: query
                      ) else {
                    continue
                }
                let candidate = Candidate(
                    text: entry.text,
                    pronunciationSequence: readings,
                    type: .phrase,
                    baseRank: result.count,
                    sourceOrder: entry.sourceOrder,
                    baseFrequency: ranker.frequencyBonus(
                        selectionCount: entry.defaultSelectionCount
                    ),
                    outputPattern: entry.outputPattern
                )
                guard seenCandidates.insert(candidate.id).inserted else {
                    continue
                }
                result.append(candidate)
            }
        }
        return result
    }

    private func phrasePatternIsCompatible(
        _ pattern: PhraseOutputPattern,
        text: String,
        query: CompositionPhraseQuery
    ) -> Bool {
        guard pattern.validates(
            text: text,
            readingCount: query.pronunciationSequence.count
        ) else {
            return false
        }
        guard query.existingOutputPattern?.containsPunctuation == true else {
            return true
        }
        let markers = pattern.markers
        guard let finalReadingIndex = markers.lastIndex(
            of: PhraseOutputPattern.readingMarker
        ) else {
            return false
        }
        let prefixMarkers = String(markers[..<finalReadingIndex])
        guard prefixMarkers == query.existingOutputPattern?.rawValue else {
            return false
        }
        let prefixCharacters = Array(text)[..<finalReadingIndex]
        let punctuation = zip(prefixCharacters, markers[..<finalReadingIndex])
            .compactMap { character, marker in
                marker == PhraseOutputPattern.punctuationMarker
                    ? String(character)
                    : nil
            }.joined()
        return punctuation == query.existingPunctuationText
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
