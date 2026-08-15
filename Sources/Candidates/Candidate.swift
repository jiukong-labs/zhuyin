import Foundation

enum CandidateType: String, Equatable, Hashable {
    case character
    case phrase
}

struct CandidateID: Equatable, Hashable {
    let text: String
    let pronunciationSequence: [String]
    let type: CandidateType

    init(
        text: String,
        pronunciationSequence: [String],
        type: CandidateType
    ) {
        self.text = text
        self.pronunciationSequence = pronunciationSequence
        self.type = type
    }

    var pronunciation: String {
        pronunciationSequence.joined(separator: " ")
    }
}

struct Candidate: Identifiable, Equatable, Hashable {
    let id: CandidateID
    let text: String
    let pronunciationSequence: [String]
    let type: CandidateType
    let baseRank: Int
    let sourceOrder: Int64
    let baseFrequency: Double?
    let userFrequency: Int64
    let lastUsed: Date?
    let pinned: Bool

    init(
        text: String,
        pronunciation: String,
        type: CandidateType = .character,
        baseRank: Int = 0,
        sourceOrder: Int64 = 0,
        baseFrequency: Double? = nil,
        userFrequency: Int64 = 0,
        lastUsed: Date? = nil,
        pinned: Bool = false
    ) {
        self.init(
            text: text,
            pronunciationSequence: [pronunciation],
            type: type,
            baseRank: baseRank,
            sourceOrder: sourceOrder,
            baseFrequency: baseFrequency,
            userFrequency: userFrequency,
            lastUsed: lastUsed,
            pinned: pinned
        )
    }

    init(
        text: String,
        pronunciationSequence: [String],
        type: CandidateType,
        baseRank: Int = 0,
        sourceOrder: Int64 = 0,
        baseFrequency: Double? = nil,
        userFrequency: Int64 = 0,
        lastUsed: Date? = nil,
        pinned: Bool = false
    ) {
        self.id = CandidateID(
            text: text,
            pronunciationSequence: pronunciationSequence,
            type: type
        )
        self.text = text
        self.pronunciationSequence = pronunciationSequence
        self.type = type
        self.baseRank = baseRank
        self.sourceOrder = sourceOrder
        self.baseFrequency = baseFrequency
        self.userFrequency = userFrequency
        self.lastUsed = lastUsed
        self.pinned = pinned
    }

    var pronunciation: String {
        pronunciationSequence.joined(separator: " ")
    }
}

enum CandidateCommitReason: Equatable, Hashable {
    case space
    case returnKey
    case number(Int)
    case mouse
    case implicitPassThrough
    case lifecycle
    case clientHandoff
}
