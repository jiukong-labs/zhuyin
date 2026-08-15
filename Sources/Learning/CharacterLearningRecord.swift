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
}
