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
        service.recordSelection(character: "我", pronunciation: "ㄨㄛˇ")
        service.setPinned(true, character: "我", pronunciation: "ㄨㄛˇ")
    }

    func testServiceFallsBackWhenStorageThrows() {
        let service = UserLearningService(store: FailingLearningStore())

        XCTAssertEqual(service.records(for: "ㄨㄛˇ"), [:])
        service.recordSelection(character: "我", pronunciation: "ㄨㄛˇ")
        service.setPinned(true, character: "我", pronunciation: "ㄨㄛˇ")
    }
}

private final class ProbeLearningStore: UserLearningStoring {
    struct Selection {
        let character: String
        let pronunciation: String
        let date: Date
    }

    private let lock = NSLock()
    private let delay: TimeInterval
    private var selectionStorage: [Selection] = []
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

}
