import CloudKit
import Foundation
import os

/// Offline-first synchronization for the small cursor-appearance preference
/// set. `UserDefaults` remains authoritative for live UI; this coordinator
/// only exchanges independently versioned field records with iCloud.
final class CloudPreferencesSyncCoordinator {
    private static let logger = Logger(
        subsystem: "tw.idv.jiukong.inputmethod.zhuyin",
        category: "CloudPreferences"
    )

    private let preferences: PreferencesController
    private let transport: CloudPreferencesTransporting
    private let stateStore: CloudPreferencesStateStoring
    private let notificationCenter: NotificationCenter
    private let now: () -> Date
    private let queue: DispatchQueue
    private let debounceInterval: TimeInterval
    private let retryInterval: TimeInterval

    private var state: CloudPreferencesPersistedState
    private var started = false
    private var synchronizing = false
    private var synchronizeAgain = false
    private var activeTransfer: CloudUserDataTransfer?
    private var preferenceObserver: NSObjectProtocol?
    private var accountObserver: NSObjectProtocol?
    private var debounceWorkItem: DispatchWorkItem?
    private var retryWorkItem: DispatchWorkItem?
    private var completions: [() -> Void] = []

    init(
        preferences: PreferencesController,
        transport: CloudPreferencesTransporting,
        stateStore: CloudPreferencesStateStoring,
        notificationCenter: NotificationCenter = .default,
        now: @escaping () -> Date = Date.init,
        queueLabel: String = "tw.idv.jiukong.cloud-preferences",
        debounceInterval: TimeInterval = 1,
        retryInterval: TimeInterval = 300
    ) {
        self.preferences = preferences
        self.transport = transport
        self.stateStore = stateStore
        self.notificationCenter = notificationCenter
        self.now = now
        self.debounceInterval = debounceInterval
        self.retryInterval = retryInterval
        queue = DispatchQueue(label: queueLabel, qos: .utility)
        state = stateStore.load()
    }

    deinit {
        activeTransfer?.cancel()
        if let preferenceObserver {
            notificationCenter.removeObserver(preferenceObserver)
        }
        if let accountObserver {
            notificationCenter.removeObserver(accountObserver)
        }
    }

    func start() {
        guard !started else {
            return
        }
        started = true
        preferenceObserver = notificationCenter.addObserver(
            forName: PreferencesController.didChangeNotification,
            object: preferences,
            queue: nil
        ) { [weak self] notification in
            let origin = notification.userInfo?[
                PreferencesController.changeOriginUserInfoKey
            ] as? String
            guard origin != PreferencesController.ChangeOrigin.cloud.rawValue
            else {
                return
            }
            self?.queue.async {
                self?.localPreferencesDidChange()
            }
        }
        accountObserver = notificationCenter.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.queue.async {
                self?.requestSynchronization(urgency: .automatic)
            }
        }
        queue.async { [weak self] in
            guard let self else {
                return
            }
            initializeLocalSnapshot()
            requestSynchronization(urgency: .automatic)
        }
    }

    func synchronizeNow() {
        synchronizeNow(completion: nil)
    }

    func synchronizeNow(completion: (() -> Void)?) {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            if let completion {
                completions.append(completion)
            }
            debounceWorkItem?.cancel()
            debounceWorkItem = nil
            retryWorkItem?.cancel()
            retryWorkItem = nil
            initializeLocalSnapshot()
            requestSynchronization(urgency: .userInitiated)
        }
    }

    private var isEnabled: Bool {
        preferences.current.iCloudSyncEnabled
    }

    private func initializeLocalSnapshot() {
        let values = currentValues()
        if state.lastValues.isEmpty {
            state.lastValues = values
            persistState()
            return
        }
        captureChanges(from: values)
    }

    private func localPreferencesDidChange() {
        captureChanges(from: currentValues())
        guard isEnabled else {
            stopSynchronization()
            return
        }
        scheduleDebouncedSynchronization()
    }

    private func captureChanges(from values: [String: String]) {
        let timestamp = now()
        var changed = false
        for field in CloudPreferenceField.allCases {
            let key = field.rawValue
            guard let value = values[key], state.lastValues[key] != value else {
                continue
            }
            _ = state.makePending(
                field: field,
                value: value,
                modifiedAt: timestamp
            )
            changed = true
        }
        if changed {
            persistState()
        }
    }

    private func currentValues() -> [String: String] {
        let current = preferences.current
        return Dictionary(uniqueKeysWithValues: CloudPreferenceField.allCases.map {
            ($0.rawValue, $0.value(from: current))
        })
    }

    private func scheduleDebouncedSynchronization() {
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.requestSynchronization(urgency: .automatic)
        }
        debounceWorkItem = item
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: item)
    }

    private func requestSynchronization(
        urgency: CloudUserDataSyncUrgency
    ) {
        guard isEnabled else {
            stopSynchronization()
            finishCompletions()
            return
        }
        if synchronizing {
            synchronizeAgain = true
            return
        }

        synchronizing = true
        activeTransfer = transport.fetchAll(urgency: urgency) {
            [weak self] result in
            self?.queue.async {
                self?.handleFetch(result, urgency: urgency)
            }
        }
    }

    private func handleFetch(
        _ result: Result<CloudPreferencesSnapshot, Error>,
        urgency: CloudUserDataSyncUrgency
    ) {
        activeTransfer = nil
        guard isEnabled else {
            finishAttempt()
            return
        }
        switch result {
        case let .failure(error):
            fail(error)
        case let .success(snapshot):
            if let account = state.accountIdentifier,
               account != snapshot.accountIdentifier {
                handleAccountChange(snapshot.accountIdentifier)
                return
            }
            state.accountIdentifier = snapshot.accountIdentifier
            let uploads = reconcile(snapshot.records)
            persistState()
            activeTransfer = transport.save(uploads, urgency: urgency) {
                [weak self] result in
                self?.queue.async {
                    self?.handleSave(result, uploads: uploads)
                }
            }
        }
    }

    private func reconcile(
        _ fetchedRecords: [CloudPreferenceRecord]
    ) -> [CloudPreferenceRecord] {
        var remote: [CloudPreferenceField: CloudPreferenceRecord] = [:]
        for record in fetchedRecords where record.isValid {
            if let existing = remote[record.field],
               !record.isNewer(than: existing) {
                continue
            }
            remote[record.field] = record
        }

        var updatedPreferences = preferences.current
        var appliedRemote = false
        var uploads: [CloudPreferenceRecord] = []

        for field in CloudPreferenceField.allCases {
            let key = field.rawValue
            let localValue = field.value(from: updatedPreferences)
            let pending = state.pending[key]
            let cloud = remote[field]

            if let pending {
                if let cloud, cloud.isNewer(than: pending) {
                    if field.apply(cloud.value, to: &updatedPreferences) {
                        state.pending.removeValue(forKey: key)
                        state.metadata[key] = CloudPreferenceMetadata(cloud)
                        state.lastValues[key] = cloud.value
                        appliedRemote = true
                    }
                } else {
                    uploads.append(pending)
                }
                continue
            }

            if let cloud {
                if let metadata = state.metadata[key] {
                    let localRecord = metadata.record(
                        field: field,
                        value: localValue
                    )
                    if cloud.isNewer(than: localRecord) {
                        if field.apply(cloud.value, to: &updatedPreferences) {
                            state.metadata[key] = CloudPreferenceMetadata(cloud)
                            state.lastValues[key] = cloud.value
                            appliedRemote = true
                        }
                    } else if localRecord.isNewer(than: cloud) {
                        state.pending[key] = localRecord
                        uploads.append(localRecord)
                    }
                } else if field.apply(cloud.value, to: &updatedPreferences) {
                    state.metadata[key] = CloudPreferenceMetadata(cloud)
                    state.lastValues[key] = cloud.value
                    appliedRemote = true
                }
                continue
            }

            let created = state.makePending(
                field: field,
                value: localValue,
                modifiedAt: now()
            )
            uploads.append(created)
        }

        if appliedRemote {
            preferences.update(origin: .cloud) {
                $0.cursorIndicator = updatedPreferences.cursorIndicator
            }
        }
        let final = currentValues()
        for (key, value) in final {
            state.lastValues[key] = value
        }
        return uploads
    }

    private func handleSave(
        _ result: Result<Void, Error>,
        uploads: [CloudPreferenceRecord]
    ) {
        activeTransfer = nil
        switch result {
        case let .failure(error):
            fail(error)
        case .success:
            for upload in uploads
                where state.pending[upload.field.rawValue] == upload {
                state.pending.removeValue(forKey: upload.field.rawValue)
                state.metadata[upload.field.rawValue] =
                    CloudPreferenceMetadata(upload)
            }
            persistState()
            finishAttempt()
        }
    }

    private func handleAccountChange(_ account: CloudAccountIdentifier) {
        state = CloudPreferencesPersistedState()
        state.accountIdentifier = account
        state.lastValues = currentValues()
        persistState()
        preferences.update(origin: .cloud) {
            $0.iCloudSyncEnabled = false
        }
        finishAttempt()
    }

    private func fail(_ error: Error) {
        Self.logger.error(
            "iCloud preference sync failed: \(error.localizedDescription, privacy: .public)"
        )
        scheduleRetry()
        finishAttempt()
    }

    private func scheduleRetry() {
        guard isEnabled else {
            return
        }
        retryWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.requestSynchronization(urgency: .automatic)
        }
        retryWorkItem = item
        queue.asyncAfter(deadline: .now() + retryInterval, execute: item)
    }

    private func finishAttempt() {
        synchronizing = false
        activeTransfer = nil
        if synchronizeAgain {
            synchronizeAgain = false
            requestSynchronization(urgency: .automatic)
            return
        }
        finishCompletions()
    }

    private func finishCompletions() {
        let pending = completions
        completions.removeAll()
        guard !pending.isEmpty else {
            return
        }
        DispatchQueue.main.async {
            pending.forEach { $0() }
        }
    }

    private func stopSynchronization() {
        activeTransfer?.cancel()
        activeTransfer = nil
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        retryWorkItem?.cancel()
        retryWorkItem = nil
        synchronizing = false
        synchronizeAgain = false
    }

    private func persistState() {
        do {
            try stateStore.save(state)
        } catch {
            Self.logger.error(
                "Could not persist iCloud preference state: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}

final class CloudPreferencesSyncService {
    static let shared = CloudPreferencesSyncService()

    private let coordinator: CloudPreferencesSyncCoordinator?

    private init() {
        guard ProcessEntitlements.isEntitledForICloudContainer(
            CloudKitUserDataTransport.containerIdentifier
        ), let location = try? UserDataLocation.userDomain() else {
            coordinator = nil
            return
        }
        coordinator = CloudPreferencesSyncCoordinator(
            preferences: .shared,
            transport: CloudKitPreferencesTransport(),
            stateStore: FileCloudPreferencesStateStore(location: location)
        )
    }

    func start() {
        coordinator?.start()
    }

    func synchronizeNow() {
        coordinator?.synchronizeNow()
    }
}
