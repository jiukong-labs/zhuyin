import CloudKit
import CryptoKit
import Foundation
import Security
import os

/// Reads the running process's own code-signing entitlements.
///
/// The repository's ad-hoc local build deliberately ships without the
/// CloudKit container entitlement (see `JIUKONG_CLOUDKIT_ENTITLEMENTS` in
/// `project.yml`) — only a Developer Team build carries it. Constructing a
/// `CKContainer` without that entitlement traps the process instead of
/// throwing a Swift error, so callers must check first and skip CloudKit
/// entirely when it is absent.
enum ProcessEntitlements {
    static func isEntitledForICloudContainer(_ identifier: String) -> Bool {
        guard let task = SecTaskCreateFromSelf(nil) else {
            return false
        }
        guard let value = SecTaskCopyValueForEntitlement(
            task,
            "com.apple.developer.icloud-container-identifiers" as CFString,
            nil
        ) else {
            return false
        }
        guard let identifiers = value as? [String] else {
            return false
        }
        return identifiers.contains(identifier)
    }
}

/// Synchronizes user-created pronunciation aliases through the same private
/// CloudKit container and record zone as the existing learning data.
///
/// The bundled dictionary is never edited. Local aliases stay in
/// `custom-readings.json`; this coordinator keeps a small sidecar journal only
/// for conflict timestamps and deletion tombstones. It waits until the normal
/// learning sync has successfully authorized the current iCloud account before
/// doing any custom-reading network work.
final class CustomReadingCloudSyncCoordinator {
    static let shared = CustomReadingCloudSyncCoordinator()

    fileprivate struct Identity: Codable, Equatable, Hashable {
        let character: String
        let pronunciation: String

        init(character: String, pronunciation: String) throws {
            let validated = try CustomReadingValidator.validate(
                character: character,
                pronunciation: pronunciation
            )
            self.character = validated.character
            self.pronunciation = validated.pronunciation
        }

        init(_ record: CustomReadingRecord) throws {
            try self.init(
                character: record.character,
                pronunciation: record.pronunciation
            )
        }

        var recordName: String {
            var data = Data("jiukong-custom-reading-v1\u{0}".utf8)
            Self.appendLengthPrefixed(Data(character.utf8), to: &data)
            Self.appendLengthPrefixed(Data(pronunciation.utf8), to: &data)
            let digest = SHA256.hash(data: data)
            return "v1-" + digest.map {
                String(format: "%02x", $0)
            }.joined()
        }

        private static func appendLengthPrefixed(
            _ value: Data,
            to data: inout Data
        ) {
            var length = UInt64(value.count).bigEndian
            withUnsafeBytes(of: &length) {
                data.append(contentsOf: $0)
            }
            data.append(value)
        }
    }

    fileprivate struct CloudValue: Equatable {
        let identity: Identity
        let timestamp: Date
        let deleted: Bool
    }

    private struct StateEntry: Codable, Equatable {
        let identity: Identity
        /// Timestamp used for cloud conflict resolution.
        var cloudTimestamp: Date
        /// The concrete local record timestamp last observed. This can differ
        /// from `cloudTimestamp` after a remote record is materialized locally,
        /// because the public editing API stamps that write with the local
        /// clock. Keeping both prevents a remote merge from looking like a new
        /// local edit on the following sync.
        var localObservedUpdatedAt: Date?
        var deleted: Bool
    }

    private struct PersistedState: Codable {
        static let currentVersion = 1

        var version = currentVersion
        var entries: [String: StateEntry] = [:]

        func validated() -> PersistedState? {
            guard version == Self.currentVersion,
                  entries.allSatisfy({ key, value in
                      key == value.identity.recordName
                  }) else {
                return nil
            }
            return self
        }
    }

    private static let logger = Logger(
        subsystem: "tw.idv.jiukong.inputmethod.zhuyin",
        category: "CustomReadingCloudSync"
    )

    private let queue = DispatchQueue(
        label: "tw.idv.jiukong.custom-reading-cloud-sync",
        qos: .utility
    )
    private let notificationCenter: NotificationCenter
    private let fileManager: FileManager
    private let now: () -> Date

    private var service: (any CustomReadingManaging)?
    private var transport: CustomReadingCloudTransport?
    private var state = PersistedState()
    private var stateURL: URL?
    private var started = false
    private var generalSyncReady = false
    private var synchronizationInProgress = false
    private var synchronizeAgain = false
    private var ignoredServiceNotifications = 0
    private var customChangeObserver: NSObjectProtocol?
    private var generalStatusObserver: NSObjectProtocol?
    private var debounceWorkItem: DispatchWorkItem?

    init(
        notificationCenter: NotificationCenter = .default,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.notificationCenter = notificationCenter
        self.fileManager = fileManager
        self.now = now
    }

    deinit {
        if let customChangeObserver {
            notificationCenter.removeObserver(customChangeObserver)
        }
        if let generalStatusObserver {
            notificationCenter.removeObserver(generalStatusObserver)
        }
    }

    /// Call before `UserLearningService.startCloudSync()`. Installing the
    /// observer synchronously avoids missing the first successful learning
    /// sync on a very fast network.
    func start(service: any CustomReadingManaging) {
        guard !started else {
            return
        }
        guard ProcessEntitlements.isEntitledForICloudContainer(
            CloudKitUserDataTransport.containerIdentifier
        ) else {
            Self.logger.notice(
                "This build has no iCloud entitlement; custom-reading sync is disabled."
            )
            return
        }

        let stateURL: URL
        do {
            let location = try UserDataLocation.userDomain()
            try location.prepareDirectory(fileManager: fileManager)
            stateURL = location.directoryURL.appendingPathComponent(
                "custom-reading-cloud-state.json",
                isDirectory: false
            )
        } catch {
            Self.logger.error(
                "Could not prepare custom-reading cloud state: \(error.localizedDescription, privacy: .public)"
            )
            return
        }

        self.service = service
        transport = CustomReadingCloudTransport()
        self.stateURL = stateURL
        state = loadState(from: stateURL)
        reconcileLocalSnapshot(at: now())
        persistState()
        installObservers(service: service)
        started = true
    }

    private func installObservers(service: any CustomReadingManaging) {
        customChangeObserver = notificationCenter.addObserver(
            forName: CustomReadingService.didChangeNotification,
            object: service,
            queue: nil
        ) { [weak self] _ in
            self?.queue.async {
                guard let self else {
                    return
                }
                if self.ignoredServiceNotifications > 0 {
                    self.ignoredServiceNotifications -= 1
                    return
                }
                self.reconcileLocalSnapshot(at: self.now())
                self.persistState()
                if self.generalSyncReady {
                    self.scheduleSynchronization()
                }
            }
        }

        generalStatusObserver = notificationCenter.addObserver(
            forName: UserDataCloudSyncCoordinator.statusDidChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let coordinator = notification.object
                    as? UserDataCloudSyncCoordinator else {
                return
            }
            let status = coordinator.status
            self?.queue.async {
                self?.handleGeneralSyncStatus(status)
            }
        }
    }

    private func handleGeneralSyncStatus(_ status: UserDataCloudSyncStatus) {
        switch status {
        case let .idle(lastSuccessfulSync):
            generalSyncReady = lastSuccessfulSync != nil
            if generalSyncReady {
                requestSynchronization()
            }
        case .disabled, .syncing, .unavailable:
            generalSyncReady = false
        }
    }

    private func scheduleSynchronization() {
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.requestSynchronization()
        }
        debounceWorkItem = item
        queue.asyncAfter(deadline: .now() + 1, execute: item)
    }

    private func requestSynchronization() {
        guard generalSyncReady,
              service != nil,
              let transport else {
            return
        }
        if synchronizationInProgress {
            synchronizeAgain = true
            return
        }

        synchronizationInProgress = true
        reconcileLocalSnapshot(at: now())
        persistState()
        transport.fetchAll { [weak self] result in
            self?.queue.async {
                self?.handleFetchResult(result)
            }
        }
    }

    private func handleFetchResult(
        _ result: Result<[CloudValue], Error>
    ) {
        guard generalSyncReady,
              let transport else {
            finishSynchronization()
            return
        }

        switch result {
        case let .failure(error):
            Self.logger.error(
                "Could not fetch custom readings from iCloud: \(error.localizedDescription, privacy: .public)"
            )
            finishSynchronization()

        case let .success(remoteValues):
            merge(remoteValues: remoteValues)
            persistState()
            let uploadValues = cloudValuesFromState()
            transport.save(uploadValues) { [weak self] saveResult in
                self?.queue.async {
                    if case let .failure(error) = saveResult {
                        Self.logger.error(
                            "Could not save custom readings to iCloud: \(error.localizedDescription, privacy: .public)"
                        )
                    }
                    self?.finishSynchronization()
                }
            }
        }
    }

    private func finishSynchronization() {
        synchronizationInProgress = false
        if synchronizeAgain, generalSyncReady {
            synchronizeAgain = false
            requestSynchronization()
        } else {
            synchronizeAgain = false
        }
    }

    private func merge(remoteValues: [CloudValue]) {
        guard let service else {
            return
        }
        reconcileLocalSnapshot(at: now())
        var remoteByName: [String: CloudValue] = [:]
        for remote in remoteValues {
            let key = remote.identity.recordName
            if let existing = remoteByName[key] {
                remoteByName[key] = Self.preferred(existing, remote)
            } else {
                remoteByName[key] = remote
            }
        }

        let localValues = cloudValuesFromState()
        let keys = Set(localValues.keys).union(remoteByName.keys)
        for key in keys.sorted() {
            guard let remote = remoteByName[key] else {
                continue
            }
            if let local = localValues[key],
               !Self.remoteWins(remote, over: local) {
                continue
            }

            if remote.deleted {
                if service.allCustomReadings().contains(where: {
                    (try? Identity($0).recordName) == key
                }) {
                    ignoredServiceNotifications += 1
                    guard service.deleteCustomReading(
                        character: remote.identity.character,
                        pronunciation: remote.identity.pronunciation
                    ) else {
                        ignoredServiceNotifications -= 1
                        continue
                    }
                }
                state.entries[key] = StateEntry(
                    identity: remote.identity,
                    cloudTimestamp: remote.timestamp,
                    localObservedUpdatedAt: nil,
                    deleted: true
                )
                continue
            }

            var localRecord = service.allCustomReadings().first {
                (try? Identity($0).recordName) == key
            }
            if localRecord == nil {
                ignoredServiceNotifications += 1
                guard service.upsertCustomReading(
                    character: remote.identity.character,
                    pronunciation: remote.identity.pronunciation
                ) else {
                    ignoredServiceNotifications -= 1
                    continue
                }
                localRecord = service.allCustomReadings().first {
                    (try? Identity($0).recordName) == key
                }
            }
            guard let localRecord else {
                continue
            }
            state.entries[key] = StateEntry(
                identity: remote.identity,
                cloudTimestamp: remote.timestamp,
                localObservedUpdatedAt: localRecord.updatedAt,
                deleted: false
            )
        }
    }

    /// Detects local edits and deletions by comparing the concrete JSON record
    /// timestamp with the last local timestamp the journal observed.
    private func reconcileLocalSnapshot(at date: Date) {
        guard let service else {
            return
        }
        var localByName: [String: (Identity, CustomReadingRecord)] = [:]
        for record in service.allCustomReadings() {
            guard let identity = try? Identity(record) else {
                continue
            }
            localByName[identity.recordName] = (identity, record)
        }

        for (key, entry) in Array(state.entries) {
            guard let local = localByName[key] else {
                if !entry.deleted {
                    state.entries[key] = StateEntry(
                        identity: entry.identity,
                        cloudTimestamp: date,
                        localObservedUpdatedAt: nil,
                        deleted: true
                    )
                }
                continue
            }

            if entry.deleted {
                // A record re-created after a deletion is an explicit local
                // action only when its local timestamp is newer than the
                // tombstone. Equal timestamps keep the deletion to avoid
                // resurrection when two devices race.
                if local.1.updatedAt > entry.cloudTimestamp {
                    state.entries[key] = StateEntry(
                        identity: local.0,
                        cloudTimestamp: local.1.updatedAt,
                        localObservedUpdatedAt: local.1.updatedAt,
                        deleted: false
                    )
                }
                continue
            }

            if local.1.updatedAt != entry.localObservedUpdatedAt {
                state.entries[key] = StateEntry(
                    identity: local.0,
                    cloudTimestamp: local.1.updatedAt,
                    localObservedUpdatedAt: local.1.updatedAt,
                    deleted: false
                )
            }
        }

        for (key, local) in localByName where state.entries[key] == nil {
            state.entries[key] = StateEntry(
                identity: local.0,
                cloudTimestamp: local.1.updatedAt,
                localObservedUpdatedAt: local.1.updatedAt,
                deleted: false
            )
        }
    }

    private func cloudValuesFromState() -> [String: CloudValue] {
        Dictionary(
            uniqueKeysWithValues: state.entries.map { key, entry in
                (
                    key,
                    CloudValue(
                        identity: entry.identity,
                        timestamp: entry.cloudTimestamp,
                        deleted: entry.deleted
                    )
                )
            }
        )
    }

    private static func preferred(
        _ lhs: CloudValue,
        _ rhs: CloudValue
    ) -> CloudValue {
        if lhs.timestamp != rhs.timestamp {
            return lhs.timestamp > rhs.timestamp ? lhs : rhs
        }
        if lhs.deleted != rhs.deleted {
            return lhs.deleted ? lhs : rhs
        }
        return lhs
    }

    static func remoteWinsForTesting(
        remoteTimestamp: Date,
        remoteDeleted: Bool,
        localTimestamp: Date,
        localDeleted: Bool
    ) -> Bool {
        if remoteTimestamp != localTimestamp {
            return remoteTimestamp > localTimestamp
        }
        if remoteDeleted != localDeleted {
            return remoteDeleted
        }
        return false
    }

    private static func remoteWins(
        _ remote: CloudValue,
        over local: CloudValue
    ) -> Bool {
        remoteWinsForTesting(
            remoteTimestamp: remote.timestamp,
            remoteDeleted: remote.deleted,
            localTimestamp: local.timestamp,
            localDeleted: local.deleted
        )
    }

    private func loadState(from url: URL) -> PersistedState {
        guard let data = try? Data(contentsOf: url) else {
            return PersistedState()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let decoded = try? decoder.decode(PersistedState.self, from: data),
              let validated = decoded.validated() else {
            return PersistedState()
        }
        return validated
    }

    private func persistState() {
        guard let stateURL else {
            return
        }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(state).write(to: stateURL, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: stateURL.path
            )
        } catch {
            Self.logger.error(
                "Could not persist custom-reading cloud state: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}

/// CloudKit transport for custom readings. It deliberately reuses the already
/// deployed `JKUserLearning` record type and existing fields, distinguished by
/// `kind = customReading`, so the production CloudKit schema does not require a
/// new record type or field deployment.
private final class CustomReadingCloudTransport {
    private static let recordType = CloudKitUserDataTransport.recordType
    private static let customKind = "customReading"
    private static let schemaVersion: Int64 = 1
    private static let maximumBatchSize = 100

    private enum Field {
        static let schemaVersion = "schemaVersion"
        static let kind = "kind"
        static let deleted = "deleted"
        static let text = "text"
        static let readings = "readings"
        static let createdAt = "createdAt"
        static let lastUsedAt = "lastUsedAt"
        static let suppressedAt = "suppressedAt"

        static let encrypted = [
            text,
            readings,
            createdAt,
            lastUsedAt,
            suppressedAt,
        ]
    }

    private let container: CKContainer
    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID
    private let cacheLock = NSLock()
    private var cachedRecords: [String: CKRecord] = [:]

    init() {
        container = CKContainer(
            identifier: CloudKitUserDataTransport.containerIdentifier
        )
        database = container.privateCloudDatabase
        zoneID = CKRecordZone.ID(
            zoneName: CloudKitUserDataTransport.zoneName,
            ownerName: CKCurrentUserDefaultName
        )
    }

    func fetchAll(
        completion: @escaping (
            Result<[CustomReadingCloudSyncCoordinator.CloudValue], Error>
        ) -> Void
    ) {
        let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        configuration.previousServerChangeToken = nil
        let operation = CKFetchRecordZoneChangesOperation(
            recordZoneIDs: [zoneID],
            configurationsByRecordZoneID: [zoneID: configuration]
        )
        operation.fetchAllChanges = true
        configure(operation)

        let resultLock = NSLock()
        var fetched: [String: CKRecord] = [:]
        var firstError: Error?
        operation.recordWasChangedBlock = { recordID, result in
            resultLock.lock()
            defer { resultLock.unlock() }
            switch result {
            case let .success(record):
                guard record.recordType == Self.recordType,
                      (record[Field.kind] as? String) == Self.customKind else {
                    return
                }
                fetched[recordID.recordName] = record
            case let .failure(error):
                if firstError == nil {
                    firstError = error
                }
            }
        }
        operation.recordZoneFetchResultBlock = { _, result in
            if case let .failure(error) = result {
                resultLock.lock()
                if firstError == nil {
                    firstError = error
                }
                resultLock.unlock()
            }
        }
        operation.fetchRecordZoneChangesResultBlock = { [weak self] result in
            guard let self else {
                return
            }
            if case let .failure(error) = result {
                completion(.failure(error))
                return
            }
            resultLock.lock()
            let error = firstError
            let records = Array(fetched.values)
            resultLock.unlock()
            if let error {
                completion(.failure(error))
                return
            }

            var values: [CustomReadingCloudSyncCoordinator.CloudValue] = []
            var cache: [String: CKRecord] = [:]
            for record in records {
                do {
                    let value = try Self.decode(record)
                    values.append(value)
                    cache[record.recordID.recordName] = record
                } catch {
                    Self.logInvalidRecord(error)
                }
            }
            cacheLock.lock()
            cachedRecords = cache
            cacheLock.unlock()
            completion(.success(values))
        }
        database.add(operation)
    }

    func save(
        _ values: [String: CustomReadingCloudSyncCoordinator.CloudValue],
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let records = values.values
            .sorted { $0.identity.recordName < $1.identity.recordName }
            .map(makeRecord)
        let batches = stride(
            from: 0,
            to: records.count,
            by: Self.maximumBatchSize
        ).map { start in
            Array(
                records[start ..< min(
                    start + Self.maximumBatchSize,
                    records.count
                )]
            )
        }
        saveBatches(batches, index: 0, completion: completion)
    }

    private func saveBatches(
        _ batches: [[CKRecord]],
        index: Int,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard batches.indices.contains(index) else {
            completion(.success(()))
            return
        }
        let operation = CKModifyRecordsOperation(
            recordsToSave: batches[index],
            recordIDsToDelete: nil
        )
        operation.savePolicy = .changedKeys
        operation.isAtomic = false
        configure(operation)
        operation.perRecordSaveBlock = { [weak self] recordID, result in
            guard let self,
                  case let .success(record) = result else {
                return
            }
            cacheLock.lock()
            cachedRecords[recordID.recordName] = record
            cacheLock.unlock()
        }
        operation.modifyRecordsResultBlock = { [weak self] result in
            guard let self else {
                return
            }
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case .success:
                saveBatches(
                    batches,
                    index: index + 1,
                    completion: completion
                )
            }
        }
        database.add(operation)
    }

    private func makeRecord(
        _ value: CustomReadingCloudSyncCoordinator.CloudValue
    ) -> CKRecord {
        let recordName = value.identity.recordName
        cacheLock.lock()
        let cached = cachedRecords[recordName]
        cacheLock.unlock()
        let record = cached ?? CKRecord(
            recordType: Self.recordType,
            recordID: CKRecord.ID(recordName: recordName, zoneID: zoneID)
        )

        record[Field.schemaVersion] = NSNumber(value: Self.schemaVersion)
        record[Field.kind] = Self.customKind
        record[Field.deleted] = NSNumber(value: value.deleted)
        for field in Field.encrypted {
            record.encryptedValues[field] = nil
        }
        record.encryptedValues[Field.text] = value.identity.character
        record.encryptedValues[Field.readings] = [value.identity.pronunciation]
        if value.deleted {
            record.encryptedValues[Field.suppressedAt] = NSNumber(
                value: Self.milliseconds(value.timestamp)
            )
        } else {
            // Creation time has no ordering role for aliases. Using the same
            // effective timestamp on every device keeps the CloudKit payload
            // stable even when a remote alias had to be materialized through
            // the local editing API first.
            let timestamp = NSNumber(
                value: Self.milliseconds(value.timestamp)
            )
            record.encryptedValues[Field.createdAt] = timestamp
            record.encryptedValues[Field.lastUsedAt] = timestamp
        }
        return record
    }

    private static func decode(
        _ record: CKRecord
    ) throws -> CustomReadingCloudSyncCoordinator.CloudValue {
        guard record.recordType == recordType,
              integer(record[Field.schemaVersion]) == schemaVersion,
              (record[Field.kind] as? String) == customKind,
              let character = record.encryptedValues[Field.text] as? String,
              let readings = record.encryptedValues[Field.readings]
                as? [String],
              readings.count == 1 else {
            throw CustomReadingCloudError.invalidRecord
        }

        let identity = try CustomReadingCloudSyncCoordinator.Identity(
            character: character,
            pronunciation: readings[0]
        )
        guard identity.recordName == record.recordID.recordName else {
            throw CustomReadingCloudError.invalidRecord
        }

        let deleted = integer(record[Field.deleted]) == 1
        let rawTimestamp: Int64?
        if deleted {
            rawTimestamp = integer(
                record.encryptedValues[Field.suppressedAt]
            )
        } else {
            rawTimestamp = integer(
                record.encryptedValues[Field.lastUsedAt]
            )
        }
        guard let rawTimestamp else {
            throw CustomReadingCloudError.invalidRecord
        }
        return CustomReadingCloudSyncCoordinator.CloudValue(
            identity: identity,
            timestamp: date(milliseconds: rawTimestamp),
            deleted: deleted
        )
    }

    private func configure(_ operation: CKOperation) {
        let configuration = CKOperation.Configuration()
        configuration.qualityOfService = .utility
        configuration.allowsCellularAccess = true
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        operation.configuration = configuration
    }

    private static func milliseconds(_ date: Date) -> Int64 {
        let value = date.timeIntervalSince1970 * 1_000
        if value >= Double(Int64.max) {
            return Int64.max
        }
        if value <= Double(Int64.min) {
            return Int64.min
        }
        return Int64(value.rounded(.towardZero))
    }

    private static func date(milliseconds value: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(value) / 1_000)
    }

    private static func integer(_ value: CKRecordValue?) -> Int64? {
        (value as? NSNumber)?.int64Value
    }

    private static func logInvalidRecord(_ error: Error) {
        Logger(
            subsystem: "tw.idv.jiukong.inputmethod.zhuyin",
            category: "CustomReadingCloudSync"
        ).error(
            "Ignoring one invalid iCloud custom-reading record: \(error.localizedDescription, privacy: .public)"
        )
    }
}

private enum CustomReadingCloudError: LocalizedError {
    case invalidRecord

    var errorDescription: String? {
        switch self {
        case .invalidRecord:
            return "iCloud contains an invalid custom-reading record."
        }
    }
}
