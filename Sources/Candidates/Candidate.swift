import Foundation

enum CandidateType: String, Equatable, Hashable {
    case character
    case phrase
}

struct CandidateID: Equatable, Hashable {
    let text: String
    let pronunciationSequence: [String]
    let type: CandidateType
    let outputPattern: PhraseOutputPattern

    init(
        text: String,
        pronunciationSequence: [String],
        type: CandidateType,
        outputPattern: PhraseOutputPattern
    ) {
        self.text = text
        self.pronunciationSequence = pronunciationSequence
        self.type = type
        self.outputPattern = outputPattern
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
    /// True only when this exact phrase identity came from the user's phrase
    /// store. The candidate window uses it to expose an exact delete action;
    /// built-in phrases and character candidates are never deletable there.
    let isUserPhrase: Bool
    let outputPattern: PhraseOutputPattern

    init(
        text: String,
        pronunciation: String,
        type: CandidateType = .character,
        baseRank: Int = 0,
        sourceOrder: Int64 = 0,
        baseFrequency: Double? = nil,
        userFrequency: Int64 = 0,
        lastUsed: Date? = nil,
        pinned: Bool = false,
        isUserPhrase: Bool = false,
        outputPattern: PhraseOutputPattern? = nil
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
            pinned: pinned,
            isUserPhrase: isUserPhrase,
            outputPattern: outputPattern
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
        pinned: Bool = false,
        isUserPhrase: Bool = false,
        outputPattern: PhraseOutputPattern? = nil
    ) {
        let resolvedPattern = outputPattern
            ?? PhraseOutputPattern.inferred(
                from: text,
                readingCount: pronunciationSequence.count
            )
            ?? PhraseOutputPattern(rawValue: "R")!
        self.id = CandidateID(
            text: text,
            pronunciationSequence: pronunciationSequence,
            type: type,
            outputPattern: resolvedPattern
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
        self.isUserPhrase = type == .phrase && isUserPhrase
        self.outputPattern = resolvedPattern
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
    case punctuation
}
