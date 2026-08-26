import Foundation

protocol CloudSyncStateStoring: AnyObject {
    func load() -> CloudSyncPersistedState
    func save(_ state: CloudSyncPersistedState) throws
}

final class FileCloudSyncStateStore: CloudSyncStateStoring {
    private let location: UserDataLocation
    private let fileManager: FileManager

    init(
        location: UserDataLocation,
        fileManager: FileManager = .default
    ) {
        self.location = location
        self.fileManager = fileManager
    }

    func load() -> CloudSyncPersistedState {
        guard let data = try? Data(contentsOf: location.cloudSyncStateURL),
              let decoded = try? JSONDecoder().decode(
                  CloudSyncPersistedState.self,
                  from: data
              ),
              let validated = decoded.validated() else {
            return CloudSyncPersistedState()
        }
        return validated
    }

    func save(_ state: CloudSyncPersistedState) throws {
        try location.prepareDirectory(fileManager: fileManager)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: location.cloudSyncStateURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: location.cloudSyncStateURL.path
        )
    }
}

final class MemoryCloudSyncStateStore: CloudSyncStateStoring {
    private let lock = NSLock()
    private var stored: CloudSyncPersistedState

    init(state: CloudSyncPersistedState = CloudSyncPersistedState()) {
        stored = state
    }

    func load() -> CloudSyncPersistedState {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func save(_ state: CloudSyncPersistedState) throws {
        lock.lock()
        stored = state
        lock.unlock()
    }
}
