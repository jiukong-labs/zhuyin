import CloudKit
import Foundation

enum UserDataCloudSyncState: Equatable {
    case disabled
    case idle(lastSuccessfulSync: Date?)
    case syncing
    case unavailable(CloudAccountAvailability)
    case failed(String)

    var localizedDescription: String {
        switch self {
        case .disabled:
            return "iCloud 同步已關閉。"
        case let .idle(lastSuccessfulSync):
            guard let lastSuccessfulSync else {
                return "等待第一次同步。"
            }
            return "上次同步：\(Self.dateFormatter.string(from: lastSuccessfulSync))"
        case .syncing:
            return "正在與 iCloud 同步…"
        case let .unavailable(availability):
            return availability.localizedDescription + "。"
        case let .failed(message):
            return "同步失敗：\(message)"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()
}

/// Coordinates local SQLite snapshots with one private CloudKit record.
///
/// Ordinary learning changes use the archive's idempotent max/union merge.
/// Explicit deletions use replacement mode so a deleted entry isn't restored
/// by the old cloud snapshot on the very next synchronization.
final class UserDataCloudSyncService {
    static let didChangeNotification = Notification.Name(
        "tw.idv.jiukong.UserDataCloudSyncStateDidChange"
    )

    static let shared = UserDataCloudSyncService()

    private enum SyncMode: Equatable {
        case merge
        case replace

        mutating func include(_ other: SyncMode) {
            if other == .replace {
                self = .replace
            }
        }
    }

    private let preferences: PreferencesController
    private let learning: UserLearningService
    private let transport: CloudUserDataTransport
    private let notificationCenter: NotificationCenter
    private let now: () -> Date
    private let debounceInterval: TimeInterval
    private let queue: DispatchQueue

    private let stateLock = NSLock()
    private var storedState: UserDataCloudSyncState

    private var isStarted = false
    private var isSynchronizing = false
    private var pendingMode: SyncMode?
    private var scheduledWorkItem: DispatchWorkItem?
    private var activeTransportOperation: (any CloudUserDataOperation)?
    private var operationGeneration: UInt = 0
    private var observerTokens: [NSObjectProtocol] = []
    private var completionHandlers: [(UserDataCloudSyncState) -> Void] = []

    init(
        preferences: PreferencesController = .shared,
        learning: UserLearningService = .shared,
        transport: CloudUserDataTransport = CloudKitUserDataTransport(),
        notificationCenter: NotificationCenter = .default,
        now: @escaping () -> Date = Date.init,
        debounceInterval: TimeInterval = 3,
        queueLabel: String = "tw.idv.jiukong.cloud-sync"
    ) {
        self.preferences = preferences
        self.learning = learning
        self.transport = transport
        self.notificationCenter = notificationCenter
        self.now = now
        self.debounceInterval = debounceInterval
        queue = DispatchQueue(label: queueLabel, qos: .utility)
        storedState = preferences.current.cloudSyncEnabled
            ? .idle(lastSuccessfulSync: nil)
            : .disabled
    }

    deinit {
        for token in observerTokens {
            notificationCenter.removeObserver(token)
        }
    }

    var state: UserDataCloudSyncState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return storedState
    }

    /// Starts automatic restore and change observation. Repeated calls are
    /// harmless because InputMethodKit can ask for the settings window often.
    func start() {
        queue.async { [weak self] in
            guard let self, !self.isStarted else {
                return
            }
            self.startObserving()
            if self.preferences.current.cloudSyncEnabled {
                self.enqueue(mode: .merge, delay: 0)
            } else {
                self.publish(.disabled)
            }
        }
    }

    func synchronizeNow(
        completion: ((UserDataCloudSyncState) -> Void)? = nil
    ) {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            self.startObserving()
            if let completion {
                self.completionHandlers.append(completion)
            }
            self.enqueue(mode: .merge, delay: 0)
        }
    }

    private func startObserving() {
        guard !isStarted else {
            return
        }
        isStarted = true
        installObservers()
    }

    private func installObservers() {
        let preferencesToken = notificationCenter.addObserver(
            forName: PreferencesController.didChangeNotification,
            object: preferences,
            queue: nil
        ) { [weak self] _ in
            self?.queue.async { [weak self] in
                self?.preferencesDidChange()
            }
        }

        let learningToken = notificationCenter.addObserver(
            forName: UserLearningService.didChangeNotification,
            object: learning,
            queue: nil
        ) { [weak self] notification in
            let mutation = UserLearningMutation(
                notification: notification
            )
            self?.queue.async { [weak self] in
                guard let self,
                      self.preferences.current.cloudSyncEnabled else {
                    return
                }
                self.enqueue(
                    mode: mutation.requiresReplacement ? .replace : .merge,
                    delay: self.debounceInterval
                )
            }
        }

        let accountToken = notificationCenter.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.queue.async { [weak self] in
                guard let self,
                      self.preferences.current.cloudSyncEnabled else {
                    return
                }
                // Consent to one private iCloud database must not silently
                // authorize uploading local data to a different account.
                self.preferences.update {
                    $0.cloudSyncEnabled = false
                }
                self.cancelSynchronization()
            }
        }

        observerTokens = [preferencesToken, learningToken, accountToken]
    }

    private func preferencesDidChange() {
        guard preferences.current.cloudSyncEnabled else {
            cancelSynchronization()
            return
        }
        enqueue(mode: .merge, delay: 0)
    }

    private func cancelSynchronization() {
        operationGeneration &+= 1
        scheduledWorkItem?.cancel()
        scheduledWorkItem = nil
        activeTransportOperation?.cancel()
        activeTransportOperation = nil
        pendingMode = nil
        isSynchronizing = false
        publish(.disabled)
        completeRequests(with: .disabled)
    }

    private func canContinue(generation: UInt) -> Bool {
        generation == operationGeneration
            && preferences.current.cloudSyncEnabled
    }

    private func enqueue(mode: SyncMode, delay: TimeInterval) {
        guard preferences.current.cloudSyncEnabled else {
            publish(.disabled)
            completeRequests(with: .disabled)
            return
        }

        if isSynchronizing {
            if var pendingMode {
                pendingMode.include(mode)
                self.pendingMode = pendingMode
            } else {
                pendingMode = mode
            }
            return
        }

        if var pendingMode {
            pendingMode.include(mode)
            self.pendingMode = pendingMode
        } else {
            pendingMode = mode
        }

        scheduledWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.beginPendingSynchronization()
        }
        scheduledWorkItem = workItem
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func beginPendingSynchronization() {
        scheduledWorkItem = nil
        guard let mode = pendingMode else {
            return
        }
        pendingMode = nil
        isSynchronizing = true
        publish(.syncing)
        let generation = operationGeneration

        transport.accountAvailability { [weak self] result in
            self?.queue.async { [weak self] in
                guard let self, self.canContinue(generation: generation) else {
                    return
                }
                self.handleAccount(
                    result,
                    mode: mode,
                    generation: generation
                )
            }
        }
    }

    private func handleAccount(
        _ result: Result<CloudAccountAvailability, Error>,
        mode: SyncMode,
        generation: UInt
    ) {
        guard canContinue(generation: generation) else {
            return
        }
        switch result {
        case let .failure(error):
            finish(.failed(error.localizedDescription))
        case let .success(availability) where availability != .available:
            finish(.unavailable(availability))
        case .success:
            switch mode {
            case .merge:
                fetchAndMerge(retryCount: 0, generation: generation)
            case .replace:
                saveLocalSnapshot(
                    retryCount: 0,
                    mode: .replace,
                    generation: generation
                )
            }
        }
    }

    private func fetchAndMerge(retryCount: Int, generation: UInt) {
        guard canContinue(generation: generation) else {
            return
        }
        activeTransportOperation = transport.fetchArchive { [weak self] result in
            self?.queue.async { [weak self] in
                guard let self,
                      self.canContinue(generation: generation) else {
                    return
                }
                self.activeTransportOperation = nil
                switch result {
                case let .failure(error):
                    self.finish(.failed(error.localizedDescription))
                case let .success(remoteArchive):
                    if let remoteArchive,
                       self.learning.merge(
                           remoteArchive,
                           notifyChange: false
                       ) == nil {
                        self.finish(.failed("無法將雲端資料寫入本機資料庫。"))
                        return
                    }
                    self.saveLocalSnapshot(
                        retryCount: retryCount,
                        mode: .merge,
                        generation: generation
                    )
                }
            }
        }
    }

    private func saveLocalSnapshot(
        retryCount: Int,
        mode: SyncMode,
        generation: UInt
    ) {
        guard canContinue(generation: generation) else {
            return
        }
        guard let archive = learning.exportArchive(at: now()) else {
            finish(.failed("無法讀取本機使用者資料。"))
            return
        }

        guard canContinue(generation: generation) else {
            return
        }
        activeTransportOperation = transport.saveArchive(archive) { [weak self] result in
            self?.queue.async { [weak self] in
                guard let self,
                      self.canContinue(generation: generation) else {
                    return
                }
                self.activeTransportOperation = nil
                switch result {
                case .success:
                    self.finish(.idle(lastSuccessfulSync: self.now()))
                case let .failure(error)
                    where error as? CloudUserDataTransportError == .conflict
                        && retryCount < 2:
                    if mode == .merge {
                        self.fetchAndMerge(
                            retryCount: retryCount + 1,
                            generation: generation
                        )
                    } else {
                        self.saveLocalSnapshot(
                            retryCount: retryCount + 1,
                            mode: .replace,
                            generation: generation
                        )
                    }
                case let .failure(error):
                    self.finish(.failed(error.localizedDescription))
                }
            }
        }
    }

    private func finish(_ state: UserDataCloudSyncState) {
        activeTransportOperation = nil
        isSynchronizing = false
        if preferences.current.cloudSyncEnabled {
            publish(state)
        } else {
            publish(.disabled)
        }
        completeRequests(with: self.state)

        if let mode = pendingMode {
            pendingMode = nil
            enqueue(mode: mode, delay: 0)
        }
    }

    private func publish(_ state: UserDataCloudSyncState) {
        stateLock.lock()
        let changed = storedState != state
        storedState = state
        stateLock.unlock()

        guard changed else {
            return
        }
        DispatchQueue.main.async { [notificationCenter, weak self] in
            guard let self else {
                return
            }
            notificationCenter.post(
                name: Self.didChangeNotification,
                object: self
            )
        }
    }

    private func completeRequests(with state: UserDataCloudSyncState) {
        let handlers = completionHandlers
        completionHandlers.removeAll()
        DispatchQueue.main.async {
            for handler in handlers {
                handler(state)
            }
        }
    }
}
