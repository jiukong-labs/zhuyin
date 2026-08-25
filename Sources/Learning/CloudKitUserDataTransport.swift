import CloudKit
import Foundation

private final class CloudKitUserDataOperation: CloudUserDataOperation {
    private let lock = NSLock()
    private var operations: [CKOperation] = []
    private var cancellationHandler: (() -> Void)?
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    init(cancellationHandler: (() -> Void)? = nil) {
        self.cancellationHandler = cancellationHandler
    }

    @discardableResult
    func add(_ operation: CKOperation) -> Bool {
        lock.lock()
        if cancelled {
            lock.unlock()
            operation.cancel()
            return false
        }
        operations.append(operation)
        lock.unlock()
        return true
    }

    func cancel() {
        lock.lock()
        guard !cancelled else {
            lock.unlock()
            return
        }
        cancelled = true
        let activeOperations = operations
        operations.removeAll()
        let handler = cancellationHandler
        cancellationHandler = nil
        lock.unlock()

        activeOperations.forEach { $0.cancel() }
        handler?()
    }
}

/// Stores one versioned snapshot in the signed-in user's private database.
///
/// A deterministic record ID gives reinstallations and additional Macs the
/// same rendezvous point. The payload is an asset rather than a Data field so
/// a large personal phrase collection doesn't approach CloudKit's record-size
/// limit.
final class CloudKitUserDataTransport: CloudUserDataTransport {
    static let containerIdentifier =
        "iCloud.tw.idv.jiukong.inputmethod.zhuyin"

    private enum Schema {
        static let recordType = "JiukongUserLearningSnapshot"
        static let recordName = "current"
        static let payload = "payload"
        static let format = "format"
        static let version = "version"
        static let exportedAt = "exportedAt"
    }

    private let container: CKContainer
    private let database: CKDatabase
    private let fileManager: FileManager
    private let recordID = CKRecord.ID(recordName: Schema.recordName)

    init(
        containerIdentifier: String = CloudKitUserDataTransport.containerIdentifier,
        fileManager: FileManager = .default
    ) {
        let container = CKContainer(identifier: containerIdentifier)
        self.container = container
        database = container.privateCloudDatabase
        self.fileManager = fileManager
    }

    func accountAvailability(
        completion: @escaping (Result<CloudAccountAvailability, Error>) -> Void
    ) {
        container.accountStatus { status, error in
            if let error {
                completion(.failure(error))
                return
            }

            switch status {
            case .available:
                completion(.success(.available))
            case .noAccount:
                completion(.success(.noAccount))
            case .restricted:
                completion(.success(.restricted))
            case .couldNotDetermine, .temporarilyUnavailable:
                completion(.success(.couldNotDetermine))
            @unknown default:
                completion(.success(.couldNotDetermine))
            }
        }
    }

    @discardableResult
    func fetchArchive(
        completion: @escaping (Result<UserDataArchive?, Error>) -> Void
    ) -> (any CloudUserDataOperation)? {
        let operationGroup = CloudKitUserDataOperation()
        fetchRecord(operationGroup: operationGroup) { result in
            guard !operationGroup.isCancelled else {
                return
            }
            switch result {
            case let .success(record):
                guard let record else {
                    completion(.success(nil))
                    return
                }
                completion(Self.archive(from: record))
            case let .failure(error):
                completion(.failure(error))
            }
        }
        return operationGroup
    }

    @discardableResult
    func saveArchive(
        _ archive: UserDataArchive,
        completion: @escaping (Result<Void, Error>) -> Void
    ) -> (any CloudUserDataOperation)? {
        let temporaryDirectory: URL
        let payloadURL: URL
        do {
            temporaryDirectory = fileManager.temporaryDirectory
                .appendingPathComponent(
                    "JiukongCloudSync-\(UUID().uuidString)",
                    isDirectory: true
                )
            try fileManager.createDirectory(
                at: temporaryDirectory,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            payloadURL = temporaryDirectory.appendingPathComponent(
                "UserData.json",
                isDirectory: false
            )
            try archive.encoded().write(to: payloadURL, options: .atomic)
        } catch {
            completion(.failure(error))
            return nil
        }

        let operationGroup = CloudKitUserDataOperation { [fileManager] in
            try? fileManager.removeItem(at: temporaryDirectory)
        }
        fetchRecord(operationGroup: operationGroup) {
            [database, fileManager, recordID] result in
            guard !operationGroup.isCancelled else {
                return
            }
            let record: CKRecord
            switch result {
            case let .success(existing):
                record = existing ?? CKRecord(
                    recordType: Schema.recordType,
                    recordID: recordID
                )
            case let .failure(error):
                try? fileManager.removeItem(at: temporaryDirectory)
                completion(.failure(error))
                return
            }

            record[Schema.payload] = CKAsset(fileURL: payloadURL)
            record[Schema.format] = archive.format as CKRecordValue
            record[Schema.version] = NSNumber(value: archive.version)
            record[Schema.exportedAt] = Date(
                timeIntervalSince1970: Double(archive.exportedAt) / 1_000
            ) as CKRecordValue

            let saveOperation = CKModifyRecordsOperation(
                recordsToSave: [record],
                recordIDsToDelete: nil
            )
            saveOperation.savePolicy = .ifServerRecordUnchanged
            saveOperation.modifyRecordsResultBlock = { result in
                try? fileManager.removeItem(at: temporaryDirectory)
                guard !operationGroup.isCancelled else {
                    return
                }
                switch result {
                case .success:
                    completion(.success(()))
                case let .failure(error):
                    completion(.failure(Self.normalized(error)))
                }
            }
            if operationGroup.add(saveOperation) {
                database.add(saveOperation)
            }
        }
        return operationGroup
    }

    private func fetchRecord(
        operationGroup: CloudKitUserDataOperation,
        completion: @escaping (Result<CKRecord?, Error>) -> Void
    ) {
        let fetchOperation = CKFetchRecordsOperation(recordIDs: [recordID])
        let resultLock = NSLock()
        var fetchedRecord: CKRecord?
        fetchOperation.perRecordResultBlock = { _, result in
            guard case let .success(record) = result else {
                return
            }
            resultLock.lock()
            fetchedRecord = record
            resultLock.unlock()
        }
        fetchOperation.fetchRecordsResultBlock = { result in
            guard !operationGroup.isCancelled else {
                return
            }
            switch result {
            case .success:
                resultLock.lock()
                let record = fetchedRecord
                resultLock.unlock()
                completion(.success(record))
            case let .failure(error):
                if Self.isUnknownItem(error) {
                    completion(.success(nil))
                } else {
                    completion(.failure(error))
                }
            }
        }
        if operationGroup.add(fetchOperation) {
            database.add(fetchOperation)
        }
    }

    private static func archive(
        from record: CKRecord
    ) -> Result<UserDataArchive?, Error> {
        guard let asset = record[Schema.payload] as? CKAsset,
              let fileURL = asset.fileURL else {
            return .failure(CloudUserDataTransportError.missingPayload)
        }

        do {
            let (archive, issues) = try UserDataArchive.decoded(
                from: Data(contentsOf: fileURL)
            )
            guard issues.isEmpty else {
                return .failure(CloudUserDataTransportError.invalidPayload)
            }
            return .success(archive)
        } catch {
            return .failure(CloudUserDataTransportError.invalidPayload)
        }
    }

    private static func isUnknownItem(_ error: Error) -> Bool {
        (error as? CKError)?.code == .unknownItem
    }

    private static func normalized(_ error: Error) -> Error {
        guard let cloudError = error as? CKError else {
            return error
        }
        if cloudError.code == .serverRecordChanged {
            return CloudUserDataTransportError.conflict
        }
        return cloudError
    }
}
