import CloudKit
import CryptoKit
import Foundation
import os

/// CloudKit synchronization for user-created pronunciation aliases.
///
/// Custom readings deliberately stay outside the learning SQLite database, so
/// this coordinator keeps a tiny sidecar journal containing only enough state
/// to detect local deletions and preserve tombstones. The actual aliases remain
/// in `custom-readings.json`.
final class CustomReadingCloudSyncCoordinator {
    static let shared = CustomReadingCloudSyncCoordinator()

    private struct Identity: Codable, Equatable, Hashable {
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
            appendLengthPrefixed(Data(character.utf8), to: &data)
            appendLengthPrefixed(Data(pronunciation.utf8), to: &data)
            let digest = SHA256.hash(data: data)
            return "v1-" + digest.map {
                String(format: "%02x", $0)
            }.joined()
        }

        private func appendLengthPrefixed(_ value: Data, to data: inout Data) {
            var length = UInt64(value.count).bigEndian
            withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
            data.append(value)
        }
    }

    private struct KnownRecord: Codable, Equatable {
        let identity: Identity
        let updatedAt: Date
    }

    private struct Tombstone: Codable, Equatable {
        let identity: Identity
        let deletedAt: Date
    }

    private struct PersistedState: Codable {
        static let currentVersion = 1

        var version = currentVersion
        var knownRecords: [String: KnownRecord] = [:]
        var tombstones: [String: Tombstone] = [:]

        func validated() -> PersistedState? {
            guard version == Self.currentVersion,
                  knownRecords.allSatisfy({ key, value in
                      key == value.identity.recordName
                  }),
                  tombstones.allSatisfy({ key, value in
                      key == value.identity.recordName
                  }) else {
                return nil
            }
            return self
        }
    }

    private enum Payload: Equatable {
        case record(CustomReadingRecord)
        case deleted(Date)
    }

    private struct CloudValue: Equatable {
        let identity: Identity
        let payload: Payload

        var timestamp: Date {
            switch payload {
            case let .record(record):
                return record.updatedAt
            case let .deleted(date):
                return date
            }
        }

        var isDeletion: Bool {
            if case .deleted = payload {
                return true
            }
            return false
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

    private weak var service: (any CustomReadingManaging)?
    private var transport: CustomReadingCloudTransport?
    private var state = PersistedState()
    private var stateURL: URL?
    private var started = false
    private var generalSyncReady = false
    private var synchronizationInProgress = false
    private var synchronizeAgain = false
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

    /// Must be called before the ordinary learning coordinator starts, so its
    /// first successful sync can trigger the initial custom-reading merge.
    func start(service: any CustomReadingManaging) {
        guard ProcessEntitlements.isEntitledForICloudContainer(
            CloudKitUserDataTransport.containerIdentifier
        ) else {
            Self.logger.notice(
                "This build has no iCloud entitlement; custom-reading sync is disabled."
            )
            return
        }

        let transport = CustomReadingCloudTransport()
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

        queue.async { [weak self, weak service] in
            guard let self, let service else {
                return
            }
            self.service = service
            if started {
                return
            }
            started = true
            self.transport = transport
            self.stateURL = stateURL
            state = loadState(from: stateURL)
            reconcileLocalSnapshot(deletionDate: now())
            persistState()
            installObservers(service: service)
        }
    }

    private func installObservers(service: any CustomReadingManaging) {
        customChangeObserver = notificationCenter.addObserver(
            forName: CustomReadingService.didChangeNotification,
            object: service,
            queue: nil
        ) { [weak self] _ in
            self?.queue.async {
                guard let self else { return }
                reconcileLocalSnapshot(deletionDate: now())
                persistState()
                if generalSyncReady {
                    scheduleSynchronization()
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
              let transport,
              service != nil else {
            return
        }
        if synchronizationInProgress {
            synchronizeAgain = true
            return
        }

        synchronizationInProgress = true
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
            mergeRemoteValues(remoteValues)
            let values = localValues()
            transport.save(values) { [weak self] saveResult in
                self?.queue.async {
                    switch saveResult {
                    case .success:
                        self?.persistState()
                    case let .failure(error):
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

    private func mergeRemoteValues(_ remoteValues: [CloudValue]) {
        guard let service else {
            return
        }
        reconcileLocalSnapshot(deletionDate: now())
        var local = localValues()
        var remote: [String: CloudValue] = [:]
        for value in remoteValues {
            let key = value.identity.recordName
            if let existing = remote[key] {
                remote[key] = Self.preferred(existing, value)
            } else {
                remote[key] = value
            }
        }

        let keys = Set(local.keys).union(remote.keys)
        for key in keys.sorted() {
            guard let remoteValue = remote[key] else {
                continue
            }
            if let localValue = local[key],
               !Self.remoteWins(remoteValue, over: localValue) {
                continue
            }

            switch remoteValue.payload {
            case let .record(remoteRecord):
                let existing = service.allCustomReadings().first {
                    (try? Identity($0).recordName) == key
                }
                if existing == nil {
                    guard service.upsertCustomReading(
                        character: remoteValue.identity.character,
                        pronunciation: remoteValue.identity.pronunciation
                    ) else {
                        continue
                    }
                }
                let current = service.allCustomReadings().first {
                    (try? Identity($0).recordName) == key
                }
                let effectiveDate = max(
                    current?.updatedAt ?? remoteRecord.updatedAt,
                    remoteRecord.updatedAt
                )
                state.knownRecords[key] = KnownRecord(
                    identity: remoteValue.identity,
                    updatedAt: effectiveDate
                )
                state.tombstones.removeValue(forKey: key)

            case let .deleted(deletedAt):
                if service.allCustomReadings().contains(where: {
                    (try? Identity($0).recordName) == key
                }) {
                    _ = service.deleteCustomReading(
                        character: remoteValue.identity.character,
                        pronunciation: remoteValue.identity.pronunciation
                    )
                }
                state.knownRecords.removeValue(forKey: key)
                let existing = state.tombstones[key]
                state.tombstones[key] = Tombstone(
                    identity: remoteValue.identity,
                    deletedAt: max(existing?.deletedAt ?? deletedAt, deletedAt)
                )
            }
            local = localValues()
        }
        reconcileLocalSnapshot(deletionDate: now())
        persistState()
    }

    private func reconcileLocalSnapshot(deletionDate: Date) {
        guard let service else {
            return
        }
        var current: [String: (Identity, CustomReadingRecord)] = [:]
        for record in service.allCustomReadings() {
            guard let identity = try? Identity(record) else {
                continue
            }
            current[identity.recordName] = (identity, record)
        }

        for (key, known) in state.knownRecords
            where current[key] == nil {
            let existing = state.tombstones[key]
            if existing == nil || existing!.deletedAt < known.updatedAt {
                state.tombstones[key] = Tombstone(
                    identity: known.identity,
                    deletedAt: deletionDate
                )
            }
            state.knownRecords.removeValue(forKey: key)
        }

        for (key, value) in current {
            if let deletion = state.tombstones[key],
               deletion.deletedAt >= value.1.updatedAt {
                state.knownRecords.removeValue(forKey: key)
                continue
            }
            state.knownRecords[key] = KnownRecord(
                identity: value.0,
                updatedAt: max(
                    state.knownRecords[key]?.updatedAt ?? value.1.updatedAt,
                    value.1.updatedAt
                )
            )
            state.tombstones.removeValue(forKey: key)
        }
    }

    private func localValues() -> [String: CloudValue] {
        guard let service else {
            return [:]
        }
        var result: [String: CloudValue] = [:]
        for record in service.allCustomReadings() {
            guard let identity = try? Identity(record) else {
                continue
            }
            let key = identity.recordName
            let effectiveUpdatedAt = max(
                state.knownRecords[key]?.updatedAt ?? record.updatedAt,
                record.updatedAt
            )
            let effective = CustomReadingRecord(
                character: identity.character,
                pronunciation: identity.pronunciation,
                createdAt: record.createdAt,
                updatedAt: effectiveUpdatedAt
            )
            result[key] = CloudValue(identity: identity, payload: .record(effective))
        }
        for (key, deletion) in state.tombstones {
            let value = CloudValue(
                identity: deletion.identity,
                payload: .deleted(deletion.deletedAt)
            )
            if let current = result[key] {
                result[key] = Self.preferred(current, value)
            } else {
                result[key] = value
            }
        }
        return result
    }

    private static func preferred(
        _ lhs: CloudValue,
        _ rhs: CloudValue
    ) -> CloudValue {
        if lhs.timestamp != rhs.timestamp {
            return lhs.timestamp > rhs.timestamp ? lhs : rhs
        }
        if lhs.isDeletion != rhs.isDeletion {
            return lhs.isDeletion ? lhs : rhs
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
            remoteDeleted: remote.isDeletion,
            localTimestamp: local.timestamp,
            localDeleted: local.isDeletion
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

private final class CustomReadingCloudTransport {
    private static let recordType = "JKCustomReading"
    private static let schemaVersion: Int64 = 1
    private static let maximumBatchSize = 100

    private enum Field {
        static let schemaVersion = "schemaVersion"
        static let deleted = "deleted"
        static let character = "character"
        static let pronunciation = "pronunciation"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
        static let deletedAt = "deletedAt"

        static let encrypted = [
            character,
            pronunciation,
            createdAt,
            updatedAt,
            deletedAt,
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
                guard record.recordType == Self.recordType else {
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
            guard let self else { return }
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

            do {
                var decoded: [CustomReadingCloudSyncCoordinator.CloudValue] = []
                var cache: [String: CKRecord] = [:]
                for record in records {
                    let value = try Self.decode(record)
                    decoded.append(value)
                    cache[record.recordID.recordName] = record
                }
                cacheLock.lock()
                cachedRecords = cache
                cacheLock.unlock()
                completion(.success(decoded))
            } catch {
                completion(.failure(error))
            }
        }
        database.add(operation)
    }

    func save(
        _ values: [String: CustomReadingCloudSyncCoordinator.CloudValue],
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        do {
            let records = try values.values
                .sorted { $0.identity.recordName < $1.identity.recordName }
                .map(makeRecord)
            let batches = stride(from: 0, to: records.count, by: Self.maximumBatchSize)
                .map { start in
                    Array(records[start ..< min(start + Self.maximumBatchSize, records.count)])
                }
            saveBatches(batches, index: 0, completion: completion)
        } catch {
            completion(.failure(error))
        }
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
            guard let self, case let .success(record) = result else {
                return
            }
            cacheLock.lock()
            cachedRecords[recordID.recordName] = record
            cacheLock.unlock()
        }
        operation.modifyRecordsResultBlock = { [weak self] result in
            guard let self else { return }
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
    ) throws -> CKRecord {
        let recordName = value.identity.recordName
        cacheLock.lock()
        let cached = cachedRecords[recordName]
        cacheLock.unlock()
        let record = cached ?? CKRecord(
            recordType: Self.recordType,
            recordID: CKRecord.ID(recordName: recordName, zoneID: zoneID)
        )
        record[Field.schemaVersion] = NSNumber(value: Self.schemaVersion)
        record[Field.deleted] = NSNumber(value: value.isDeletion)
        for field in Field.encrypted {
            record.encryptedValues[field] = nil
        }
        record.encryptedValues[Field.character] = value.identity.character
        record.encryptedValues[Field.pronunciation] = value.identity.pronunciation
        switch value.payload {
        case let .record(customReading):
            record.encryptedValues[Field.createdAt] = NSNumber(
                value: milliseconds(customReading.createdAt)
            )
            record.encryptedValues[Field.updatedAt] = NSNumber(
                value: milliseconds(customReading.updatedAt)
            )
        case let .deleted(deletedAt):
            record.encryptedValues[Field.deletedAt] = NSNumber(
                value: milliseconds(deletedAt)
            )
        }
        return record
    }

    private static func decode(
        _ record: CKRecord
    ) throws -> CustomReadingCloudSyncCoordinator.CloudValue {
        guard record.recordType == recordType,
              integer(record[Field.schemaVersion]) == schemaVersion,
              let character: String = record.encryptedValues[Field.character],
              let pronunciation: String = record.encryptedValues[Field.pronunciation]
        else {
            throw CustomReadingCloudError.invalidRecord
        }
        let identity = try CustomReadingCloudSyncCoordinator.Identity(
            character: character,
            pronunciation: pronunciation
        )
        guard identity.recordName == record.recordID.recordName else {
            throw CustomReadingCloudError.invalidRecord
        }
        let deleted = integer(record[Field.deleted]) == 1
        if deleted {
            guard let rawDeletedAt = integer(
                record.encryptedValues[Field.deletedAt]
            ) else {
                throw CustomReadingCloudError.invalidRecord
            }
            return CustomReadingCloudSyncCoordinator.CloudValue(
                identity: identity,
                payload: .deleted(date(milliseconds: rawDeletedAt))
            )
        }
        guard let rawCreatedAt = integer(
                  record.encryptedValues[Field.createdAt]
              ),
              let rawUpdatedAt = integer(
                  record.encryptedValues[Field.updatedAt]
              ) else {
            throw CustomReadingCloudError.invalidRecord
        }
        return CustomReadingCloudSyncCoordinator.CloudValue(
            identity: identity,
            payload: .record(
                CustomReadingRecord(
                    character: identity.character,
                    pronunciation: identity.pronunciation,
                    createdAt: date(milliseconds: rawCreatedAt),
                    updatedAt: date(milliseconds: rawUpdatedAt)
                )
            )
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

    private func milliseconds(_ date: Date) -> Int64 {
        Self.milliseconds(date)
    }

    private static func milliseconds(_ date: Date) -> Int64 {
        let value = date.timeIntervalSince1970 * 1_000
        if value >= Double(Int64.max) { return Int64.max }
        if value <= Double(Int64.min) { return Int64.min }
        return Int64(value.rounded(.towardZero))
    }

    private static func date(milliseconds value: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(value) / 1_000)
    }

    private static func integer(_ value: CKRecordValue?) -> Int64? {
        if let number = value as? NSNumber {
            return number.int64Value
        }
        return nil
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
