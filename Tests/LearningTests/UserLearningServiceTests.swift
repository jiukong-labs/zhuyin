import Foundation
import XCTest

final class UserLearningServiceTests: XCTestCase {
    func testServiceUsesInjectedClockAndStore() {
        let store = ProbeLearningStore()
        let date = Date(timeIntervalSince1970: 1_234)
        let service = UserLearningService(store: store, now: { date })

        service.recordSelection(
            character: "鍵",
            pronunciation: "ㄐㄧㄢˋ"
        )

        XCTAssertEqual(store.selections.count, 1)
        XCTAssertEqual(store.selections.first?.character, "鍵")
        XCTAssertEqual(store.selections.first?.pronunciation, "ㄐㄧㄢˋ")
        XCTAssertEqual(store.selections.first?.date, date)
    }

    func testServiceSerializesConcurrentCalls() {
        let store = ProbeLearningStore(delay: 0.001)
        let service = UserLearningService(store: store)

        DispatchQueue.concurrentPerform(iterations: 80) { _ in
            service.recordSelection(
                character: "我",
                pronunciation: "ㄨㄛˇ"
            )
        }

        XCTAssertEqual(store.selections.count, 80)
        XCTAssertEqual(store.maximumConcurrentCalls, 1)
    }

    func testServiceReturnsEmptyRecordsWhenStorageIsUnavailable() {
        let service = UserLearningService(store: nil)

        XCTAssertEqual(service.records(for: "ㄨㄛˇ"), [:])
        XCTAssertEqual(service.phraseRecords(for: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"]), [])
        service.recordSelection(character: "我", pronunciation: "ㄨㄛˇ")
        service.setPinned(true, character: "我", pronunciation: "ㄨㄛˇ")
        XCTAssertFalse(
            service.addPhrase(
                phrase: "久空",
                pronunciationSequence: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"],
                createdAt: Date()
            )
        )
        service.recordPhraseSelection(
            phrase: "久空",
            pronunciationSequence: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"],
            at: Date()
        )
        service.setPhrasePinned(
            true,
            phrase: "久空",
            pronunciationSequence: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"]
        )
    }

    func testServiceFallsBackWhenStorageThrows() {
        let service = UserLearningService(store: FailingLearningStore())

        XCTAssertEqual(service.records(for: "ㄨㄛˇ"), [:])
        XCTAssertEqual(service.phraseRecords(for: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"]), [])
        service.recordSelection(character: "我", pronunciation: "ㄨㄛˇ")
        service.setPinned(true, character: "我", pronunciation: "ㄨㄛˇ")
        XCTAssertFalse(
            service.addPhrase(
                phrase: "久空",
                pronunciationSequence: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"],
                createdAt: Date()
            )
        )
        service.recordPhraseSelection(
            phrase: "久空",
            pronunciationSequence: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"],
            at: Date()
        )
        service.setPhrasePinned(
            true,
            phrase: "久空",
            pronunciationSequence: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"]
        )
    }

    func testServiceForwardsPhraseOperationsAndExplicitDates() {
        let store = ProbeLearningStore()
        let service = UserLearningService(store: store)
        let createdAt = Date(timeIntervalSince1970: 100)
        let selectedAt = Date(timeIntervalSince1970: 200)
        let readings = ["ㄐㄧㄡˇ", "ㄎㄨㄥ"]
        store.phraseRecordsResult = [
            UserPhraseRecord(
                phraseID: 7,
                phrase: "久空",
                pronunciationSequence: readings,
                createdAt: createdAt,
                lastUsedAt: nil,
                selectionCount: 0,
                pinned: false
            ),
        ]

        XCTAssertTrue(
            service.addPhrase(
                phrase: "久空",
                pronunciationSequence: readings,
                createdAt: createdAt
            )
        )
        service.recordPhraseSelection(
            phrase: "久空",
            pronunciationSequence: readings,
            at: selectedAt
        )
        service.setPhrasePinned(
            true,
            phrase: "久空",
            pronunciationSequence: readings
        )

        XCTAssertEqual(service.phraseRecords(for: readings), store.phraseRecordsResult)
        XCTAssertEqual(store.phraseAdditions.count, 1)
        XCTAssertEqual(store.phraseAdditions.first?.phrase, "久空")
        XCTAssertEqual(store.phraseAdditions.first?.readings, readings)
        XCTAssertEqual(store.phraseAdditions.first?.date, createdAt)
        XCTAssertEqual(store.phraseSelections.first?.date, selectedAt)
        XCTAssertEqual(store.phrasePins.first?.pinned, true)
    }
}

private final class ProbeLearningStore: UserLearningStoring {
    struct Selection {
        let character: String
        let pronunciation: String
        let date: Date
    }

    struct PhraseOperation {
        let phrase: String
        let readings: [String]
        let date: Date
    }

    struct PhrasePin {
        let phrase: String
        let readings: [String]
        let pinned: Bool
    }

    private let lock = NSLock()
    private let delay: TimeInterval
    private var selectionStorage: [Selection] = []
    private var phraseAdditionStorage: [PhraseOperation] = []
    private var phraseSelectionStorage: [PhraseOperation] = []
    private var phrasePinStorage: [PhrasePin] = []
    var phraseRecordsResult: [UserPhraseRecord] = []
    private var currentConcurrentCalls = 0
    private var maximumConcurrentCallsStorage = 0

    init(delay: TimeInterval = 0) {
        self.delay = delay
    }

    var selections: [Selection] {
        lock.lock()
        defer { lock.unlock() }
        return selectionStorage
    }

    var maximumConcurrentCalls: Int {
        lock.lock()
        defer { lock.unlock() }
        return maximumConcurrentCallsStorage
    }

    var phraseAdditions: [PhraseOperation] {
        lock.lock()
        defer { lock.unlock() }
        return phraseAdditionStorage
    }

    var phraseSelections: [PhraseOperation] {
        lock.lock()
        defer { lock.unlock() }
        return phraseSelectionStorage
    }

    var phrasePins: [PhrasePin] {
        lock.lock()
        defer { lock.unlock() }
        return phrasePinStorage
    }

    func records(
        for pronunciation: String
    ) throws -> [String: CharacterLearningRecord] {
        [:]
    }

    func recordSelection(
        character: String,
        pronunciation: String,
        at date: Date
    ) throws {
        beginCall()
        if delay > 0 {
            Thread.sleep(forTimeInterval: delay)
        }
        lock.lock()
        selectionStorage.append(
            Selection(
                character: character,
                pronunciation: pronunciation,
                date: date
            )
        )
        lock.unlock()
        endCall()
    }

    func setPinned(
        _ pinned: Bool,
        character: String,
        pronunciation: String
    ) throws {
        beginCall()
        endCall()
    }

    func phraseRecords(
        for pronunciationSequence: [String]
    ) throws -> [UserPhraseRecord] {
        beginCall()
        defer { endCall() }
        return phraseRecordsResult
    }

    func addPhrase(
        phrase: String,
        pronunciationSequence: [String],
        createdAt: Date
    ) throws {
        beginCall()
        lock.lock()
        phraseAdditionStorage.append(
            PhraseOperation(
                phrase: phrase,
                readings: pronunciationSequence,
                date: createdAt
            )
        )
        lock.unlock()
        endCall()
    }

    func recordPhraseSelection(
        phrase: String,
        pronunciationSequence: [String],
        at date: Date
    ) throws {
        beginCall()
        lock.lock()
        phraseSelectionStorage.append(
            PhraseOperation(
                phrase: phrase,
                readings: pronunciationSequence,
                date: date
            )
        )
        lock.unlock()
        endCall()
    }

    func setPhrasePinned(
        _ pinned: Bool,
        phrase: String,
        pronunciationSequence: [String]
    ) throws {
        beginCall()
        lock.lock()
        phrasePinStorage.append(
            PhrasePin(
                phrase: phrase,
                readings: pronunciationSequence,
                pinned: pinned
            )
        )
        lock.unlock()
        endCall()
    }


    private func beginCall() {
        lock.lock()
        currentConcurrentCalls += 1
        maximumConcurrentCallsStorage = max(
            maximumConcurrentCallsStorage,
            currentConcurrentCalls
        )
        lock.unlock()
    }

    private func endCall() {
        lock.lock()
        currentConcurrentCalls -= 1
        lock.unlock()
    }
}

private final class FailingLearningStore: UserLearningStoring {
    private enum Failure: Error {
        case expected
    }

    func records(
        for pronunciation: String
    ) throws -> [String: CharacterLearningRecord] {
        throw Failure.expected
    }

    func recordSelection(
        character: String,
        pronunciation: String,
        at date: Date
    ) throws {
        throw Failure.expected
    }

    func setPinned(
        _ pinned: Bool,
        character: String,
        pronunciation: String
    ) throws {
        throw Failure.expected
    }

    func phraseRecords(
        for pronunciationSequence: [String]
    ) throws -> [UserPhraseRecord] {
        throw Failure.expected
    }

    func addPhrase(
        phrase: String,
        pronunciationSequence: [String],
        createdAt: Date
    ) throws {
        throw Failure.expected
    }

    func recordPhraseSelection(
        phrase: String,
        pronunciationSequence: [String],
        at date: Date
    ) throws {
        throw Failure.expected
    }

    func setPhrasePinned(
        _ pinned: Bool,
        phrase: String,
        pronunciationSequence: [String]
    ) throws {
        throw Failure.expected
    }

}
