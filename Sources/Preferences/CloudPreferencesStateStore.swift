import Foundation

protocol CloudPreferencesStateStoring: AnyObject {
    func load() -> CloudPreferencesPersistedState
    func save(_ state: CloudPreferencesPersistedState) throws
}

final class FileCloudPreferencesStateStore: CloudPreferencesStateStoring {
    private let location: UserDataLocation
    private let fileManager: FileManager

    init(
        location: UserDataLocation,
        fileManager: FileManager = .default
    ) {
        self.location = location
        self.fileManager = fileManager
    }

    func load() -> CloudPreferencesPersistedState {
        guard let data = try? Data(
                  contentsOf: location.cloudPreferencesStateURL
              ),
              let decoded = try? JSONDecoder().decode(
                  CloudPreferencesPersistedState.self,
                  from: data
              ),
              let valid = decoded.validated() else {
            return CloudPreferencesPersistedState()
        }
        return valid
    }

    func save(_ state: CloudPreferencesPersistedState) throws {
        try location.prepareDirectory(fileManager: fileManager)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: location.cloudPreferencesStateURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: location.cloudPreferencesStateURL.path
        )
    }
}

final class MemoryCloudPreferencesStateStore: CloudPreferencesStateStoring {
    private let lock = NSLock()
    private var state: CloudPreferencesPersistedState

    init(state: CloudPreferencesPersistedState = .init()) {
        self.state = state
    }

    func load() -> CloudPreferencesPersistedState {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    func save(_ state: CloudPreferencesPersistedState) throws {
        lock.lock()
        self.state = state
        lock.unlock()
    }
}
