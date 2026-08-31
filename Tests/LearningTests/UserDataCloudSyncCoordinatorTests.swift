import CloudKit
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

    func testManualSynchronizationUsesUserInitiatedUrgency() throws {
        let store = try makeStore()
        let transport = ProbeCloudTransport()
        let coordinator = makeCoordinator(store: store, transport: transport)

        waitForSync(coordinator)

        XCTAssertEqual(transport.fetchUrgencies, [.userInitiated])
        XCTAssertEqual(transport.saveUrgencies, [.userInitiated])
    }

    func testAutomaticSynchronizationUsesAutomaticUrgency() throws {
        let store = try makeStore()
        let preference = LockedBoolean(true)
        let fetchStarted = expectation(description: "automatic fetch started")
        let transport = ProbeCloudTransport(
            defersFetch: true,
            onFetch: { fetchStarted.fulfill() }
        )
        let coordinator = UserDataCloudSyncCoordinator(
            store: store,
            transport: transport,
            stateStore: MemoryCloudSyncStateStore(),
            isEnabled: { preference.value },
            debounceInterval: 0,
            retryInterval: 60
        )

        coordinator.start()
        wait(for: [fetchStarted], timeout: 2)

        XCTAssertEqual(transport.fetchUrgencies, [.automatic])

        preference.value = false
        coordinator.preferenceDidChange()
        drainDisabledCoordinator(coordinator)
        XCTAssertTrue(transport.fetchWasCancelled)
    }

    func testManualSynchronizationPreemptsAutomaticFetch() throws {
        let store = try makeStore()
        let preference = LockedBoolean(true)
        let firstFetchStarted = expectation(
            description: "automatic fetch started"
        )
        let secondFetchStarted = expectation(
            description: "manual fetch started"
        )
        let fetchCountLock = NSLock()
        var fetchCount = 0
        let transport = ProbeCloudTransport(
            defersFetch: true,
            onFetch: {
                fetchCountLock.lock()
                fetchCount += 1
                let currentCount = fetchCount
                fetchCountLock.unlock()
                if currentCount == 1 {
                    firstFetchStarted.fulfill()
                } else if currentCount == 2 {
                    secondFetchStarted.fulfill()
                }
            }
        )
        let coordinator = UserDataCloudSyncCoordinator(
            store: store,
            transport: transport,
            stateStore: MemoryCloudSyncStateStore(),
            isEnabled: { preference.value },
            debounceInterval: 0,
            retryInterval: 60
        )
        let stopped = expectation(description: "manual sync stopped")

        coordinator.start()
        wait(for: [firstFetchStarted], timeout: 2)
        coordinator.synchronizeNow {
            stopped.fulfill()
        }
        wait(for: [secondFetchStarted], timeout: 2)

        XCTAssertEqual(
            transport.fetchUrgencies,
            [.automatic, .userInitiated]
        )
        XCTAssertEqual(transport.fetchCancellationStates, [true, false])

        preference.value = false
        coordinator.preferenceDidChange()
        wait(for: [stopped], timeout: 2)
        XCTAssertEqual(transport.fetchCancellationStates, [true, true])
    }

    func testManualSynchronizationTimesOutAndRetriesOnlyOnce() throws {
        let store = try makeStore()
        let transport = ProbeCloudTransport(defersFetch: true)
        let coordinator = UserDataCloudSyncCoordinator(
            store: store,
            transport: transport,
            stateStore: MemoryCloudSyncStateStore(),
            isEnabled: { true },
            debounceInterval: 0,
            retryInterval: 60,
            fetchTimeoutInterval: 0.02,
            saveTimeoutInterval: 0.02,
            userInitiatedRetryInterval: 0
        )
        let completed = expectation(description: "timed out sync completed")

        coordinator.synchronizeNow {
            completed.fulfill()
        }
        wait(for: [completed], timeout: 2)

        XCTAssertEqual(transport.fetchCount, 2)
        XCTAssertEqual(
            transport.fetchUrgencies,
            [.userInitiated, .userInitiated]
        )
        XCTAssertEqual(transport.fetchCancellationStates, [true, true])
        guard case let .unavailable(message) = coordinator.status else {
            return XCTFail("Expected unavailable status")
        }
        XCTAssertTrue(message.contains("連線逾時"))
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

    func testDisablingDuringFetchCancelsTransferAndIgnoresLateResult() throws {
        let store = try makeStore()
        let preference = LockedBoolean(true)
        let fetchStarted = expectation(description: "fetch started")
        let transport = ProbeCloudTransport(
            records: [try cloudCharacter(count: 4, pinned: false)],
            defersFetch: true,
            onFetch: { fetchStarted.fulfill() }
        )
        let coordinator = UserDataCloudSyncCoordinator(
            store: store,
            transport: transport,
            stateStore: MemoryCloudSyncStateStore(),
            isEnabled: { preference.value },
            debounceInterval: 0,
            retryInterval: 60
        )
        let stopped = expectation(description: "sync stopped")

        coordinator.synchronizeNow {
            stopped.fulfill()
        }
        wait(for: [fetchStarted], timeout: 2)
        preference.value = false
        coordinator.preferenceDidChange()
        wait(for: [stopped], timeout: 2)

        XCTAssertTrue(transport.fetchWasCancelled)
        XCTAssertEqual(coordinator.status, .disabled)

        transport.completeDeferredFetch()
        drainDisabledCoordinator(coordinator)
        XCTAssertTrue(try store.allCharacterRecords().isEmpty)
        XCTAssertEqual(transport.saveCount, 0)
    }

    func testDisablingDuringSaveKeepsMutationPending() throws {
        let store = try makeStore()
        try store.recordSelection(character: "鍵", pronunciation: "ㄐㄧㄢˋ")
        let identity = try CloudUserDataIdentity(
            character: "鍵",
            pronunciation: "ㄐㄧㄢˋ"
        )
        var state = completedState()
        state.note(.upsert, identity: identity)
        let stateStore = MemoryCloudSyncStateStore(state: state)
        let preference = LockedBoolean(true)
        let saveStarted = expectation(description: "save started")
        let transport = ProbeCloudTransport(
            defersSave: true,
            onSave: { saveStarted.fulfill() }
        )
        let coordinator = UserDataCloudSyncCoordinator(
            store: store,
            transport: transport,
            stateStore: stateStore,
            isEnabled: { preference.value },
            debounceInterval: 0,
            retryInterval: 60
        )
        let stopped = expectation(description: "sync stopped")

        coordinator.synchronizeNow {
            stopped.fulfill()
        }
        wait(for: [saveStarted], timeout: 2)
        preference.value = false
        coordinator.preferenceDidChange()
        wait(for: [stopped], timeout: 2)

        XCTAssertTrue(transport.saveWasCancelled)
        XCTAssertEqual(stateStore.load().pending.count, 1)

        transport.completeDeferredSave()
        drainDisabledCoordinator(coordinator)
        XCTAssertEqual(stateStore.load().pending.count, 1)
    }

    func testUpgradeStateSurvivesAccountNotificationBeforeFirstCheck() throws {
        let store = try makeStore()
        let notificationCenter = NotificationCenter()
        let preference = LockedBoolean(true)
        let firstFetchStarted = expectation(description: "first fetch started")
        let secondFetchStarted = expectation(description: "second fetch started")
        let synchronized = expectation(description: "upgrade state synchronized")
        let account = CloudAccountIdentifier(stableIdentifier: "account-a")
        var oldState = CloudSyncPersistedState()
        oldState.completedInitialMerge = true
        let stateStore = MemoryCloudSyncStateStore(state: oldState)
        var transport: ProbeCloudTransport!
        transport = ProbeCloudTransport(
            accountIdentifier: account,
            defersFetch: true,
            onFetch: {
                if transport.fetchCount == 1 {
                    firstFetchStarted.fulfill()
                } else if transport.fetchCount == 2 {
                    secondFetchStarted.fulfill()
                }
            }
        )
        let coordinator = UserDataCloudSyncCoordinator(
            store: store,
            transport: transport,
            stateStore: stateStore,
            isEnabled: { preference.value },
            turnOffSyncAfterAccountChange: {
                preference.value = false
            },
            notificationCenter: notificationCenter,
            debounceInterval: 0,
            retryInterval: 60
        )
        let statusObserver = notificationCenter.addObserver(
            forName: UserDataCloudSyncCoordinator
                .statusDidChangeNotification,
            object: coordinator,
            queue: nil
        ) { _ in
            if case .idle = coordinator.status {
                synchronized.fulfill()
            }
        }
        defer { notificationCenter.removeObserver(statusObserver) }

        coordinator.start()
        wait(for: [firstFetchStarted], timeout: 2)
        notificationCenter.post(name: .CKAccountChanged, object: nil)
        wait(for: [secondFetchStarted], timeout: 2)
        transport.completeDeferredFetch()
        wait(for: [synchronized], timeout: 2)

        XCTAssertTrue(preference.value)
        XCTAssertEqual(stateStore.load().accountIdentifier, account)
        XCTAssertEqual(transport.fetchCancellationStates, [true, false])
    }

    func testAccountNotificationKeepsSyncEnabledForSameAccount() throws {
        let store = try makeStore()
        let notificationCenter = NotificationCenter()
        let preference = LockedBoolean(true)
        let firstFetchStarted = expectation(description: "first fetch started")
        let secondFetchStarted = expectation(description: "second fetch started")
        let synchronized = expectation(description: "same account synchronized")
        let account = CloudAccountIdentifier(stableIdentifier: "account-a")
        var state = CloudSyncPersistedState()
        state.accountIdentifier = account
        let stateStore = MemoryCloudSyncStateStore(state: state)
        var transport: ProbeCloudTransport!
        transport = ProbeCloudTransport(
            accountIdentifier: account,
            defersFetch: true,
            onFetch: {
                if transport.fetchCount == 1 {
                    firstFetchStarted.fulfill()
                } else if transport.fetchCount == 2 {
                    secondFetchStarted.fulfill()
                }
            }
        )
        let coordinator = UserDataCloudSyncCoordinator(
            store: store,
            transport: transport,
            stateStore: stateStore,
            isEnabled: { preference.value },
            turnOffSyncAfterAccountChange: {
                preference.value = false
            },
            notificationCenter: notificationCenter,
            debounceInterval: 0,
            retryInterval: 60
        )
        let statusObserver = notificationCenter.addObserver(
            forName: UserDataCloudSyncCoordinator
                .statusDidChangeNotification,
            object: coordinator,
            queue: nil
        ) { _ in
            if case .idle = coordinator.status {
                synchronized.fulfill()
            }
        }
        defer { notificationCenter.removeObserver(statusObserver) }

        coordinator.start()
        wait(for: [firstFetchStarted], timeout: 2)
        notificationCenter.post(name: .CKAccountChanged, object: nil)
        wait(for: [secondFetchStarted], timeout: 2)
        transport.completeDeferredFetch()
        wait(for: [synchronized], timeout: 2)

        XCTAssertTrue(preference.value)
        XCTAssertEqual(stateStore.load().accountIdentifier, account)
        XCTAssertEqual(transport.fetchCancellationStates, [true, false])
    }

    func testRealAppleAccountChangeTurnsOffSyncAndRequiresFreshConsent() throws {
        let store = try makeStore()
        let notificationCenter = NotificationCenter()
        let preference = LockedBoolean(true)
        let firstFetchStarted = expectation(description: "first fetch started")
        let secondFetchStarted = expectation(description: "second fetch started")
        let settingTurnedOff = expectation(description: "setting turned off")
        let firstAccount = CloudAccountIdentifier(
            stableIdentifier: "account-a"
        )
        let secondAccount = CloudAccountIdentifier(
            stableIdentifier: "account-b"
        )
        var state = CloudSyncPersistedState()
        state.accountIdentifier = firstAccount
        let stateStore = MemoryCloudSyncStateStore(state: state)
        var transport: ProbeCloudTransport!
        transport = ProbeCloudTransport(
            accountIdentifier: firstAccount,
            defersFetch: true,
            onFetch: {
                if transport.fetchCount == 1 {
                    firstFetchStarted.fulfill()
                } else if transport.fetchCount == 2 {
                    secondFetchStarted.fulfill()
                }
            }
        )
        let coordinator = UserDataCloudSyncCoordinator(
            store: store,
            transport: transport,
            stateStore: stateStore,
            isEnabled: { preference.value },
            turnOffSyncAfterAccountChange: {
                preference.value = false
                settingTurnedOff.fulfill()
            },
            notificationCenter: notificationCenter,
            debounceInterval: 0,
            retryInterval: 60
        )

        coordinator.start()
        wait(for: [firstFetchStarted], timeout: 2)
        transport.setAccountIdentifier(secondAccount)
        notificationCenter.post(name: .CKAccountChanged, object: nil)
        wait(for: [secondFetchStarted], timeout: 2)
        transport.completeDeferredFetch()
        wait(for: [settingTurnedOff], timeout: 2)
        drainDisabledCoordinator(coordinator)

        XCTAssertFalse(preference.value)
        XCTAssertEqual(transport.fetchCancellationStates, [true, false])
        XCTAssertEqual(coordinator.status, .disabled)
        XCTAssertNil(stateStore.load().accountIdentifier)
        XCTAssertEqual(transport.saveCount, 0)
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
            retryInterval: 60,
            userInitiatedRetryInterval: 0
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

    private func drainDisabledCoordinator(
        _ coordinator: UserDataCloudSyncCoordinator
    ) {
        let drained = expectation(description: "coordinator queue drained")
        coordinator.synchronizeNow {
            drained.fulfill()
        }
        wait(for: [drained], timeout: 2)
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
    private let defersFetch: Bool
    private let defersSave: Bool
    private let onFetch: (() -> Void)?
    private let onSave: (() -> Void)?
    private var savedStorage: [CloudUserDataRecord] = []
    private var accountIdentifierStorage: CloudAccountIdentifier
    private var fetchCountStorage = 0
    private var saveCountStorage = 0
    private var fetchUrgenciesStorage: [CloudUserDataSyncUrgency] = []
    private var saveUrgenciesStorage: [CloudUserDataSyncUrgency] = []
    private var fetchTransfersStorage: [ProbeCloudTransfer] = []
    private var fetchTransferStorage: ProbeCloudTransfer?
    private var saveTransferStorage: ProbeCloudTransfer?
    private var deferredFetchCompletion: (
        (Result<CloudUserDataSnapshot, Error>) -> Void
    )?
    private var deferredSaveCompletion: ((Result<Void, Error>) -> Void)?

    init(
        records: [CloudUserDataRecord] = [],
        accountIdentifier: CloudAccountIdentifier = CloudAccountIdentifier(
            stableIdentifier: "probe-account"
        ),
        fetchError: Error? = nil,
        saveError: Error? = nil,
        defersFetch: Bool = false,
        defersSave: Bool = false,
        onFetch: (() -> Void)? = nil,
        onSave: (() -> Void)? = nil
    ) {
        self.records = records
        accountIdentifierStorage = accountIdentifier
        self.fetchError = fetchError
        self.saveError = saveError
        self.defersFetch = defersFetch
        self.defersSave = defersSave
        self.onFetch = onFetch
        self.onSave = onSave
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

    var saveCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return saveCountStorage
    }

    var fetchUrgencies: [CloudUserDataSyncUrgency] {
        lock.lock()
        defer { lock.unlock() }
        return fetchUrgenciesStorage
    }

    var saveUrgencies: [CloudUserDataSyncUrgency] {
        lock.lock()
        defer { lock.unlock() }
        return saveUrgenciesStorage
    }

    var fetchCancellationStates: [Bool] {
        lock.lock()
        let transfers = fetchTransfersStorage
        lock.unlock()
        return transfers.map(\.isCancelled)
    }

    var fetchWasCancelled: Bool {
        lock.lock()
        let transfer = fetchTransferStorage
        lock.unlock()
        return transfer?.isCancelled ?? false
    }

    var saveWasCancelled: Bool {
        lock.lock()
        let transfer = saveTransferStorage
        lock.unlock()
        return transfer?.isCancelled ?? false
    }

    func fetchAll(
        urgency: CloudUserDataSyncUrgency,
        completion: @escaping (Result<CloudUserDataSnapshot, Error>) -> Void
    ) -> CloudUserDataTransfer {
        let transfer = ProbeCloudTransfer()
        lock.lock()
        fetchCountStorage += 1
        fetchUrgenciesStorage.append(urgency)
        fetchTransfersStorage.append(transfer)
        fetchTransferStorage = transfer
        if defersFetch {
            deferredFetchCompletion = completion
        }
        lock.unlock()
        onFetch?()
        guard !defersFetch else {
            return transfer
        }
        if let fetchError {
            completion(.failure(fetchError))
        } else {
            lock.lock()
            let accountIdentifier = accountIdentifierStorage
            lock.unlock()
            completion(.success(CloudUserDataSnapshot(
                accountIdentifier: accountIdentifier,
                records: records
            )))
        }
        return transfer
    }

    func save(
        _ records: [CloudUserDataRecord],
        urgency: CloudUserDataSyncUrgency,
        completion: @escaping (Result<Void, Error>) -> Void
    ) -> CloudUserDataTransfer {
        let transfer = ProbeCloudTransfer()
        lock.lock()
        saveCountStorage += 1
        saveUrgenciesStorage.append(urgency)
        savedStorage.append(contentsOf: records)
        saveTransferStorage = transfer
        if defersSave {
            deferredSaveCompletion = completion
        }
        lock.unlock()
        onSave?()
        guard !defersSave else {
            return transfer
        }
        if let saveError {
            completion(.failure(saveError))
        } else {
            completion(.success(()))
        }
        return transfer
    }

    func completeDeferredFetch() {
        lock.lock()
        let completion = deferredFetchCompletion
        deferredFetchCompletion = nil
        let accountIdentifier = accountIdentifierStorage
        lock.unlock()
        if let fetchError {
            completion?(.failure(fetchError))
        } else {
            completion?(.success(CloudUserDataSnapshot(
                accountIdentifier: accountIdentifier,
                records: records
            )))
        }
    }

    func setAccountIdentifier(_ accountIdentifier: CloudAccountIdentifier) {
        lock.lock()
        accountIdentifierStorage = accountIdentifier
        lock.unlock()
    }

    func completeDeferredSave() {
        lock.lock()
        let completion = deferredSaveCompletion
        deferredSaveCompletion = nil
        lock.unlock()
        if let saveError {
            completion?(.failure(saveError))
        } else {
            completion?(.success(()))
        }
    }
}

private final class ProbeCloudTransfer: CloudUserDataTransfer {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

private final class LockedBoolean {
    private let lock = NSLock()
    private var storage: Bool

    init(_ value: Bool) {
        storage = value
    }

    var value: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }
}
