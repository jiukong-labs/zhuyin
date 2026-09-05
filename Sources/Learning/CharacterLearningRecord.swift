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

    func setPinned(
        _ pinned: Bool,
        character: String,
        pronunciation: String
    )

    func phraseRecords(
        for pronunciationSequence: [String]
    ) -> [UserPhraseRecord]

    @discardableResult
    func addPhrase(
        phrase: String,
        pronunciationSequence: [String],
        createdAt: Date
    ) -> Bool

    @discardableResult
    func addPhrase(
        phrase: String,
        pronunciationSequence: [String],
        outputPattern: PhraseOutputPattern,
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

    /// The built-in phrase texts the user removed for this exact reading
    /// sequence. Candidate lookup drops them from the dictionary's own
    /// results.
    func suppressedPhrases(
        for pronunciationSequence: [String]
    ) -> Set<String>

    @discardableResult
    func suppressPhrase(
        phrase: String,
        pronunciationSequence: [String],
        at date: Date
    ) -> Bool

    @discardableResult
    func restorePhrase(
        phrase: String,
        pronunciationSequence: [String]
    ) -> Bool
}

extension UserLearningProviding {
    func setPinned(
        _ pinned: Bool,
        character: String,
        pronunciation: String
    ) {}

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

    @discardableResult
    func addPhrase(
        phrase: String,
        pronunciationSequence: [String],
        outputPattern: PhraseOutputPattern,
        createdAt: Date
    ) -> Bool {
        addPhrase(
            phrase: phrase,
            pronunciationSequence: pronunciationSequence,
            createdAt: createdAt
        )
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

    func suppressedPhrases(
        for pronunciationSequence: [String]
    ) -> Set<String> {
        []
    }

    @discardableResult
    func suppressPhrase(
        phrase: String,
        pronunciationSequence: [String],
        at date: Date
    ) -> Bool {
        false
    }

    @discardableResult
    func restorePhrase(
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

    func addPhrase(
        phrase: String,
        pronunciationSequence: [String],
        outputPattern: PhraseOutputPattern,
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

    func suppressedPhrases(
        for pronunciationSequence: [String]
    ) throws -> Set<String>

    func suppressPhrase(
        phrase: String,
        pronunciationSequence: [String],
        at date: Date
    ) throws

    func restorePhrase(
        phrase: String,
        pronunciationSequence: [String]
    ) throws

    func clearCharacterLearning() throws
    func clearUserPhrases() throws
    func clearSuppressedPhrases() throws
    func clearAllUserData() throws

    func allCharacterRecords() throws -> [CharacterLearningRecord]
    func allPhraseRecords() throws -> [UserPhraseRecord]
    func allSuppressedPhrases() throws -> [SuppressedPhraseRecord]

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

    func addPhrase(
        phrase: String,
        pronunciationSequence: [String],
        outputPattern: PhraseOutputPattern,
        createdAt: Date
    ) throws {
        try addPhrase(
            phrase: phrase,
            pronunciationSequence: pronunciationSequence,
            createdAt: createdAt
        )
    }

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

    func suppressedPhrases(
        for pronunciationSequence: [String]
    ) throws -> Set<String> {
        []
    }

    func suppressPhrase(
        phrase: String,
        pronunciationSequence: [String],
        at date: Date
    ) throws {}

    func restorePhrase(
        phrase: String,
        pronunciationSequence: [String]
    ) throws {}

    func clearCharacterLearning() throws {}
    func clearUserPhrases() throws {}
    func clearSuppressedPhrases() throws {}
    func clearAllUserData() throws {}

    func allCharacterRecords() throws -> [CharacterLearningRecord] {
        []
    }

    func allPhraseRecords() throws -> [UserPhraseRecord] {
        []
    }

    func allSuppressedPhrases() throws -> [SuppressedPhraseRecord] {
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
