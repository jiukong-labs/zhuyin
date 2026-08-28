import Foundation

struct CandidateRanker {
    static let defaultUserFrequencyWeight = 8.0
    static let defaultRecencyWeight = 4.0
    static let defaultRecencyHalfLife: TimeInterval = 7 * 24 * 60 * 60
    static let defaultPhraseBonus = 1_024.0

    let userFrequencyWeight: Double
    let recencyWeight: Double
    let recencyHalfLife: TimeInterval
    let phraseBonus: Double

    init(
        userFrequencyWeight: Double = Self.defaultUserFrequencyWeight,
        recencyWeight: Double = Self.defaultRecencyWeight,
        recencyHalfLife: TimeInterval = Self.defaultRecencyHalfLife,
        phraseBonus: Double = Self.defaultPhraseBonus
    ) {
        precondition(
            userFrequencyWeight.isFinite && userFrequencyWeight >= 0,
            "User-frequency weight must be finite and nonnegative."
        )
        precondition(
            recencyWeight.isFinite && recencyWeight >= 0,
            "Recency weight must be finite and nonnegative."
        )
        precondition(
            recencyHalfLife.isFinite && recencyHalfLife > 0,
            "Recency half-life must be finite and positive."
        )
        precondition(
            phraseBonus.isFinite && phraseBonus >= 0,
            "Phrase bonus must be finite and nonnegative."
        )

        self.userFrequencyWeight = userFrequencyWeight
        self.recencyWeight = recencyWeight
        self.recencyHalfLife = recencyHalfLife
        self.phraseBonus = phraseBonus
    }

    func ranked(
        _ candidates: [Candidate],
        at now: Date = Date()
    ) -> [Candidate] {
        candidates.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned {
                return lhs.pinned
            }

            // Exact phrase queries are emitted longest suffix first. Preserve
            // that composition boundary before applying frequency, otherwise
            // a frequent short phrase could replace only part of a longer
            // exact match and leave stale provisional characters behind.
            if lhs.type == .phrase, rhs.type == .phrase,
               lhs.pronunciationSequence.count
                    != rhs.pronunciationSequence.count {
                return lhs.pronunciationSequence.count
                    > rhs.pronunciationSequence.count
            }

            // A deliberate character choice should be useful on the very next
            // lookup, even when that character was far down the CNS source
            // order. Phrases keep their independent tier, and an explicit pin
            // remains stronger than automatic learning.
            if lhs.type == .character, rhs.type == .character {
                let lhsWasSelected = hasCommittedSelection(lhs)
                let rhsWasSelected = hasCommittedSelection(rhs)
                if lhsWasSelected != rhsWasSelected {
                    return lhsWasSelected
                }
                if lhsWasSelected,
                   lhs.lastUsed != rhs.lastUsed {
                    return isMoreRecent(lhs.lastUsed, than: rhs.lastUsed)
                }
            }

            let lhsScore = score(for: lhs, at: now)
            let rhsScore = score(for: rhs, at: now)
            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }
            if lhs.baseRank != rhs.baseRank {
                return lhs.baseRank < rhs.baseRank
            }
            if lhs.sourceOrder != rhs.sourceOrder {
                return lhs.sourceOrder < rhs.sourceOrder
            }
            if lhs.text != rhs.text {
                return lhs.text < rhs.text
            }
            if lhs.pronunciation != rhs.pronunciation {
                return lhs.pronunciation < rhs.pronunciation
            }
            return lhs.type.rawValue < rhs.type.rawValue
        }
    }

    func score(for candidate: Candidate, at now: Date = Date()) -> Double {
        let fallbackBaseScore = -Double(max(0, candidate.baseRank))
        let baseScore: Double
        if let baseFrequency = candidate.baseFrequency,
           baseFrequency.isFinite {
            baseScore = baseFrequency
        } else {
            baseScore = fallbackBaseScore
        }

        let userBonus = frequencyBonus(
            selectionCount: candidate.userFrequency
        )

        let recencyBonus: Double
        if let lastUsed = candidate.lastUsed {
            let age = max(0, now.timeIntervalSince(lastUsed))
            recencyBonus = recencyWeight
                * pow(0.5, age / recencyHalfLife)
        } else {
            recencyBonus = 0
        }

        let typeBonus = candidate.type == .phrase ? phraseBonus : 0
        return baseScore + userBonus + recencyBonus + typeBonus
    }

    func frequencyBonus(selectionCount: Int64) -> Double {
        userFrequencyWeight * log2(Double(max(0, selectionCount)) + 1)
    }

    private func hasCommittedSelection(_ candidate: Candidate) -> Bool {
        candidate.userFrequency > 0 || candidate.lastUsed != nil
    }

    private func isMoreRecent(_ lhs: Date?, than rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return lhs > rhs
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return false
        }
    }
}
