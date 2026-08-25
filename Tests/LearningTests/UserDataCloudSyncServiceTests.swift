import Foundation
import XCTest

final class UserDataCloudSyncServiceTests: XCTestCase {
    func testFirstSyncMergesRemoteArchiveIntoLocalStoreAndUploadsResult() throws {
        let store = try makeStore()
        try store.recordSelection(
            character: "鍵",
            pronunciation: "ㄐㄧㄢˋ",
            at: Date(timeIntervalSince1970: 1)
        )
        let learning = UserLearningService(store: store)
        let remote = UserDataArchive(
            exportedAt: 2_000,
            characters: [
                ArchivedCharacter(
                    character: "鍵",
                    pronunciation: "ㄐㄧㄢˋ",
                    selectionCount: 9,
                    lastSelectedAt: 1_500,
                    pinned: true
                ),
            ],
            phrases: []
        )
        let transport = FakeCloudUserDataTransport(remoteArchive: remote)
        let service = makeService(learning: learning, transport: transport)
        let finished = expectation(description: "sync finished")

        service.synchronizeNow { state in
            guard case .idle = state else {
                XCTFail("unexpected state: \(state)")
                finished.fulfill()
                return
            }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 2)

        let record = try XCTUnwrap(
            learning.records(for: "ㄐㄧㄢˋ")["鍵"]
        )
        XCTAssertEqual(record.selectionCount, 9)
        XCTAssertTrue(record.pinned)
        XCTAssertEqual(transport.saveCount, 1)
        XCTAssertEqual(
            transport.remoteArchive?.characters.first?.selectionCount,
            9
        )
    }

    func testDisabledPreferenceSkipsCloudAccess() throws {
        let learning = UserLearningService(store: try makeStore())
        let transport = FakeCloudUserDataTransport(remoteArchive: nil)
        let service = makeService(
            learning: learning,
            transport: transport,
            enabled: false
        )
        let finished = expectation(description: "disabled request finished")

        service.synchronizeNow { state in
            XCTAssertEqual(state, .disabled)
            finished.fulfill()
        }
        wait(for: [finished], timeout: 2)

        XCTAssertEqual(transport.accountRequestCount, 0)
        XCTAssertEqual(transport.fetchCount, 0)
        XCTAssertEqual(transport.saveCount, 0)
    }

    func testDisablingSyncCancelsFetchAndBlocksLateUpload() throws {
        let learning = UserLearningService(store: try makeStore())
        let transport = FakeCloudUserDataTransport(remoteArchive: nil)
        transport.defersFetch = true
        let harness = makeHarness(learning: learning, transport: transport)
        let fetchStarted = expectation(description: "fetch started")
        let requestFinished = expectation(description: "request disabled")
        transport.onFetch = { fetchStarted.fulfill() }

        harness.service.synchronizeNow { state in
            XCTAssertEqual(state, .disabled)
            requestFinished.fulfill()
        }
        wait(for: [fetchStarted], timeout: 2)

        harness.preferences.update { $0.cloudSyncEnabled = false }
        wait(for: [requestFinished], timeout: 2)

        XCTAssertTrue(transport.lastFetchOperation?.isCancelled == true)
        transport.completeDeferredFetch(.success(nil))
        let callbacksSettled = expectation(description: "late fetch ignored")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            callbacksSettled.fulfill()
        }
        wait(for: [callbacksSettled], timeout: 1)
        XCTAssertEqual(transport.saveCount, 0)
    }

    func testAccountChangeDisablesSyncAndRequiresFreshConsent() throws {
        let center = NotificationCenter()
        let learning = UserLearningService(
            store: try makeStore(),
            notificationCenter: center
        )
        let transport = FakeCloudUserDataTransport(remoteArchive: nil)
        transport.defersFetch = true
        let harness = makeHarness(
            learning: learning,
            transport: transport,
            notificationCenter: center
        )
        let fetchStarted = expectation(description: "initial fetch started")
        let disabled = expectation(description: "sync disabled")
        transport.onFetch = { fetchStarted.fulfill() }
        let token = center.addObserver(
            forName: UserDataCloudSyncService.didChangeNotification,
            object: harness.service,
            queue: .main
        ) { _ in
            if harness.service.state == .disabled {
                disabled.fulfill()
            }
        }
        defer { center.removeObserver(token) }

        harness.service.start()
        wait(for: [fetchStarted], timeout: 2)
        center.post(name: .CKAccountChanged, object: nil)
        wait(for: [disabled], timeout: 2)

        XCTAssertFalse(harness.preferences.current.cloudSyncEnabled)
        XCTAssertTrue(transport.lastFetchOperation?.isCancelled == true)
        transport.completeDeferredFetch(.success(nil))
        XCTAssertEqual(transport.saveCount, 0)
    }

    func testDisablingSyncCancelsAnUploadAlreadyInProgress() throws {
        let learning = UserLearningService(store: try makeStore())
        let transport = FakeCloudUserDataTransport(remoteArchive: nil)
        transport.defersSave = true
        let harness = makeHarness(learning: learning, transport: transport)
        let saveStarted = expectation(description: "save started")
        let requestFinished = expectation(description: "request disabled")
        transport.onSave = { saveStarted.fulfill() }

        harness.service.synchronizeNow { state in
            XCTAssertEqual(state, .disabled)
            requestFinished.fulfill()
        }
        wait(for: [saveStarted], timeout: 2)

        harness.preferences.update { $0.cloudSyncEnabled = false }
        wait(for: [requestFinished], timeout: 2)

        XCTAssertTrue(transport.lastSaveOperation?.isCancelled == true)
    }

    func testConflictRefetchesAndRetriesWithoutDoubleCounting() throws {
        let store = try makeStore()
        try store.recordSelection(
            character: "雲",
            pronunciation: "ㄩㄣˊ",
            at: Date(timeIntervalSince1970: 1)
        )
        let learning = UserLearningService(store: store)
        let remote = UserDataArchive(
            exportedAt: 2_000,
            characters: [
                ArchivedCharacter(
                    character: "雲",
                    pronunciation: "ㄩㄣˊ",
                    selectionCount: 4,
                    lastSelectedAt: 1_500,
                    pinned: false
                ),
            ],
            phrases: []
        )
        let transport = FakeCloudUserDataTransport(remoteArchive: remote)
        transport.saveResults = [
            .failure(CloudUserDataTransportError.conflict),
            .success(()),
        ]
        let service = makeService(learning: learning, transport: transport)
        let finished = expectation(description: "retry finished")

        service.synchronizeNow { state in
            guard case .idle = state else {
                XCTFail("unexpected state: \(state)")
                finished.fulfill()
                return
            }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 2)

        XCTAssertEqual(transport.fetchCount, 2)
        XCTAssertEqual(transport.saveCount, 2)
        XCTAssertEqual(
            learning.records(for: "ㄩㄣˊ")["雲"]?.selectionCount,
            4
        )
    }

    func testDeletionAnnouncesReplacementMutation() throws {
        let center = NotificationCenter()
        let store = try makeStore()
        try store.recordSelection(
            character: "刪",
            pronunciation: "ㄕㄢ",
            at: Date()
        )
        let learning = UserLearningService(
            store: store,
            notificationCenter: center
        )
        let received = expectation(description: "mutation received")
        var mutation: UserLearningMutation?
        let token = center.addObserver(
            forName: UserLearningService.didChangeNotification,
            object: learning,
            queue: nil
        ) { notification in
            mutation = UserLearningMutation(notification: notification)
            received.fulfill()
        }
        defer { center.removeObserver(token) }

        XCTAssertTrue(
            learning.deleteCharacterRecord(
                character: "刪",
                pronunciation: "ㄕㄢ"
            )
        )
        wait(for: [received], timeout: 1)

        XCTAssertEqual(mutation, .replacement)
    }

    private func makeService(
        learning: UserLearningService,
        transport: FakeCloudUserDataTransport,
        enabled: Bool = true
    ) -> UserDataCloudSyncService {
        makeHarness(
            learning: learning,
            transport: transport,
            enabled: enabled
        ).service
    }

    private func makeHarness(
        learning: UserLearningService,
        transport: FakeCloudUserDataTransport,
        enabled: Bool = true,
        notificationCenter: NotificationCenter = NotificationCenter()
    ) -> (
        service: UserDataCloudSyncService,
        preferences: PreferencesController
    ) {
        let preferences = PreferencesController(
            store: CloudSyncPreferencesStore(
                preferences: Preferences(cloudSyncEnabled: enabled)
            ),
            notificationCenter: notificationCenter
        )
        let service = UserDataCloudSyncService(
            preferences: preferences,
            learning: learning,
            transport: transport,
            notificationCenter: notificationCenter,
            now: { Date(timeIntervalSince1970: 123) },
            debounceInterval: 0,
            queueLabel: "test.cloud-sync.\(UUID().uuidString)"
        )
        return (service, preferences)
    }

    private func makeStore() throws -> UserLearningStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "JiukongCloudSyncTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return try UserLearningStore(
            databaseURL: directory.appendingPathComponent("User.sqlite3")
        )
    }
}

private final class CloudSyncPreferencesStore: PreferencesStoring {
    private var preferences: Preferences

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    func load() -> Preferences {
        preferences
    }

    func save(_ preferences: Preferences) {
        self.preferences = preferences
    }
}

private final class FakeCloudUserDataTransport: CloudUserDataTransport {
    var remoteArchive: UserDataArchive?
    var availability: CloudAccountAvailability = .available
    var saveResults: [Result<Void, Error>] = []
    var defersFetch = false
    var defersSave = false
    var onFetch: (() -> Void)?
    var onSave: (() -> Void)?

    private(set) var accountRequestCount = 0
    private(set) var fetchCount = 0
    private(set) var saveCount = 0
    private(set) var lastFetchOperation: FakeCloudUserDataOperation?
    private(set) var lastSaveOperation: FakeCloudUserDataOperation?
    private var deferredFetchCompletion: (
        (Result<UserDataArchive?, Error>) -> Void
    )?

    init(remoteArchive: UserDataArchive?) {
        self.remoteArchive = remoteArchive
    }

    func accountAvailability(
        completion: @escaping (Result<CloudAccountAvailability, Error>) -> Void
    ) {
        accountRequestCount += 1
        completion(.success(availability))
    }

    @discardableResult
    func fetchArchive(
        completion: @escaping (Result<UserDataArchive?, Error>) -> Void
    ) -> (any CloudUserDataOperation)? {
        fetchCount += 1
        let operation = FakeCloudUserDataOperation()
        lastFetchOperation = operation
        onFetch?()
        if defersFetch {
            deferredFetchCompletion = completion
            return operation
        }
        completion(.success(remoteArchive))
        return operation
    }

    @discardableResult
    func saveArchive(
        _ archive: UserDataArchive,
        completion: @escaping (Result<Void, Error>) -> Void
    ) -> (any CloudUserDataOperation)? {
        saveCount += 1
        let operation = FakeCloudUserDataOperation()
        lastSaveOperation = operation
        onSave?()
        if defersSave {
            return operation
        }
        let result = saveResults.isEmpty
            ? Result<Void, Error>.success(())
            : saveResults.removeFirst()
        if case .success = result {
            remoteArchive = archive
        }
        completion(result)
        return operation
    }

    func completeDeferredFetch(
        _ result: Result<UserDataArchive?, Error>
    ) {
        let completion = deferredFetchCompletion
        deferredFetchCompletion = nil
        completion?(result)
    }
}

private final class FakeCloudUserDataOperation: CloudUserDataOperation {
    private(set) var isCancelled = false

    func cancel() {
        isCancelled = true
    }
}
