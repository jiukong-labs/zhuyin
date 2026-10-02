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

/// How a phrase candidate that starts inside an automatically accepted
/// provisional phrase rebuilds that phrase. The candidate takes the
/// provisional phrase's trailing readings; each reading left in front of it
/// becomes the matching standalone character in `remainderTexts` again.
struct ProvisionalPhraseSplit: Equatable, Hashable {
    let remainderTexts: [String]
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
    /// Set only on a phrase the chooser offers across a provisional phrase
    /// boundary, such as 「維萱」 after the provisional 「視為」.
    let provisionalSplit: ProvisionalPhraseSplit?

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
        outputPattern: PhraseOutputPattern? = nil,
        provisionalSplit: ProvisionalPhraseSplit? = nil
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
        self.provisionalSplit = type == .phrase ? provisionalSplit : nil
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
    /// A hidden preview accepted while typing continues; its phrase may grow.
    case automaticContinuation
    case implicitPassThrough
    case lifecycle
    case clientHandoff
    case punctuation
}
