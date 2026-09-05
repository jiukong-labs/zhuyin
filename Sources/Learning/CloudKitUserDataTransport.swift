import CloudKit
import Foundation
import os

protocol CloudUserDataTransfer: AnyObject {
    func cancel()
}

enum CloudUserDataSyncUrgency: Equatable {
    case automatic
    case userInitiated

    var qualityOfService: QualityOfService {
        switch self {
        case .automatic:
            return .utility
        case .userInitiated:
            return .userInitiated
        }
    }
}

protocol CloudUserDataTransporting: AnyObject {
    @discardableResult
    func fetchAll(
        urgency: CloudUserDataSyncUrgency,
        completion: @escaping (Result<CloudUserDataSnapshot, Error>) -> Void
    ) -> CloudUserDataTransfer

    @discardableResult
    func save(
        _ records: [CloudUserDataRecord],
        urgency: CloudUserDataSyncUrgency,
        completion: @escaping (Result<Void, Error>) -> Void
    ) -> CloudUserDataTransfer
}

enum CloudKitUserDataTransportError: LocalizedError {
    case noAccount
    case accountRestricted
    case accountTemporarilyUnavailable
    case accountStatusUnknown
    case missingAccountIdentifier
    case missingZoneResult

    var errorDescription: String? {
        switch self {
        case .noAccount:
            return "這台 Mac 尚未登入 iCloud。"
        case .accountRestricted:
            return "這個 iCloud 帳號目前不允許使用 CloudKit。"
        case .accountTemporarilyUnavailable:
            return "iCloud 帳號目前暫時無法使用。"
        case .accountStatusUnknown:
            return "目前無法確認 iCloud 帳號狀態。"
        case .missingAccountIdentifier:
            return "iCloud 沒有回傳目前帳號的識別資料。"
        case .missingZoneResult:
            return "iCloud 沒有回傳久空同步區的建立結果。"
        }
    }
}

/// CloudKit private-database transport for normalized learning records.
///
/// The custom zone is fetched from the beginning on each synchronization. A
/// personal input-method dictionary is small, and this keeps restoration and
/// tombstone handling deterministic without coupling CloudKit change tokens to
/// the local SQLite schema.
final class CloudKitUserDataTransport: CloudUserDataTransporting {
    static let containerIdentifier =
        "iCloud.tw.idv.jiukong.inputmethod.zhuyin"
    static let zoneName = "JiukongUserLearning"
    static let recordType = "JKUserLearning"

    private enum Field {
        static let schemaVersion = "schemaVersion"
        static let kind = "kind"
        static let deleted = "deleted"
        static let text = "text"
        static let readings = "readings"
        static let unitPattern = "unitPattern"
        static let selectionCount = "selectionCount"
        static let lastSelectedAt = "lastSelectedAt"
        static let createdAt = "createdAt"
        static let lastUsedAt = "lastUsedAt"
        static let pinned = "pinned"
        static let suppressedAt = "suppressedAt"

        static let encrypted = [
            text,
            readings,
            unitPattern,
            selectionCount,
            lastSelectedAt,
            createdAt,
            lastUsedAt,
            pinned,
            suppressedAt,
        ]
    }

    private static let recordSchemaVersion: Int64 = 1
    private static let maximumBatchSize = 100
    private static let requestTimeout: TimeInterval = 60
    private static let resourceTimeout: TimeInterval = 300

    private static let logger = Logger(
        subsystem: "tw.idv.jiukong.inputmethod.zhuyin",
        category: "CloudUserData"
    )

    private let container: CKContainer
    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID
    private let cacheLock = NSLock()
    private var cachedRecords: [String: CKRecord] = [:]

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
        completion: @escaping (Result<CloudUserDataSnapshot, Error>) -> Void
    ) -> CloudUserDataTransfer {
        let transfer = CloudKitUserDataTransfer()
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
            self.container.fetchUserRecordID {
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
                let accountIdentifier = CloudAccountIdentifier(
                    stableIdentifier: recordID.recordName
                )
                self.ensureZone(
                    urgency: urgency,
                    transfer: transfer
                ) { result in
                    guard transfer.isActive else {
                        return
                    }
                    switch result {
                    case .success:
                        self.fetchZoneChanges(
                            urgency: urgency,
                            transfer: transfer,
                            accountIdentifier: accountIdentifier,
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
        _ records: [CloudUserDataRecord],
        urgency: CloudUserDataSyncUrgency,
        completion: @escaping (Result<Void, Error>) -> Void
    ) -> CloudUserDataTransfer {
        let transfer = CloudKitUserDataTransfer()
        guard !records.isEmpty else {
            transfer.deliver(.success(()), to: completion)
            return transfer
        }

        do {
            let cloudRecords = try records.map(makeCloudRecord)
            saveBatches(
                Array(cloudRecords.chunked(maximumCount: Self.maximumBatchSize)),
                at: 0,
                urgency: urgency,
                transfer: transfer,
                completion: completion
            )
        } catch {
            transfer.deliver(.failure(error), to: completion)
        }
        return transfer
    }

    private func ensureZone(
        urgency: CloudUserDataSyncUrgency,
        transfer: CloudKitUserDataTransfer,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let operation = CKFetchRecordZonesOperation(
            recordZoneIDs: [zoneID]
        )
        configure(operation, urgency: urgency)

        let resultLock = NSLock()
        var fetchedZoneResult: Result<CKRecordZone, Error>?
        operation.perRecordZoneResultBlock = { recordZoneID, result in
            guard recordZoneID == self.zoneID else {
                return
            }
            resultLock.lock()
            fetchedZoneResult = result
            resultLock.unlock()
        }
        operation.fetchRecordZonesResultBlock = {
            [weak self, weak transfer] operationResult in
            guard let self, let transfer, transfer.isActive else {
                return
            }

            resultLock.lock()
            let zoneResult = fetchedZoneResult
            resultLock.unlock()
            if let zoneResult {
                switch zoneResult {
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

            switch operationResult {
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
        transfer: CloudKitUserDataTransfer,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let zone = CKRecordZone(zoneID: zoneID)
        let operation = CKModifyRecordZonesOperation(
            recordZonesToSave: [zone],
            recordZoneIDsToDelete: nil
        )
        configure(operation, urgency: urgency)

        let resultLock = NSLock()
        var savedZoneResult: Result<CKRecordZone, Error>?
        operation.perRecordZoneSaveBlock = { recordZoneID, result in
            guard recordZoneID == self.zoneID else {
                return
            }
            resultLock.lock()
            savedZoneResult = result
            resultLock.unlock()
        }
        operation.modifyRecordZonesResultBlock = {
            [weak transfer] operationResult in
            guard let transfer, transfer.isActive else {
                return
            }

            resultLock.lock()
            let zoneResult = savedZoneResult
            resultLock.unlock()
            if let zoneResult {
                completion(zoneResult.map { _ in () })
                return
            }

            switch operationResult {
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
        transfer: CloudKitUserDataTransfer,
        accountIdentifier: CloudAccountIdentifier,
        completion: @escaping (Result<CloudUserDataSnapshot, Error>) -> Void
    ) {
        let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        configuration.previousServerChangeToken = nil
        let operation = CKFetchRecordZoneChangesOperation(
            recordZoneIDs: [zoneID],
            configurationsByRecordZoneID: [zoneID: configuration]
        )
        operation.fetchAllChanges = true
        configure(operation, urgency: urgency)

        let resultLock = NSLock()
        var fetched: [String: CKRecord] = [:]
        var firstRecordError: Error?
        var zoneError: Error?

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
                if firstRecordError == nil {
                    firstRecordError = error
                }
            }
        }
        operation.recordWithIDWasDeletedBlock = { recordID, _ in
            resultLock.lock()
            fetched.removeValue(forKey: recordID.recordName)
            resultLock.unlock()
        }
        operation.recordZoneFetchResultBlock = { _, result in
            if case let .failure(error) = result {
                resultLock.lock()
                zoneError = error
                resultLock.unlock()
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
            resultLock.lock()
            let recordError = zoneError ?? firstRecordError
            let fetchedRecords = Array(fetched.values)
            resultLock.unlock()
            if let error = recordError {
                transfer.deliver(.failure(error), to: completion)
                return
            }

            var decoded: [CloudUserDataRecord] = []
            var validCloudRecords: [String: CKRecord] = [:]
            for record in fetchedRecords {
                do {
                    let value = try Self.decode(record)
                    decoded.append(value)
                    validCloudRecords[record.recordID.recordName] = record
                } catch {
                    Self.logger.error(
                        "Ignoring one invalid iCloud learning record: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
            guard transfer.isActive else {
                return
            }
            cacheLock.lock()
            cachedRecords = validCloudRecords
            cacheLock.unlock()
            transfer.deliver(
                .success(
                    CloudUserDataSnapshot(
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

    private func saveBatches(
        _ batches: [[CKRecord]],
        at index: Int,
        urgency: CloudUserDataSyncUrgency,
        transfer: CloudKitUserDataTransfer,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard transfer.isActive else {
            return
        }
        guard batches.indices.contains(index) else {
            transfer.deliver(.success(()), to: completion)
            return
        }

        let operation = CKModifyRecordsOperation(
            recordsToSave: batches[index],
            recordIDsToDelete: nil
        )
        operation.savePolicy = .ifServerRecordUnchanged
        operation.isAtomic = false
        configure(operation, urgency: urgency)
        operation.perRecordSaveBlock = {
            [weak self, weak transfer] recordID, result in
            guard let self,
                  let transfer,
                  transfer.isActive,
                  case let .success(record) = result else {
                return
            }
            cacheLock.lock()
            cachedRecords[recordID.recordName] = record
            cacheLock.unlock()
        }
        operation.modifyRecordsResultBlock = {
            [weak self, weak transfer] result in
            guard let self, let transfer, transfer.isActive else {
                return
            }
            switch result {
            case let .failure(error):
                transfer.deliver(.failure(error), to: completion)
            case .success:
                saveBatches(
                    batches,
                    at: index + 1,
                    urgency: urgency,
                    transfer: transfer,
                    completion: completion
                )
            }
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

    private func makeCloudRecord(_ value: CloudUserDataRecord) throws -> CKRecord {
        let recordName = value.identity.recordName
        cacheLock.lock()
        let cached = cachedRecords[recordName]
        cacheLock.unlock()
        let record = cached ?? CKRecord(
            recordType: Self.recordType,
            recordID: CKRecord.ID(recordName: recordName, zoneID: zoneID)
        )

        record[Field.schemaVersion] = NSNumber(
            value: Self.recordSchemaVersion
        )
        record[Field.kind] = value.identity.kind.rawValue
        record[Field.deleted] = NSNumber(
            value: value.archive == nil
        )
        for key in Field.encrypted {
            record.encryptedValues[key] = nil
        }
        record.encryptedValues[Field.text] = value.identity.text
        record.encryptedValues[Field.readings] = value.identity.readings
        record.encryptedValues[Field.unitPattern] = value.identity
            .outputPattern?.rawValue

        switch value.payload {
        case let .character(character):
            record.encryptedValues[Field.selectionCount] = NSNumber(
                value: character.selectionCount
            )
            record.encryptedValues[Field.lastSelectedAt] = character
                .lastSelectedAt.map { NSNumber(value: $0) }
            record.encryptedValues[Field.pinned] = NSNumber(
                value: character.pinned
            )
        case let .phrase(phrase):
            record.encryptedValues[Field.selectionCount] = NSNumber(
                value: phrase.selectionCount
            )
            record.encryptedValues[Field.createdAt] = NSNumber(
                value: phrase.createdAt
            )
            record.encryptedValues[Field.lastUsedAt] = phrase.lastUsedAt.map {
                NSNumber(value: $0)
            }
            record.encryptedValues[Field.pinned] = NSNumber(
                value: phrase.pinned
            )
        case let .suppressedPhrase(suppression):
            record.encryptedValues[Field.suppressedAt] = NSNumber(
                value: suppression.suppressedAt
            )
        case .deleted:
            break
        }
        return record
    }

    private static func decode(_ record: CKRecord) throws -> CloudUserDataRecord {
        guard record.recordType == recordType,
              integer(record[Field.schemaVersion]) == recordSchemaVersion,
              let rawKind: String = record[Field.kind],
              let kind = CloudUserDataIdentity.Kind(rawValue: rawKind),
              let text: String = record.encryptedValues[Field.text],
              let readings: [String] = record.encryptedValues[Field.readings]
        else {
            throw CloudUserDataModelError.invalidPayload
        }

        let identity: CloudUserDataIdentity
        switch kind {
        case .character:
            guard readings.count == 1 else {
                throw CloudUserDataModelError.invalidCharacterIdentity
            }
            identity = try CloudUserDataIdentity(
                character: text,
                pronunciation: readings[0]
            )
        case .phrase:
            let rawPattern: String? = record.encryptedValues[Field.unitPattern]
            let outputPattern = rawPattern.flatMap(
                PhraseOutputPattern.init(rawValue:)
            ) ?? PhraseOutputPattern.inferred(
                from: text,
                readingCount: readings.count
            )
            guard let outputPattern else {
                throw CloudUserDataModelError.invalidPayload
            }
            identity = try CloudUserDataIdentity(
                phrase: text,
                readings: readings,
                outputPattern: outputPattern
            )
        case .suppressedPhrase:
            identity = try CloudUserDataIdentity(
                suppressedPhrase: text,
                readings: readings
            )
        }
        guard record.recordID.recordName == identity.recordName else {
            throw CloudUserDataModelError.invalidRecordName
        }

        if boolean(record[Field.deleted]) == true {
            return try .tombstone(identity)
        }

        if identity.kind == .suppressedPhrase {
            guard let suppressedAt = integer(
                record.encryptedValues[Field.suppressedAt]
            ) else {
                throw CloudUserDataModelError.invalidPayload
            }
            return try CloudUserDataRecord(
                identity: identity,
                payload: .suppressedPhrase(
                    ArchivedSuppressedPhrase(
                        phrase: identity.text,
                        readings: identity.readings,
                        suppressedAt: suppressedAt
                    )
                )
            )
        }

        guard let selectionCount = integer(
                  record.encryptedValues[Field.selectionCount]
              ),
              selectionCount >= 0,
              let pinned = boolean(record.encryptedValues[Field.pinned]) else {
            throw CloudUserDataModelError.invalidPayload
        }

        switch identity.kind {
        case .character:
            return try CloudUserDataRecord(
                identity: identity,
                payload: .character(
                    ArchivedCharacter(
                        character: identity.text,
                        pronunciation: identity.readings[0],
                        selectionCount: selectionCount,
                        lastSelectedAt: integer(
                            record.encryptedValues[Field.lastSelectedAt]
                        ),
                        pinned: pinned
                    )
                )
            )
        case .phrase:
            guard let createdAt = integer(
                record.encryptedValues[Field.createdAt]
            ) else {
                throw CloudUserDataModelError.invalidPayload
            }
            return try CloudUserDataRecord(
                identity: identity,
                payload: .phrase(
                    ArchivedPhrase(
                        phrase: identity.text,
                        readings: identity.readings,
                        unitPattern: identity.outputPattern?.rawValue,
                        selectionCount: selectionCount,
                        createdAt: createdAt,
                        lastUsedAt: integer(
                            record.encryptedValues[Field.lastUsedAt]
                        ),
                        pinned: pinned
                    )
                )
            )
        case .suppressedPhrase:
            throw CloudUserDataModelError.invalidPayload
        }
    }

    private static func integer(_ value: Any?) -> Int64? {
        (value as? NSNumber)?.int64Value
    }

    private static func boolean(_ value: Any?) -> Bool? {
        (value as? NSNumber)?.boolValue
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

private final class CloudKitUserDataTransfer: CloudUserDataTransfer {
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
        let operationsToCancel = operations
        operations.removeAll()
        lock.unlock()

        operationsToCancel.forEach { $0.cancel() }
    }
}

private extension Array {
    func chunked(maximumCount: Int) -> AnySequence<[Element]> {
        guard maximumCount > 0 else {
            return AnySequence([])
        }
        return AnySequence(
            sequence(state: startIndex) { index in
                guard index < endIndex else {
                    return nil
                }
                let next = Swift.min(index + maximumCount, endIndex)
                defer { index = next }
                return Array(self[index ..< next])
            }
        )
    }
}
