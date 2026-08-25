import Foundation

enum CloudAccountAvailability: Equatable {
    case available
    case noAccount
    case restricted
    case couldNotDetermine

    var localizedDescription: String {
        switch self {
        case .available:
            return "iCloud 可用"
        case .noAccount:
            return "尚未登入 iCloud"
        case .restricted:
            return "此帳號無法使用 iCloud"
        case .couldNotDetermine:
            return "目前無法確認 iCloud 帳號狀態"
        }
    }
}

enum CloudUserDataTransportError: LocalizedError, Equatable {
    case conflict
    case missingPayload
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .conflict:
            return "雲端資料剛被另一台裝置更新。"
        case .missingPayload:
            return "雲端備份缺少資料內容。"
        case .invalidPayload:
            return "雲端備份不是可讀取的久空輸入法資料。"
        }
    }
}

/// A CloudKit request that can be invalidated when consent is withdrawn or
/// the active Apple Account changes.
protocol CloudUserDataOperation: AnyObject {
    func cancel()
}

/// The CloudKit boundary is completion-based so the synchronization policy can
/// be tested without an iCloud account or a live container.
protocol CloudUserDataTransport: AnyObject {
    func accountAvailability(
        completion: @escaping (Result<CloudAccountAvailability, Error>) -> Void
    )

    @discardableResult
    func fetchArchive(
        completion: @escaping (Result<UserDataArchive?, Error>) -> Void
    ) -> (any CloudUserDataOperation)?

    @discardableResult
    func saveArchive(
        _ archive: UserDataArchive,
        completion: @escaping (Result<Void, Error>) -> Void
    ) -> (any CloudUserDataOperation)?
}
