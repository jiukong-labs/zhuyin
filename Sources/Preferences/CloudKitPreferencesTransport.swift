import CloudKit
import Foundation
import os

protocol CloudPreferencesTransporting: AnyObject {
    @discardableResult
    func fetchAll(
        urgency: CloudUserDataSyncUrgency,
        completion: @escaping (Result<CloudPreferencesSnapshot, Error>) -> Void
    ) -> CloudUserDataTransfer

    @discardableResult
    func save(
        _ records: [CloudPreferenceRecord],
        urgency: CloudUserDataSyncUrgency,
        completion: @escaping (Result<Void, Error>) -> Void
    ) -> CloudUserDataTransfer
}

/// A separate private custom zone and record type keep appearance preferences
/// independent from learned characters and phrases. One record per setting
/// also preserves fields unknown to older releases.
final class CloudKitPreferencesTransport: CloudPreferencesTransporting {
    static let zoneName = "JiukongPreferences"
    static let recordType = "JKPreference"

    private enum Field {
        static let schemaVersion = "schemaVersion"
        static let key = "preferenceKey"
        static let modifiedAt = "modifiedAt"
        static let revision = "revision"
        static let value = "value"
    }

    private static let requestTimeout: TimeInterval = 60
    private static let resourceTimeout: TimeInterval = 300
    private static let logger = Logger(
        subsystem: "tw.idv.jiukong.inputmethod.zhuyin",
        category: "CloudPreferences"
    )

    private let container: CKContainer
    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID
    private let cacheLock = NSLock()
    private var cachedRecords: [CloudPreferenceField: CKRecord] = [:]

    init(
        container: CKContainer = CKContainer(
            identifier: CloudKitUserDataTransport.containerIdentifier
        )
    ) {
        self.container = container
        database = container.privateCloudDatabase
        zoneID = CKRecordZone.ID(
            zoneName: Self.zoneName,
            ownerName: CKCurrentUserDefaultName
        )
    }

    func fetchAll(
        urgency: CloudUserDataSyncUrgency,
        completion: @escaping (Result<CloudPreferencesSnapshot, Error>) -> Void
    ) -> CloudUserDataTransfer {
        let transfer = CloudPreferencesTransfer()
        container.accountStatus { [weak self, weak transfer] status, error in
            guard let self, let transfer, transfer.isActive else {
                return
            }
            if let error {
                transfer.deliver(.failure(error), to: completion)
                return
            }
            guard status == .available else {
                transfer.deliver(
                    .failure(Self.error(for: status)),
                    to: completion
                )
                return
            }
            container.fetchUserRecordID {
                [weak self, weak transfer] recordID, error in
                guard let self, let transfer, transfer.isActive else {
                    return
                }
                if let error {
                    transfer.deliver(.failure(error), to: completion)
                    return
                }
                guard let recordID else {
                    transfer.deliver(
                        .failure(
                            CloudKitUserDataTransportError
                                .missingAccountIdentifier
                        ),
                        to: completion
                    )
                    return
                }
                ensureZone(urgency: urgency, transfer: transfer) { result in
                    guard transfer.isActive else {
                        return
                    }
                    switch result {
                    case .success:
                        self.fetchZoneChanges(
                            urgency: urgency,
                            transfer: transfer,
                            accountIdentifier: CloudAccountIdentifier(
                                stableIdentifier: recordID.recordName
                            ),
                            completion: completion
                        )
                    case let .failure(error):
                        transfer.deliver(.failure(error), to: completion)
                    }
                }
            }
        }
        return transfer
    }

    func save(
        _ records: [CloudPreferenceRecord],
        urgency: CloudUserDataSyncUrgency,
        completion: @escaping (Result<Void, Error>) -> Void
    ) -> CloudUserDataTransfer {
        let transfer = CloudPreferencesTransfer()
        guard !records.isEmpty else {
            transfer.deliver(.success(()), to: completion)
            return transfer
        }

        let cloudRecords = records.map(makeCloudRecord)
        let operation = CKModifyRecordsOperation(
            recordsToSave: cloudRecords,
            recordIDsToDelete: nil
        )
        operation.savePolicy = .ifServerRecordUnchanged
        operation.isAtomic = false
        configure(operation, urgency: urgency)
        operation.perRecordSaveBlock = {
            [weak self, weak transfer] _, result in
            guard let self,
                  let transfer,
                  transfer.isActive,
                  case let .success(record) = result,
                  let decoded = Self.decode(record) else {
                return
            }
            cacheLock.lock()
            cachedRecords[decoded.field] = record
            cacheLock.unlock()
        }
        operation.modifyRecordsResultBlock = { [weak transfer] result in
            guard let transfer, transfer.isActive else {
                return
            }
            transfer.deliver(result.map { _ in () }, to: completion)
        }
        guard transfer.track(operation) else {
            return transfer
        }
        database.add(operation)
        return transfer
    }

    private func ensureZone(
        urgency: CloudUserDataSyncUrgency,
        transfer: CloudPreferencesTransfer,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let operation = CKFetchRecordZonesOperation(recordZoneIDs: [zoneID])
        configure(operation, urgency: urgency)
        let lock = NSLock()
        var zoneResult: Result<CKRecordZone, Error>?
        operation.perRecordZoneResultBlock = { recordZoneID, result in
            guard recordZoneID == self.zoneID else {
                return
            }
            lock.lock()
            zoneResult = result
            lock.unlock()
        }
        operation.fetchRecordZonesResultBlock = {
            [weak self, weak transfer] result in
            guard let self, let transfer, transfer.isActive else {
                return
            }
            lock.lock()
            let fetched = zoneResult
            lock.unlock()
            if let fetched {
                switch fetched {
                case .success:
                    completion(.success(()))
                case let .failure(error):
                    if Self.isMissingZone(error) {
                        createZone(
                            urgency: urgency,
                            transfer: transfer,
                            completion: completion
                        )
                    } else {
                        completion(.failure(error))
                    }
                }
                return
            }
            switch result {
            case let .failure(error) where Self.isMissingZone(error):
                createZone(
                    urgency: urgency,
                    transfer: transfer,
                    completion: completion
                )
            case let .failure(error):
                completion(.failure(error))
            case .success:
                completion(.failure(
                    CloudKitUserDataTransportError.missingZoneResult
                ))
            }
        }
        guard transfer.track(operation) else {
            return
        }
        database.add(operation)
    }

    private func createZone(
        urgency: CloudUserDataSyncUrgency,
        transfer: CloudPreferencesTransfer,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let operation = CKModifyRecordZonesOperation(
            recordZonesToSave: [CKRecordZone(zoneID: zoneID)],
            recordZoneIDsToDelete: nil
        )
        configure(operation, urgency: urgency)
        let lock = NSLock()
        var zoneResult: Result<CKRecordZone, Error>?
        operation.perRecordZoneSaveBlock = { recordZoneID, result in
            guard recordZoneID == self.zoneID else {
                return
            }
            lock.lock()
            zoneResult = result
            lock.unlock()
        }
        operation.modifyRecordZonesResultBlock = { [weak transfer] result in
            guard let transfer, transfer.isActive else {
                return
            }
            lock.lock()
            let saved = zoneResult
            lock.unlock()
            if let saved {
                completion(saved.map { _ in () })
                return
            }
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case .success:
                completion(.failure(
                    CloudKitUserDataTransportError.missingZoneResult
                ))
            }
        }
        guard transfer.track(operation) else {
            return
        }
        database.add(operation)
    }

    private func fetchZoneChanges(
        urgency: CloudUserDataSyncUrgency,
        transfer: CloudPreferencesTransfer,
        accountIdentifier: CloudAccountIdentifier,
        completion: @escaping (Result<CloudPreferencesSnapshot, Error>) -> Void
    ) {
        let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        configuration.previousServerChangeToken = nil
        let operation = CKFetchRecordZoneChangesOperation(
            recordZoneIDs: [zoneID],
            configurationsByRecordZoneID: [zoneID: configuration]
        )
        operation.fetchAllChanges = true
        configure(operation, urgency: urgency)

        let lock = NSLock()
        var fetched: [CKRecord.ID: CKRecord] = [:]
        var firstError: Error?
        operation.recordWasChangedBlock = { recordID, result in
            lock.lock()
            defer { lock.unlock() }
            switch result {
            case let .success(record):
                if record.recordType == Self.recordType {
                    fetched[recordID] = record
                }
            case let .failure(error):
                firstError = firstError ?? error
            }
        }
        operation.recordWithIDWasDeletedBlock = { recordID, _ in
            lock.lock()
            fetched.removeValue(forKey: recordID)
            lock.unlock()
        }
        operation.recordZoneFetchResultBlock = { _, result in
            if case let .failure(error) = result {
                lock.lock()
                firstError = firstError ?? error
                lock.unlock()
            }
        }
        operation.fetchRecordZoneChangesResultBlock = {
            [weak self, weak transfer] result in
            guard let self, let transfer, transfer.isActive else {
                return
            }
            if case let .failure(error) = result {
                transfer.deliver(.failure(error), to: completion)
                return
            }
            lock.lock()
            let records = Array(fetched.values)
            let error = firstError
            lock.unlock()
            if let error {
                transfer.deliver(.failure(error), to: completion)
                return
            }

            var decoded: [CloudPreferenceRecord] = []
            var cache: [CloudPreferenceField: CKRecord] = [:]
            for record in records {
                guard let value = Self.decode(record) else {
                    Self.logger.error(
                        "Ignoring one malformed iCloud preference record."
                    )
                    continue
                }
                decoded.append(value)
                cache[value.field] = record
            }
            cacheLock.lock()
            cachedRecords = cache
            cacheLock.unlock()
            transfer.deliver(
                .success(
                    CloudPreferencesSnapshot(
                        accountIdentifier: accountIdentifier,
                        records: decoded
                    )
                ),
                to: completion
            )
        }
        guard transfer.track(operation) else {
            return
        }
        database.add(operation)
    }

    private func configure(
        _ operation: CKOperation,
        urgency: CloudUserDataSyncUrgency
    ) {
        let configuration = CKOperation.Configuration()
        configuration.qualityOfService = urgency.qualityOfService
        configuration.allowsCellularAccess = true
        configuration.timeoutIntervalForRequest = Self.requestTimeout
        configuration.timeoutIntervalForResource = Self.resourceTimeout
        operation.configuration = configuration
    }

    private func makeCloudRecord(_ value: CloudPreferenceRecord) -> CKRecord {
        cacheLock.lock()
        let cached = cachedRecords[value.field]
        cacheLock.unlock()
        let record = cached ?? CKRecord(
            recordType: Self.recordType,
            recordID: CKRecord.ID(
                recordName: "setting-\(value.field.rawValue)",
                zoneID: zoneID
            )
        )
        record[Field.schemaVersion] = NSNumber(value: value.schemaVersion)
        record[Field.key] = value.field.rawValue
        record[Field.modifiedAt] = value.modifiedAt
        record[Field.revision] = NSNumber(value: value.revision)
        record.encryptedValues[Field.value] = value.value
        return record
    }

    private static func decode(_ record: CKRecord) -> CloudPreferenceRecord? {
        guard record.recordType == recordType,
              let schema = (record[Field.schemaVersion] as? NSNumber)?.intValue,
              let rawKey: String = record[Field.key],
              let field = CloudPreferenceField(rawValue: rawKey),
              record.recordID.recordName == "setting-\(rawKey)",
              let modifiedAt: Date = record[Field.modifiedAt],
              let revision = (record[Field.revision] as? NSNumber)?.int64Value,
              let value: String = record.encryptedValues[Field.value] else {
            return nil
        }
        let decoded = CloudPreferenceRecord(
            field: field,
            value: value,
            modifiedAt: modifiedAt,
            revision: revision,
            schemaVersion: schema
        )
        return decoded.isValid ? decoded : nil
    }

    private static func error(
        for status: CKAccountStatus
    ) -> CloudKitUserDataTransportError {
        switch status {
        case .noAccount:
            return .noAccount
        case .restricted:
            return .accountRestricted
        case .temporarilyUnavailable:
            return .accountTemporarilyUnavailable
        case .couldNotDetermine, .available:
            return .accountStatusUnknown
        @unknown default:
            return .accountStatusUnknown
        }
    }

    private static func isMissingZone(_ error: Error) -> Bool {
        (error as? CKError)?.code == .zoneNotFound
    }
}

private final class CloudPreferencesTransfer: CloudUserDataTransfer {
    private let lock = NSLock()
    private var operations: [CKOperation] = []
    private var cancelled = false
    private var finished = false

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !cancelled && !finished
    }

    func track(_ operation: CKOperation) -> Bool {
        lock.lock()
        guard !cancelled, !finished else {
            lock.unlock()
            operation.cancel()
            return false
        }
        operations.append(operation)
        lock.unlock()
        return true
    }

    func deliver<Value>(
        _ result: Result<Value, Error>,
        to completion: (Result<Value, Error>) -> Void
    ) {
        lock.lock()
        guard !cancelled, !finished else {
            lock.unlock()
            return
        }
        finished = true
        operations.removeAll()
        lock.unlock()
        completion(result)
    }

    func cancel() {
        lock.lock()
        guard !cancelled, !finished else {
            lock.unlock()
            return
        }
        cancelled = true
        let pending = operations
        operations.removeAll()
        lock.unlock()
        pending.forEach { $0.cancel() }
    }
}
