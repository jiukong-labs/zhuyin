import Foundation
import XCTest

final class CloudPreferencesSyncCoordinatorTests: XCTestCase {
    func testLocalPreferenceChangeCreatesCloudUpdate() {
        let context = makeContext()
        synchronize(context.coordinator)
        context.transport.savedBatches.removeAll()

        context.preferences.update {
            $0.cursorIndicator.appearance.chineseText = "漢"
        }
        synchronize(context.coordinator)

        XCTAssertEqual(context.transport.savedBatches.count, 1)
        XCTAssertEqual(
            context.transport.savedBatches[0].map(\.field),
            [.chineseText]
        )
        XCTAssertEqual(context.transport.savedBatches[0][0].value, "漢")
    }

    func testIncomingCloudPreferenceUpdatesLocalPreferences() {
        let remote = record(
            .compositionColor,
            "#663399",
            modifiedAt: 200,
            revision: 4
        )
        let context = makeContext(remote: [remote])

        synchronize(context.coordinator)

        XCTAssertEqual(
            context.preferences.current.cursorIndicator.appearance
                .compositionIndicatorColorHex,
            "#663399"
        )
    }

    func testMalformedCloudValueDoesNotDestroyValidLocalSetting() {
        let local = Preferences(
            cursorIndicator: CursorIndicatorPreferences(
                appearance: CursorIndicatorAppearance(
                    compositionIndicatorColorHex: "#112233"
                )
            )
        )
        let malformed = CloudPreferenceRecord(
            field: .compositionColor,
            value: "not-a-color",
            modifiedAt: Date(timeIntervalSince1970: 500),
            revision: 9
        )
        let context = makeContext(local: local, remote: [malformed])

        synchronize(context.coordinator)

        XCTAssertEqual(
            context.preferences.current.cursorIndicator.appearance
                .compositionIndicatorColorHex,
            "#112233"
        )
    }

    func testNewerRemoteRecordWinsOverPendingLocalChange() {
        let account = CloudAccountIdentifier(stableIdentifier: "account")
        var state = CloudPreferencesPersistedState()
        state.accountIdentifier = account
        state.lastValues = values(from: .default)
        let pending = state.makePending(
            field: .compositionColor,
            value: "#112233",
            modifiedAt: Date(timeIntervalSince1970: 200)
        )
        state.metadata[CloudPreferenceField.compositionColor.rawValue] =
            CloudPreferenceMetadata(pending)
        let newer = record(
            .compositionColor,
            "#663399",
            modifiedAt: 300,
            revision: pending.revision + 1
        )
        let stateStore = MemoryCloudPreferencesStateStore(state: state)
        let local = Preferences(
            cursorIndicator: CursorIndicatorPreferences(
                appearance: CursorIndicatorAppearance(
                    compositionIndicatorColorHex: "#112233"
                )
            )
        )
        let context = makeContext(
            local: local,
            remote: [newer],
            stateStore: stateStore,
            account: account
        )

        synchronize(context.coordinator)

        XCTAssertEqual(
            context.preferences.current.cursorIndicator.appearance
                .compositionIndicatorColorHex,
            "#663399"
        )
        XCTAssertNil(
            stateStore.load().pending[
                CloudPreferenceField.compositionColor.rawValue
            ]
        )
    }

    func testOfflineFailureKeepsPendingLocalSettings() {
        let stateStore = MemoryCloudPreferencesStateStore()
        let context = makeContext(stateStore: stateStore)
        synchronize(context.coordinator)

        context.preferences.update {
            $0.cursorIndicator.showsCompositionIndicator = false
        }
        context.transport.fetchError = ProbeError.offline
        synchronize(context.coordinator)

        XCTAssertNotNil(
            stateStore.load().pending[
                CloudPreferenceField.showsCompositionIndicator.rawValue
            ]
        )
        XCTAssertFalse(
            context.preferences.current.cursorIndicator
                .showsCompositionIndicator
        )
    }

    func testAccountChangeDisablesSyncWithoutChangingLocalAppearance() {
        let oldAccount = CloudAccountIdentifier(stableIdentifier: "old")
        var state = CloudPreferencesPersistedState()
        state.accountIdentifier = oldAccount
        state.lastValues = values(from: .default)
        let local = Preferences(
            cursorIndicator: CursorIndicatorPreferences(
                appearance: CursorIndicatorAppearance(chineseText: "漢")
            )
        )
        let context = makeContext(
            local: local,
            stateStore: MemoryCloudPreferencesStateStore(state: state),
            account: CloudAccountIdentifier(stableIdentifier: "new")
        )

        synchronize(context.coordinator)

        XCTAssertFalse(context.preferences.current.iCloudSyncEnabled)
        XCTAssertEqual(
            context.preferences.current.cursorIndicator.appearance.chineseText,
            "漢"
        )
    }

    func testUnsupportedCloudSchemaIsIgnored() {
        let unsupported = CloudPreferenceRecord(
            field: .chineseText,
            value: "新版欄位",
            modifiedAt: Date(timeIntervalSince1970: 100),
            revision: 1,
            schemaVersion: CloudPreferenceRecord.currentSchemaVersion + 1
        )
        let context = makeContext(remote: [unsupported])

        synchronize(context.coordinator)

        XCTAssertNil(
            context.preferences.current.cursorIndicator.appearance.chineseText
        )
    }

    private struct Context {
        let preferences: PreferencesController
        let transport: ProbeCloudPreferencesTransport
        let coordinator: CloudPreferencesSyncCoordinator
    }

    private func makeContext(
        local: Preferences = .default,
        remote: [CloudPreferenceRecord] = [],
        stateStore: CloudPreferencesStateStoring =
            MemoryCloudPreferencesStateStore(),
        account: CloudAccountIdentifier = CloudAccountIdentifier(
            stableIdentifier: "account"
        )
    ) -> Context {
        let center = NotificationCenter()
        let preferences = PreferencesController(
            store: TestPreferencesStore(local),
            notificationCenter: center
        )
        let transport = ProbeCloudPreferencesTransport(
            account: account,
            records: remote
        )
        let coordinator = CloudPreferencesSyncCoordinator(
            preferences: preferences,
            transport: transport,
            stateStore: stateStore,
            notificationCenter: center,
            now: { Date(timeIntervalSince1970: 1_000) },
            debounceInterval: 0,
            retryInterval: 60
        )
        return Context(
            preferences: preferences,
            transport: transport,
            coordinator: coordinator
        )
    }

    private func synchronize(_ coordinator: CloudPreferencesSyncCoordinator) {
        let completed = expectation(description: "preference sync completed")
        coordinator.synchronizeNow { completed.fulfill() }
        wait(for: [completed], timeout: 2)
    }

    private func record(
        _ field: CloudPreferenceField,
        _ value: String,
        modifiedAt: TimeInterval,
        revision: Int64
    ) -> CloudPreferenceRecord {
        CloudPreferenceRecord(
            field: field,
            value: value,
            modifiedAt: Date(timeIntervalSince1970: modifiedAt),
            revision: revision
        )
    }

    private func values(from preferences: Preferences) -> [String: String] {
        Dictionary(uniqueKeysWithValues: CloudPreferenceField.allCases.map {
            ($0.rawValue, $0.value(from: preferences))
        })
    }
}

private enum ProbeError: Error {
    case offline
}

private final class TestPreferencesStore: PreferencesStoring {
    private var value: Preferences

    init(_ value: Preferences) {
        self.value = value
    }

    func load() -> Preferences {
        value
    }

    func save(_ preferences: Preferences) {
        value = preferences
    }
}

private final class ProbeCloudPreferencesTransport:
    CloudPreferencesTransporting {
    let account: CloudAccountIdentifier
    var records: [CloudPreferenceRecord]
    var fetchError: Error?
    var saveError: Error?
    var savedBatches: [[CloudPreferenceRecord]] = []

    init(
        account: CloudAccountIdentifier,
        records: [CloudPreferenceRecord]
    ) {
        self.account = account
        self.records = records
    }

    func fetchAll(
        urgency: CloudUserDataSyncUrgency,
        completion: @escaping (Result<CloudPreferencesSnapshot, Error>) -> Void
    ) -> CloudUserDataTransfer {
        let transfer = ProbeCloudPreferencesTransfer()
        if let fetchError {
            completion(.failure(fetchError))
        } else {
            completion(.success(
                CloudPreferencesSnapshot(
                    accountIdentifier: account,
                    records: records
                )
            ))
        }
        return transfer
    }

    func save(
        _ records: [CloudPreferenceRecord],
        urgency: CloudUserDataSyncUrgency,
        completion: @escaping (Result<Void, Error>) -> Void
    ) -> CloudUserDataTransfer {
        let transfer = ProbeCloudPreferencesTransfer()
        savedBatches.append(records)
        if let saveError {
            completion(.failure(saveError))
        } else {
            for record in records {
                self.records.removeAll { $0.field == record.field }
                self.records.append(record)
            }
            completion(.success(()))
        }
        return transfer
    }
}

private final class ProbeCloudPreferencesTransfer: CloudUserDataTransfer {
    func cancel() {}
}
