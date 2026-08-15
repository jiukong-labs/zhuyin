import Foundation

struct CandidateRanker {
    static let defaultUserFrequencyWeight = 8.0
    static let defaultRecencyWeight = 4.0
    static let defaultRecencyHalfLife: TimeInterval = 7 * 24 * 60 * 60

    let userFrequencyWeight: Double
    let recencyWeight: Double
    let recencyHalfLife: TimeInterval

    init(
        userFrequencyWeight: Double = Self.defaultUserFrequencyWeight,
        recencyWeight: Double = Self.defaultRecencyWeight,
        recencyHalfLife: TimeInterval = Self.defaultRecencyHalfLife
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

        self.userFrequencyWeight = userFrequencyWeight
        self.recencyWeight = recencyWeight
        self.recencyHalfLife = recencyHalfLife
    }

    func ranked(
        _ candidates: [Candidate],
        at now: Date = Date()
    ) -> [Candidate] {
        candidates.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned {
                return lhs.pinned
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

        let selectionCount = max(0, candidate.userFrequency)
        let userBonus = userFrequencyWeight
            * log2(Double(selectionCount) + 1)

        let recencyBonus: Double
        if let lastUsed = candidate.lastUsed {
            let age = max(0, now.timeIntervalSince(lastUsed))
            recencyBonus = recencyWeight
                * pow(0.5, age / recencyHalfLife)
        } else {
            recencyBonus = 0
        }

        return baseScore + userBonus + recencyBonus
    }
}
