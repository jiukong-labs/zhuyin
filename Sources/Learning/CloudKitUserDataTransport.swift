import CloudKit
import Foundation
import os

protocol CloudUserDataTransporting: AnyObject {
    func fetchAll(
        completion: @escaping (Result<[CloudUserDataRecord], Error>) -> Void
    )

    func save(
        _ records: [CloudUserDataRecord],
        completion: @escaping (Result<Void, Error>) -> Void
    )
}

enum CloudKitUserDataTransportError: LocalizedError {
    case noAccount
    case accountRestricted
    case accountTemporarilyUnavailable
    case accountStatusUnknown
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
        static let selectionCount = "selectionCount"
        static let lastSelectedAt = "lastSelectedAt"
        static let createdAt = "createdAt"
        static let lastUsedAt = "lastUsedAt"
        static let pinned = "pinned"

        static let encrypted = [
            text,
            readings,
            selectionCount,
            lastSelectedAt,
            createdAt,
            lastUsedAt,
            pinned,
        ]
    }

    private static let recordSchemaVersion: Int64 = 1
    private static let maximumBatchSize = 100

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
        completion: @escaping (Result<[CloudUserDataRecord], Error>) -> Void
    ) {
        container.accountStatus { [weak self] status, error in
            guard let self else {
                return
            }
            if let error {
                completion(.failure(error))
                return
            }
            guard status == .available else {
                completion(.failure(Self.error(for: status)))
                return
            }
            ensureZone { result in
                switch result {
                case .success:
                    self.fetchZoneChanges(completion: completion)
                case let .failure(error):
                    completion(.failure(error))
                }
            }
        }
    }

    func save(
        _ records: [CloudUserDataRecord],
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard !records.isEmpty else {
            completion(.success(()))
            return
        }

        do {
            let cloudRecords = try records.map(makeCloudRecord)
            saveBatches(
                Array(cloudRecords.chunked(maximumCount: Self.maximumBatchSize)),
                at: 0,
                completion: completion
            )
        } catch {
            completion(.failure(error))
        }
    }

    private func ensureZone(
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        database.fetch(withRecordZoneIDs: [zoneID]) { [weak self] result in
            guard let self else {
                return
            }
            switch result {
            case let .failure(error):
                if Self.isMissingZone(error) {
                    createZone(completion: completion)
                } else {
                    completion(.failure(error))
                }
            case let .success(results):
                guard let zoneResult = results[zoneID] else {
                    completion(.failure(
                        CloudKitUserDataTransportError.missingZoneResult
                    ))
                    return
                }
                switch zoneResult {
                case .success:
                    completion(.success(()))
                case let .failure(error):
                    if Self.isMissingZone(error) {
                        createZone(completion: completion)
                    } else {
                        completion(.failure(error))
                    }
                }
            }
        }
    }

    private func createZone(
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let zone = CKRecordZone(zoneID: zoneID)
        database.modifyRecordZones(saving: [zone], deleting: []) { result in
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case let .success(results):
                guard let zoneResult = results.saveResults[self.zoneID] else {
                    completion(.failure(
                        CloudKitUserDataTransportError.missingZoneResult
                    ))
                    return
                }
                switch zoneResult {
                case .success:
                    completion(.success(()))
                case let .failure(error):
                    completion(.failure(error))
                }
            }
        }
    }

    private func fetchZoneChanges(
        completion: @escaping (Result<[CloudUserDataRecord], Error>) -> Void
    ) {
        let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        configuration.previousServerChangeToken = nil
        let operation = CKFetchRecordZoneChangesOperation(
            recordZoneIDs: [zoneID],
            configurationsByRecordZoneID: [zoneID: configuration]
        )
        operation.fetchAllChanges = true
        operation.qualityOfService = .utility

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
        operation.fetchRecordZoneChangesResultBlock = { [weak self] result in
            guard let self else {
                return
            }
            if case let .failure(error) = result {
                completion(.failure(error))
                return
            }
            resultLock.lock()
            let recordError = zoneError ?? firstRecordError
            let fetchedRecords = Array(fetched.values)
            resultLock.unlock()
            if let error = recordError {
                completion(.failure(error))
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
            cacheLock.lock()
            cachedRecords = validCloudRecords
            cacheLock.unlock()
            completion(.success(decoded))
        }
        database.add(operation)
    }

    private func saveBatches(
        _ batches: [[CKRecord]],
        at index: Int,
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
        operation.savePolicy = .ifServerRecordUnchanged
        operation.isAtomic = false
        operation.qualityOfService = .utility
        operation.perRecordSaveBlock = { [weak self] recordID, result in
            guard let self, case let .success(record) = result else {
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
                saveBatches(batches, at: index + 1, completion: completion)
            }
        }
        database.add(operation)
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
            identity = try CloudUserDataIdentity(
                phrase: text,
                readings: readings
            )
        }
        guard record.recordID.recordName == identity.recordName else {
            throw CloudUserDataModelError.invalidRecordName
        }

        if boolean(record[Field.deleted]) == true {
            return try .tombstone(identity)
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
                        selectionCount: selectionCount,
                        createdAt: createdAt,
                        lastUsedAt: integer(
                            record.encryptedValues[Field.lastUsedAt]
                        ),
                        pinned: pinned
                    )
                )
            )
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
