import CloudKit
import Foundation
import os

enum UserDataCloudSyncStatus: Equatable {
    case disabled
    case idle(lastSuccessfulSync: Date?)
    case syncing
    case unavailable(String)

    var localizedDescription: String {
        switch self {
        case .disabled:
            return "iCloud 同步已關閉"
        case let .idle(lastSuccessfulSync):
            guard let lastSuccessfulSync else {
                return "等待第一次 iCloud 同步"
            }
            return "上次同步：\(Self.dateFormatter.string(from: lastSuccessfulSync))"
        case .syncing:
            return "正在與 iCloud 同步…"
        case let .unavailable(message):
            return "iCloud 同步暫時無法使用：\(message)"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hant_TW")
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()
}

private enum UserDataCloudSyncCoordinatorError: LocalizedError {
    case timedOut

    var errorDescription: String? {
        switch self {
        case .timedOut:
            return "連線逾時。請確認 VPN 允許 iCloud 連線後再按「立即同步」。"
        }
    }
}

protocol UserDataCloudSyncing: AnyObject {
    var status: UserDataCloudSyncStatus { get }
    func start()
    func synchronizeNow()
    func refreshIfNeeded()
    func preferenceDidChange()
    func noteUpsert(_ identity: CloudUserDataIdentity)
    func noteDeletion(_ identity: CloudUserDataIdentity)
}

/// Reconciles a local offline-first SQLite store with CloudKit records.
///
/// Local input never waits for this queue. Successful local changes append a
/// compact mutation to the state file and are uploaded after a short debounce.
/// On a new Mac, remote records are applied before existing local data is
/// migrated, so cloud tombstones cannot be accidentally resurrected.
final class UserDataCloudSyncCoordinator: UserDataCloudSyncing {
    static let statusDidChangeNotification = Notification.Name(
        "tw.idv.jiukong.UserDataCloudSyncStatusDidChange"
    )
    static let didApplyRemoteChangesNotification = Notification.Name(
        "tw.idv.jiukong.UserDataCloudSyncDidApplyRemoteChanges"
    )

    private enum ExactPin {
        case character(CloudUserDataIdentity, Bool)
        case phrase(CloudUserDataIdentity, Bool)
    }

    private struct Reconciliation {
        let uploads: [CloudUserDataRecord]
        let mutations: [CloudSyncPendingMutation]
        let appliedRemoteChanges: Bool
    }

    private static let logger = Logger(
        subsystem: "tw.idv.jiukong.inputmethod.zhuyin",
        category: "CloudUserData"
    )

    private let store: UserLearningStoring
    private let transport: CloudUserDataTransporting
    private let stateStore: CloudSyncStateStoring
    private let isEnabled: () -> Bool
    private let turnOffSyncAfterAccountChange: () -> Void
    private let now: () -> Date
    private let notificationCenter: NotificationCenter
    private let queue: DispatchQueue
    private let debounceInterval: TimeInterval
    private let retryInterval: TimeInterval
    private let minimumRefreshInterval: TimeInterval
    private let fetchTimeoutInterval: TimeInterval
    private let saveTimeoutInterval: TimeInterval
    private let userInitiatedRetryInterval: TimeInterval

    private let statusLock = NSLock()
    private var statusStorage: UserDataCloudSyncStatus

    private var persistedState: CloudSyncPersistedState
    private var started = false
    private var requiresFreshConsent = false
    private var synchronizationInProgress = false
    private var synchronizeAgain = false
    private var synchronizationID: UInt = 0
    private var activeTransfer: CloudUserDataTransfer?
    private var activeUrgency: CloudUserDataSyncUrgency = .automatic
    private var userInitiatedRetriesRemaining = 0
    private var accountChangeObserver: NSObjectProtocol?
    private var debounceWorkItem: DispatchWorkItem?
    private var retryWorkItem: DispatchWorkItem?
    private var timeoutWorkItem: DispatchWorkItem?
    private var completionHandlers: [() -> Void] = []
    private var lastAttemptAt: Date?

    init(
        store: UserLearningStoring,
        transport: CloudUserDataTransporting,
        stateStore: CloudSyncStateStoring,
        isEnabled: @escaping () -> Bool,
        turnOffSyncAfterAccountChange: @escaping () -> Void = {},
        now: @escaping () -> Date = Date.init,
        notificationCenter: NotificationCenter = .default,
        queueLabel: String = "tw.idv.jiukong.cloud-user-data",
        debounceInterval: TimeInterval = 2,
        retryInterval: TimeInterval = 300,
        minimumRefreshInterval: TimeInterval = 900,
        fetchTimeoutInterval: TimeInterval = 75,
        saveTimeoutInterval: TimeInterval = 300,
        userInitiatedRetryInterval: TimeInterval = 2
    ) {
        self.store = store
        self.transport = transport
        self.stateStore = stateStore
        self.isEnabled = isEnabled
        self.turnOffSyncAfterAccountChange = turnOffSyncAfterAccountChange
        self.now = now
        self.notificationCenter = notificationCenter
        self.debounceInterval = debounceInterval
        self.retryInterval = retryInterval
        self.minimumRefreshInterval = minimumRefreshInterval
        self.fetchTimeoutInterval = fetchTimeoutInterval
        self.saveTimeoutInterval = saveTimeoutInterval
        self.userInitiatedRetryInterval = userInitiatedRetryInterval
        queue = DispatchQueue(label: queueLabel, qos: .utility)
        persistedState = stateStore.load()
        statusStorage = isEnabled()
            ? .idle(lastSuccessfulSync: nil)
            : .disabled
    }

    deinit {
        activeTransfer?.cancel()
        if let accountChangeObserver {
            notificationCenter.removeObserver(accountChangeObserver)
        }
    }

    var status: UserDataCloudSyncStatus {
        statusLock.lock()
        defer { statusLock.unlock() }
        return statusStorage
    }

    func start() {
        queue.async { [weak self] in
            guard let self, !started else {
                return
            }
            started = true
            observeForAccountChanges()
            requestSynchronization(urgency: .automatic)
        }
    }

    func synchronizeNow() {
        synchronizeNow(completion: nil)
    }

    /// Pulls changes when input becomes active, but rate-limits focus changes
    /// so moving among text fields cannot turn into repeated network traffic.
    func refreshIfNeeded() {
        queue.async { [weak self] in
            guard let self, synchronizationIsEnabled else {
                return
            }
            if let lastAttemptAt,
               now().timeIntervalSince(lastAttemptAt) < minimumRefreshInterval {
                return
            }
            requestSynchronization(urgency: .automatic)
        }
    }

    /// Test and settings hook. The completion is delivered on the main queue
    /// after this attempt finishes, whether it succeeds or fails.
    func synchronizeNow(completion: (() -> Void)?) {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            if let completion {
                completionHandlers.append(completion)
            }
            debounceWorkItem?.cancel()
            debounceWorkItem = nil
            retryWorkItem?.cancel()
            retryWorkItem = nil
            if !synchronizationInProgress
                || activeUrgency != .userInitiated {
                userInitiatedRetriesRemaining = 1
            }
            requestSynchronization(urgency: .userInitiated)
        }
    }

    func preferenceDidChange() {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            if isEnabled() {
                requiresFreshConsent = false
                setStatus(.idle(lastSuccessfulSync: nil))
                requestSynchronization(urgency: .automatic)
            } else {
                stopSynchronization()
            }
        }
    }

    func noteUpsert(_ identity: CloudUserDataIdentity) {
        note(.upsert, identity: identity)
    }

    func noteDeletion(_ identity: CloudUserDataIdentity) {
        note(.delete, identity: identity)
    }

    private func note(
        _ action: CloudSyncMutationAction,
        identity: CloudUserDataIdentity
    ) {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            persistedState.note(action, identity: identity)
            do {
                try stateStore.save(persistedState)
            } catch {
                Self.logger.error(
                    "Could not persist an iCloud mutation: \(error.localizedDescription, privacy: .public)"
                )
                setStatus(.unavailable(error.localizedDescription))
            }
            guard synchronizationIsEnabled else {
                setStatus(.disabled)
                return
            }
            scheduleDebouncedSynchronization()
        }
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
        guard synchronizationIsEnabled else {
            stopSynchronization()
            return
        }
        if synchronizationInProgress {
            if urgency == .userInitiated,
               activeUrgency == .automatic {
                cancelActiveAttempt()
            } else {
                if urgency == .automatic {
                    synchronizeAgain = true
                }
                return
            }
        }

        synchronizationInProgress = true
        activeUrgency = urgency
        synchronizationID &+= 1
        let currentSynchronizationID = synchronizationID
        lastAttemptAt = now()
        setStatus(.syncing)
        activeTransfer = transport.fetchAll(urgency: urgency) {
            [weak self] result in
            self?.queue.async {
                self?.handleFetchResult(
                    result,
                    synchronizationID: currentSynchronizationID
                )
            }
        }
        scheduleTimeout(
            after: fetchTimeoutInterval,
            synchronizationID: currentSynchronizationID
        )
    }

    private func handleFetchResult(
        _ result: Result<CloudUserDataSnapshot, Error>,
        synchronizationID completedSynchronizationID: UInt
    ) {
        guard completedSynchronizationID == synchronizationID else {
            return
        }
        cancelTimeout()
        activeTransfer = nil
        guard synchronizationIsEnabled else {
            stopSynchronization()
            return
        }
        switch result {
        case let .failure(error):
            finishWithFailure(error)
        case let .success(snapshot):
            do {
                guard try authorize(snapshot.accountIdentifier) else {
                    return
                }
            } catch {
                finishWithFailure(error)
                return
            }
            let reconciliation: Reconciliation
            do {
                reconciliation = try reconcile(snapshot.records)
            } catch {
                finishWithFailure(error)
                return
            }
            activeTransfer = transport.save(
                reconciliation.uploads,
                urgency: activeUrgency
            ) {
                [weak self] result in
                self?.queue.async {
                    self?.handleSaveResult(
                        result,
                        reconciliation: reconciliation,
                        synchronizationID: completedSynchronizationID
                    )
                }
            }
            scheduleTimeout(
                after: saveTimeoutInterval,
                synchronizationID: completedSynchronizationID
            )
        }
    }

    /// Records the account used for first consent and rejects only a genuine
    /// account switch. CloudKit can post `CKAccountChanged` while rebuilding
    /// its local cache after an app update or reinstall, even when the active
    /// Apple Account is unchanged.
    private func authorize(
        _ currentIdentifier: CloudAccountIdentifier
    ) throws -> Bool {
        if let authorizedIdentifier = persistedState.accountIdentifier,
           authorizedIdentifier != currentIdentifier {
            persistedState.accountIdentifier = nil
            try? stateStore.save(persistedState)
            requiresFreshConsent = true
            turnOffSyncAfterAccountChange()
            stopSynchronization()
            return false
        }
        guard persistedState.accountIdentifier == nil else {
            return true
        }
        var savedState = persistedState
        savedState.accountIdentifier = currentIdentifier
        try stateStore.save(savedState)
        persistedState = savedState
        return true
    }

    private func handleSaveResult(
        _ result: Result<Void, Error>,
        reconciliation: Reconciliation,
        synchronizationID completedSynchronizationID: UInt
    ) {
        guard completedSynchronizationID == synchronizationID else {
            return
        }
        cancelTimeout()
        activeTransfer = nil
        guard synchronizationIsEnabled else {
            stopSynchronization()
            return
        }
        switch result {
        case let .failure(error):
            finishWithFailure(error)
        case .success:
            var savedState = persistedState
            savedState.clear(reconciliation.mutations)
            do {
                try stateStore.save(savedState)
                persistedState = savedState
            } catch {
                finishWithFailure(error)
                return
            }

            if reconciliation.appliedRemoteChanges {
                DispatchQueue.main.async { [notificationCenter] in
                    notificationCenter.post(
                        name: Self.didApplyRemoteChangesNotification,
                        object: self
                    )
                }
            }
            finishSuccessfully()
        }
    }

    private func reconcile(
        _ remoteRecords: [CloudUserDataRecord]
    ) throws -> Reconciliation {
        let pendingAtFetch = persistedState.pending
        let localBefore = try localRecords()

        var archives: [UserDataArchive] = []
        var exactPins: [ExactPin] = []
        var deletions: [CloudUserDataIdentity] = []
        var appliedRemoteChanges = false

        for remote in remoteRecords.sorted(by: {
            $0.identity.recordName < $1.identity.recordName
        }) {
            let pending = pendingAtFetch[remote.identity.recordName]
            switch pending?.action {
            case .delete:
                continue
            case .upsert:
                guard let local = localBefore[remote.identity.recordName] else {
                    persistedState.note(.delete, identity: remote.identity)
                    continue
                }
                if let archive = remote.archive {
                    archives.append(archive)
                    if let pinned = local.pinned,
                       let pin = exactPin(
                           identity: remote.identity,
                           pinned: pinned
                       ) {
                        exactPins.append(pin)
                    }
                    appliedRemoteChanges = true
                }
            case nil:
                if let archive = remote.archive {
                    archives.append(archive)
                    if let pinned = remote.pinned,
                       let pin = exactPin(
                           identity: remote.identity,
                           pinned: pinned
                       ) {
                        exactPins.append(pin)
                    }
                } else {
                    deletions.append(remote.identity)
                }
                appliedRemoteChanges = true
            }
        }

        if !archives.isEmpty {
            let combined = UserDataArchive(
                exportedAt: 0,
                characters: archives.flatMap(\.characters),
                phrases: archives.flatMap(\.phrases),
                suppressions: archives.flatMap(\.suppressions)
            )
            try store.merge(combined)
        }
        for pin in exactPins {
            try apply(pin)
        }
        for identity in deletions {
            try delete(identity)
        }

        if !persistedState.completedInitialMerge {
            for record in try localRecords().values {
                persistedState.note(.upsert, identity: record.identity)
            }
            persistedState.completedInitialMerge = true
        }
        try stateStore.save(persistedState)

        let currentLocal = try localRecords()
        var mutations: [CloudSyncPendingMutation] = []
        var uploads: [CloudUserDataRecord] = []
        for mutation in persistedState.pending.values.sorted(by: {
            $0.revision < $1.revision
        }) {
            switch mutation.action {
            case .upsert:
                if let record = currentLocal[mutation.identity.recordName] {
                    mutations.append(mutation)
                    uploads.append(record)
                } else {
                    let deletion = CloudSyncPendingMutation(
                        identity: mutation.identity,
                        action: .delete,
                        revision: mutation.revision
                    )
                    persistedState.pending[mutation.identity.recordName] = deletion
                    mutations.append(deletion)
                    uploads.append(try .tombstone(mutation.identity))
                }
            case .delete:
                mutations.append(mutation)
                uploads.append(try .tombstone(mutation.identity))
            }
        }
        try stateStore.save(persistedState)

        return Reconciliation(
            uploads: uploads,
            mutations: mutations,
            appliedRemoteChanges: appliedRemoteChanges
        )
    }

    private func localRecords() throws -> [String: CloudUserDataRecord] {
        var result: [String: CloudUserDataRecord] = [:]
        for record in try store.allCharacterRecords() {
            let cloudRecord = try CloudUserDataRecord.character(record)
            result[cloudRecord.identity.recordName] = cloudRecord
        }
        for record in try store.allPhraseRecords() {
            let cloudRecord = try CloudUserDataRecord.phrase(record)
            result[cloudRecord.identity.recordName] = cloudRecord
        }
        for record in try store.allSuppressedPhrases() {
            let cloudRecord = try CloudUserDataRecord.suppressedPhrase(record)
            result[cloudRecord.identity.recordName] = cloudRecord
        }
        return result
    }

    private func exactPin(
        identity: CloudUserDataIdentity,
        pinned: Bool
    ) -> ExactPin? {
        switch identity.kind {
        case .character:
            return .character(identity, pinned)
        case .phrase:
            return .phrase(identity, pinned)
        case .suppressedPhrase:
            // A suppression has no pin of its own; its whole state is the
            // merged tombstone row.
            return nil
        }
    }

    private func apply(_ pin: ExactPin) throws {
        switch pin {
        case let .character(identity, pinned):
            try store.setPinned(
                pinned,
                character: identity.text,
                pronunciation: identity.readings[0]
            )
        case let .phrase(identity, pinned):
            try store.setPhrasePinned(
                pinned,
                phrase: identity.text,
                pronunciationSequence: identity.readings
            )
        }
    }

    private func delete(_ identity: CloudUserDataIdentity) throws {
        switch identity.kind {
        case .character:
            try store.deleteCharacterRecord(
                character: identity.text,
                pronunciation: identity.readings[0]
            )
        case .phrase:
            try store.deletePhrase(
                phrase: identity.text,
                pronunciationSequence: identity.readings
            )
        case .suppressedPhrase:
            // Deleting a suppression is a restore: another Mac put the
            // built-in phrase back, so this one stops hiding it too.
            try store.restorePhrase(
                phrase: identity.text,
                pronunciationSequence: identity.readings
            )
        }
    }

    private func finishSuccessfully() {
        cancelTimeout()
        activeTransfer = nil
        retryWorkItem?.cancel()
        retryWorkItem = nil
        synchronizationInProgress = false
        userInitiatedRetriesRemaining = 0
        guard synchronizationIsEnabled else {
            setStatus(.disabled)
            completeCurrentHandlers()
            return
        }
        setStatus(.idle(lastSuccessfulSync: now()))
        completeCurrentHandlers()
        if synchronizeAgain || !persistedState.pending.isEmpty {
            synchronizeAgain = false
            requestSynchronization(urgency: .automatic)
        }
    }

    private func finishWithFailure(_ error: Error) {
        cancelTimeout()
        activeTransfer = nil
        Self.logger.error(
            "iCloud user-data synchronization failed: \(error.localizedDescription, privacy: .public)"
        )
        synchronizationInProgress = false

        if activeUrgency == .userInitiated,
           userInitiatedRetriesRemaining > 0,
           synchronizationIsEnabled {
            userInitiatedRetriesRemaining -= 1
            retryWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                self?.requestSynchronization(urgency: .userInitiated)
            }
            retryWorkItem = item
            queue.asyncAfter(
                deadline: .now() + userInitiatedRetryInterval,
                execute: item
            )
            return
        }

        setStatus(.unavailable(error.localizedDescription))
        completeCurrentHandlers()

        guard started, synchronizationIsEnabled else {
            return
        }
        retryWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.requestSynchronization(urgency: .automatic)
        }
        retryWorkItem = item
        queue.asyncAfter(deadline: .now() + retryInterval, execute: item)
    }

    private var synchronizationIsEnabled: Bool {
        isEnabled() && !requiresFreshConsent
    }

    private func observeForAccountChanges() {
        guard accountChangeObserver == nil else {
            return
        }
        accountChangeObserver = notificationCenter.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.queue.async {
                self?.handleAccountChange()
            }
        }
    }

    private func handleAccountChange() {
        guard synchronizationIsEnabled else {
            return
        }
        let urgency = synchronizationInProgress
            ? activeUrgency
            : .automatic
        cancelActiveAttempt()
        requestSynchronization(urgency: urgency)
    }

    private func stopSynchronization() {
        synchronizationID &+= 1
        activeTransfer?.cancel()
        activeTransfer = nil
        synchronizationInProgress = false
        synchronizeAgain = false
        userInitiatedRetriesRemaining = 0
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        retryWorkItem?.cancel()
        retryWorkItem = nil
        cancelTimeout()
        setStatus(.disabled)
        completeCurrentHandlers()
    }

    private func cancelActiveAttempt() {
        synchronizationID &+= 1
        activeTransfer?.cancel()
        activeTransfer = nil
        synchronizationInProgress = false
        synchronizeAgain = false
        cancelTimeout()
    }

    private func scheduleTimeout(
        after interval: TimeInterval,
        synchronizationID expectedSynchronizationID: UInt
    ) {
        cancelTimeout()
        guard interval > 0 else {
            return
        }
        let item = DispatchWorkItem { [weak self] in
            guard let self,
                  synchronizationInProgress,
                  synchronizationID == expectedSynchronizationID else {
                return
            }
            synchronizationID &+= 1
            activeTransfer?.cancel()
            activeTransfer = nil
            finishWithFailure(UserDataCloudSyncCoordinatorError.timedOut)
        }
        timeoutWorkItem = item
        queue.asyncAfter(deadline: .now() + interval, execute: item)
    }

    private func cancelTimeout() {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
    }

    private func setStatus(_ status: UserDataCloudSyncStatus) {
        statusLock.lock()
        let changed = statusStorage != status
        statusStorage = status
        statusLock.unlock()
        guard changed else {
            return
        }
        DispatchQueue.main.async { [notificationCenter] in
            notificationCenter.post(
                name: Self.statusDidChangeNotification,
                object: self
            )
        }
    }

    private func completeCurrentHandlers() {
        let handlers = completionHandlers
        completionHandlers.removeAll()
        DispatchQueue.main.async {
            handlers.forEach { $0() }
        }
    }
}
