import Foundation

enum UserDataLocationError: LocalizedError {
    case applicationSupportUnavailable
    case unsafeDirectory(URL)
    case unsafeDatabaseFile(URL)

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            return "The user Application Support directory is unavailable."
        case let .unsafeDirectory(url):
            return "The user data path is not a private directory: \(url.path)"
        case let .unsafeDatabaseFile(url):
            return "The user database path is not a regular file: \(url.path)"
        }
    }
}

struct UserDataLocation: Equatable {
    static let directoryName = "JiukongZhuyin"
    static let databaseName = "user.sqlite"
    static let cloudSyncStateName = "cloud-sync-state.json"

    let directoryURL: URL

    var databaseURL: URL {
        directoryURL.appendingPathComponent(Self.databaseName, isDirectory: false)
    }

    var cloudSyncStateURL: URL {
        directoryURL.appendingPathComponent(
            Self.cloudSyncStateName,
            isDirectory: false
        )
    }

    init(applicationSupportRootURL: URL) {
        directoryURL = applicationSupportRootURL
            .appendingPathComponent(Self.directoryName, isDirectory: true)
    }

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    static func userDomain(
        fileManager: FileManager = .default
    ) throws -> UserDataLocation {
        guard let root = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw UserDataLocationError.applicationSupportUnavailable
        }
        return UserDataLocation(applicationSupportRootURL: root)
    }

    func prepareDirectory(fileManager: FileManager = .default) throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) {
            let values = try directoryURL.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
            guard isDirectory.boolValue,
                  values.isDirectory == true,
                  values.isSymbolicLink != true else {
                throw UserDataLocationError.unsafeDirectory(directoryURL)
            }
        } else {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }

        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directoryURL.path
        )
    }
}
