import Foundation
import XCTest

final class UserDataCloudSyncCoordinatorTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
        try super.tearDownWithError()
    }

    func testFirstSyncRestoresRemoteCharacterAndPhrase() throws {
        let store = try makeStore()
        let transport = ProbeCloudTransport(records: [
            try cloudCharacter(count: 5, pinned: true),
            try cloudPhrase(count: 3, pinned: false),
        ])
        let stateStore = MemoryCloudSyncStateStore()
        let date = Date(timeIntervalSince1970: 123)
        let coordinator = makeCoordinator(
            store: store,
            transport: transport,
            stateStore: stateStore,
            now: { date }
        )

        waitForSync(coordinator)

        let character = try XCTUnwrap(
            try store.records(for: "ㄐㄧㄢˋ")["鍵"]
        )
        XCTAssertEqual(character.selectionCount, 5)
        XCTAssertTrue(character.pinned)
        let phrase = try XCTUnwrap(try store.allPhraseRecords().first)
        XCTAssertEqual(phrase.phrase, "久空")
        XCTAssertEqual(phrase.selectionCount, 3)
        XCTAssertEqual(transport.savedRecords.count, 2)
        XCTAssertTrue(stateStore.load().completedInitialMerge)
        XCTAssertTrue(stateStore.load().pending.isEmpty)
        XCTAssertEqual(coordinator.status, .idle(lastSuccessfulSync: date))
    }

    func testFirstSyncUploadsExistingLocalLearning() throws {
        let store = try makeStore()
        try store.recordSelection(
            character: "鍵",
            pronunciation: "ㄐㄧㄢˋ",
            at: Date(timeIntervalSince1970: 9)
        )
        let transport = ProbeCloudTransport()
        let coordinator = makeCoordinator(store: store, transport: transport)

        waitForSync(coordinator)

        XCTAssertEqual(transport.savedRecords.count, 1)
        XCTAssertEqual(transport.savedRecords.first?.identity.text, "鍵")
        guard case let .character(record) = transport.savedRecords.first?.payload
        else {
            return XCTFail("Expected an active character upload")
        }
        XCTAssertEqual(record.selectionCount, 1)
    }

    func testRemoteTombstoneDeletesLocalEntry() throws {
        let store = try makeStore()
        try store.recordSelection(character: "鍵", pronunciation: "ㄐㄧㄢˋ")
        let identity = try CloudUserDataIdentity(
            character: "鍵",
            pronunciation: "ㄐㄧㄢˋ"
        )
        let state = completedState()
        let stateStore = MemoryCloudSyncStateStore(state: state)
        let transport = ProbeCloudTransport(records: [
            try .tombstone(identity),
        ])
        let coordinator = makeCoordinator(
            store: store,
            transport: transport,
            stateStore: stateStore
        )

        waitForSync(coordinator)

        XCTAssertTrue(try store.allCharacterRecords().isEmpty)
        XCTAssertTrue(transport.savedRecords.isEmpty)
    }

    func testPendingLocalDeletionWinsOverRemoteActiveRecord() throws {
        let store = try makeStore()
        let identity = try CloudUserDataIdentity(
            character: "鍵",
            pronunciation: "ㄐㄧㄢˋ"
        )
        var state = completedState()
        state.note(.delete, identity: identity)
        let stateStore = MemoryCloudSyncStateStore(state: state)
        let transport = ProbeCloudTransport(records: [
            try cloudCharacter(count: 8, pinned: true),
        ])
        let coordinator = makeCoordinator(
            store: store,
            transport: transport,
            stateStore: stateStore
        )

        waitForSync(coordinator)

        XCTAssertTrue(try store.allCharacterRecords().isEmpty)
        XCTAssertEqual(transport.savedRecords.count, 1)
        XCTAssertEqual(transport.savedRecords.first?.payload, .deleted)
        XCTAssertTrue(stateStore.load().pending.isEmpty)
    }

    func testPendingLocalUpsertWinsOverRemoteTombstone() throws {
        let store = try makeStore()
        try store.recordSelection(character: "鍵", pronunciation: "ㄐㄧㄢˋ")
        let identity = try CloudUserDataIdentity(
            character: "鍵",
            pronunciation: "ㄐㄧㄢˋ"
        )
        var state = completedState()
        state.note(.upsert, identity: identity)
        let stateStore = MemoryCloudSyncStateStore(state: state)
        let transport = ProbeCloudTransport(records: [
            try .tombstone(identity),
        ])
        let coordinator = makeCoordinator(
            store: store,
            transport: transport,
            stateStore: stateStore
        )

        waitForSync(coordinator)

        XCTAssertEqual(try store.allCharacterRecords().map(\.character), ["鍵"])
        guard case .character = transport.savedRecords.first?.payload else {
            return XCTFail("Expected the local active record to be uploaded")
        }
    }

    func testRemoteUnpinIsAppliedExactlyWhenNoLocalMutationExists() throws {
        let store = try makeStore()
        try store.setPinned(true, character: "鍵", pronunciation: "ㄐㄧㄢˋ")
        let transport = ProbeCloudTransport(records: [
            try cloudCharacter(count: 0, pinned: false),
        ])
        let coordinator = makeCoordinator(
            store: store,
            transport: transport,
            stateStore: MemoryCloudSyncStateStore(state: completedState())
        )

        waitForSync(coordinator)

        XCTAssertFalse(try XCTUnwrap(
            try store.records(for: "ㄐㄧㄢˋ")["鍵"]
        ).pinned)
    }

    func testFailedSaveKeepsPendingMutationForRetry() throws {
        let store = try makeStore()
        try store.recordSelection(character: "鍵", pronunciation: "ㄐㄧㄢˋ")
        let identity = try CloudUserDataIdentity(
            character: "鍵",
            pronunciation: "ㄐㄧㄢˋ"
        )
        var state = completedState()
        state.note(.upsert, identity: identity)
        let stateStore = MemoryCloudSyncStateStore(state: state)
        let transport = ProbeCloudTransport(saveError: ProbeError.failed)
        let coordinator = makeCoordinator(
            store: store,
            transport: transport,
            stateStore: stateStore
        )

        waitForSync(coordinator)

        XCTAssertEqual(stateStore.load().pending.count, 1)
        guard case .unavailable = coordinator.status else {
            return XCTFail("Expected unavailable status")
        }
    }

    func testDisabledCoordinatorNeverTouchesTransport() throws {
        let store = try makeStore()
        let transport = ProbeCloudTransport()
        let coordinator = UserDataCloudSyncCoordinator(
            store: store,
            transport: transport,
            stateStore: MemoryCloudSyncStateStore(),
            isEnabled: { false },
            retryInterval: 60
        )

        waitForSync(coordinator)

        XCTAssertEqual(coordinator.status, .disabled)
        XCTAssertEqual(transport.fetchCount, 0)
    }

    private func makeCoordinator(
        store: UserLearningStore,
        transport: ProbeCloudTransport,
        stateStore: CloudSyncStateStoring = MemoryCloudSyncStateStore(),
        now: @escaping () -> Date = Date.init
    ) -> UserDataCloudSyncCoordinator {
        UserDataCloudSyncCoordinator(
            store: store,
            transport: transport,
            stateStore: stateStore,
            isEnabled: { true },
            now: now,
            debounceInterval: 0,
            retryInterval: 60
        )
    }

    private func waitForSync(
        _ coordinator: UserDataCloudSyncCoordinator,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let completed = expectation(description: "cloud sync")
        coordinator.synchronizeNow {
            completed.fulfill()
        }
        wait(for: [completed], timeout: 2)
    }

    private func cloudCharacter(
        count: Int64,
        pinned: Bool
    ) throws -> CloudUserDataRecord {
        let identity = try CloudUserDataIdentity(
            character: "鍵",
            pronunciation: "ㄐㄧㄢˋ"
        )
        return try CloudUserDataRecord(
            identity: identity,
            payload: .character(
                ArchivedCharacter(
                    character: "鍵",
                    pronunciation: "ㄐㄧㄢˋ",
                    selectionCount: count,
                    lastSelectedAt: 10_000,
                    pinned: pinned
                )
            )
        )
    }

    private func cloudPhrase(
        count: Int64,
        pinned: Bool
    ) throws -> CloudUserDataRecord {
        let identity = try CloudUserDataIdentity(
            phrase: "久空",
            readings: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"]
        )
        return try CloudUserDataRecord(
            identity: identity,
            payload: .phrase(
                ArchivedPhrase(
                    phrase: "久空",
                    readings: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"],
                    selectionCount: count,
                    createdAt: 1_000,
                    lastUsedAt: 9_000,
                    pinned: pinned
                )
            )
        )
    }

    private func completedState() -> CloudSyncPersistedState {
        var state = CloudSyncPersistedState()
        state.completedInitialMerge = true
        return state
    }

    private func makeStore() throws -> UserLearningStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        temporaryDirectories.append(root)
        return try UserLearningStore(
            location: UserDataLocation(applicationSupportRootURL: root)
        )
    }
}

private enum ProbeError: Error {
    case failed
}

private final class ProbeCloudTransport: CloudUserDataTransporting {
    private let lock = NSLock()
    private let records: [CloudUserDataRecord]
    private let fetchError: Error?
    private let saveError: Error?
    private var savedStorage: [CloudUserDataRecord] = []
    private var fetchCountStorage = 0

    init(
        records: [CloudUserDataRecord] = [],
        fetchError: Error? = nil,
        saveError: Error? = nil
    ) {
        self.records = records
        self.fetchError = fetchError
        self.saveError = saveError
    }

    var savedRecords: [CloudUserDataRecord] {
        lock.lock()
        defer { lock.unlock() }
        return savedStorage
    }

    var fetchCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return fetchCountStorage
    }

    func fetchAll(
        completion: @escaping (Result<[CloudUserDataRecord], Error>) -> Void
    ) {
        lock.lock()
        fetchCountStorage += 1
        lock.unlock()
        if let fetchError {
            completion(.failure(fetchError))
        } else {
            completion(.success(records))
        }
    }

    func save(
        _ records: [CloudUserDataRecord],
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        lock.lock()
        savedStorage.append(contentsOf: records)
        lock.unlock()
        if let saveError {
            completion(.failure(saveError))
        } else {
            completion(.success(()))
        }
    }
}
