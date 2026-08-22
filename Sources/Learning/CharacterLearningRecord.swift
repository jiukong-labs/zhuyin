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

    @discardableResult
    func deletePhrase(
        phrase: String,
        pronunciationSequence: [String]
    ) -> Bool
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

    @discardableResult
    func deletePhrase(
        phrase: String,
        pronunciationSequence: [String]
    ) -> Bool {
        false
    }
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

    func allCharacterRecords() throws -> [CharacterLearningRecord]
    func allPhraseRecords() throws -> [UserPhraseRecord]

    func deleteCharacterRecord(
        character: String,
        pronunciation: String
    ) throws

    func deletePhrase(
        phrase: String,
        pronunciationSequence: [String]
    ) throws

    @discardableResult
    func merge(_ archive: UserDataArchive) throws -> UserDataMergeSummary
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

    func allCharacterRecords() throws -> [CharacterLearningRecord] {
        []
    }

    func allPhraseRecords() throws -> [UserPhraseRecord] {
        []
    }

    func deleteCharacterRecord(
        character: String,
        pronunciation: String
    ) throws {}

    func deletePhrase(
        phrase: String,
        pronunciationSequence: [String]
    ) throws {}

    @discardableResult
    func merge(_ archive: UserDataArchive) throws -> UserDataMergeSummary {
        UserDataMergeSummary()
    }
}
