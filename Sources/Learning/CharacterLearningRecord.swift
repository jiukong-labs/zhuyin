import Foundation

struct CharacterLearningRecord: Equatable {
    let character: String
    let pronunciation: String
    let selectionCount: Int64
    let lastSelectedAt: Date?
    let pinned: Bool
}

protocol UserLearningProviding: AnyObject {
    func records(for pronunciation: String) -> [String: CharacterLearningRecord]
    func recordSelection(character: String, pronunciation: String)

    func phraseRecords(
        for pronunciationSequence: [String]
    ) -> [UserPhraseRecord]

    @discardableResult
    func addPhrase(
        phrase: String,
        pronunciationSequence: [String],
        createdAt: Date
    ) -> Bool

    func recordPhraseSelection(
        phrase: String,
        pronunciationSequence: [String],
        at date: Date
    )

    func setPhrasePinned(
        _ pinned: Bool,
        phrase: String,
        pronunciationSequence: [String]
    )
}

extension UserLearningProviding {
    func phraseRecords(
        for pronunciationSequence: [String]
    ) -> [UserPhraseRecord] {
        []
    }

    @discardableResult
    func addPhrase(
        phrase: String,
        pronunciationSequence: [String],
        createdAt: Date
    ) -> Bool {
        false
    }

    func recordPhraseSelection(
        phrase: String,
        pronunciationSequence: [String],
        at date: Date
    ) {}

    func setPhrasePinned(
        _ pinned: Bool,
        phrase: String,
        pronunciationSequence: [String]
    ) {}
}

protocol UserLearningStoring: AnyObject {
    func records(
        for pronunciation: String
    ) throws -> [String: CharacterLearningRecord]

    func recordSelection(
        character: String,
        pronunciation: String,
        at date: Date
    ) throws

    func setPinned(
        _ pinned: Bool,
        character: String,
        pronunciation: String
    ) throws

    func phraseRecords(
        for pronunciationSequence: [String]
    ) throws -> [UserPhraseRecord]

    func addPhrase(
        phrase: String,
        pronunciationSequence: [String],
        createdAt: Date
    ) throws

    func recordPhraseSelection(
        phrase: String,
        pronunciationSequence: [String],
        at date: Date
    ) throws

    func setPhrasePinned(
        _ pinned: Bool,
        phrase: String,
        pronunciationSequence: [String]
    ) throws

    func clearCharacterLearning() throws
    func clearUserPhrases() throws
    func clearAllUserData() throws
}

extension UserLearningStoring {
    func phraseRecords(
        for pronunciationSequence: [String]
    ) throws -> [UserPhraseRecord] {
        []
    }

    func addPhrase(
        phrase: String,
        pronunciationSequence: [String],
        createdAt: Date
    ) throws {}

    func recordPhraseSelection(
        phrase: String,
        pronunciationSequence: [String],
        at date: Date
    ) throws {}

    func setPhrasePinned(
        _ pinned: Bool,
        phrase: String,
        pronunciationSequence: [String]
    ) throws {}

    func clearCharacterLearning() throws {}
    func clearUserPhrases() throws {}
    func clearAllUserData() throws {}
}
