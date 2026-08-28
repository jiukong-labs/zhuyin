import Foundation

protocol UpdateReleaseFetching {
    func fetchLatestRelease(
        completion: @escaping (Result<UpdateRelease, Error>) -> Void
    )
}

enum GitHubUpdateError: LocalizedError {
    case invalidHTTPResponse
    case serverStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidHTTPResponse:
            return "更新伺服器沒有回傳有效的 HTTP 回應。"
        case let .serverStatus(status):
            return "更新伺服器回傳 HTTP \(status)。"
        }
    }
}

final class GitHubUpdateReleaseFetcher: UpdateReleaseFetching {
    static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/jiukong-labs/zhuyin/releases/latest"
    )!

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchLatestRelease(
        completion: @escaping (Result<UpdateRelease, Error>) -> Void
    ) {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadRevalidatingCacheData
        request.setValue(
            "application/vnd.github+json",
            forHTTPHeaderField: "Accept"
        )
        request.setValue(
            "Jiukong-Zhuyin-Update-Checker",
            forHTTPHeaderField: "User-Agent"
        )

        session.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let response = response as? HTTPURLResponse else {
                completion(.failure(GitHubUpdateError.invalidHTTPResponse))
                return
            }
            guard response.statusCode == 200 else {
                completion(.failure(GitHubUpdateError.serverStatus(response.statusCode)))
                return
            }
            guard let data else {
                completion(.failure(UpdateReleaseDecodingError.invalidResponse))
                return
            }

            do {
                completion(.success(try UpdateReleaseDecoder.decode(data)))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}

protocol UpdateCheckStoring: AnyObject {
    var lastAutomaticCheckDate: Date? { get set }
    var cachedRelease: UpdateRelease? { get set }
}

final class UserDefaultsUpdateCheckStore: UpdateCheckStoring {
    private static let lastCheckKey = "JiukongUpdateLastCheckDate"
    private static let releaseVersionKey = "JiukongUpdateReleaseVersion"
    private static let releasePageURLKey = "JiukongUpdateReleasePageURL"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var lastAutomaticCheckDate: Date? {
        get { defaults.object(forKey: Self.lastCheckKey) as? Date }
        set { defaults.set(newValue, forKey: Self.lastCheckKey) }
    }

    var cachedRelease: UpdateRelease? {
        get {
            guard let version = defaults.string(
                forKey: Self.releaseVersionKey
            ),
                  let pageURLString = defaults.string(
                    forKey: Self.releasePageURLKey
                  ),
                  let pageURL = URL(string: pageURLString) else {
                return nil
            }
            return UpdateRelease(cachedVersion: version, pageURL: pageURL)
        }
        set {
            defaults.set(
                newValue?.version.description,
                forKey: Self.releaseVersionKey
            )
            defaults.set(
                newValue?.pageURL.absoluteString,
                forKey: Self.releasePageURLKey
            )
        }
    }
}

enum UpdateCheckPolicy {
    static let automaticInterval: TimeInterval = 24 * 60 * 60

    static func isDue(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else {
            return true
        }
        return now.timeIntervalSince(lastCheck) >= automaticInterval
    }
}

enum UpdateCheckState: Equatable {
    case idle(installedVersion: String)
    case checking(installedVersion: String)
    case upToDate(installedVersion: String)
    case updateAvailable(release: UpdateRelease, installedVersion: String)
    case failed(installedVersion: String, message: String)

    var installedVersion: String {
        switch self {
        case let .idle(version),
             let .checking(version),
             let .upToDate(version),
             let .updateAvailable(_, version),
             let .failed(version, _):
            return version
        }
    }
}

/// Owns the process-wide update state. Automatic checks are silent; UI code
/// observes `didChangeNotification` and decides how to present a manual result.
final class UpdateController {
    static let didChangeNotification = Notification.Name(
        "tw.idv.jiukong.UpdateCheckDidChange"
    )

    static let shared = UpdateController(
        installedVersion: Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "未知",
        fetcher: GitHubUpdateReleaseFetcher(),
        store: UserDefaultsUpdateCheckStore()
    )

    private let fetcher: UpdateReleaseFetching
    private let store: UpdateCheckStoring
    private let notificationCenter: NotificationCenter
    private let now: () -> Date
    private var timer: Timer?
    private var completions: [(UpdateCheckState) -> Void] = []

    private(set) var state: UpdateCheckState {
        didSet {
            guard state != oldValue else {
                return
            }
            notificationCenter.post(
                name: Self.didChangeNotification,
                object: self
            )
        }
    }

    init(
        installedVersion: String,
        fetcher: UpdateReleaseFetching,
        store: UpdateCheckStoring,
        notificationCenter: NotificationCenter = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.fetcher = fetcher
        self.store = store
        self.notificationCenter = notificationCenter
        self.now = now
        if let installed = AppVersion(installedVersion),
           let cachedRelease = store.cachedRelease,
           cachedRelease.version > installed {
            state = .updateAvailable(
                release: cachedRelease,
                installedVersion: installedVersion
            )
        } else {
            state = .idle(installedVersion: installedVersion)
        }
    }

    func startAutomaticChecks() {
        guard timer == nil else {
            return
        }

        checkAutomaticallyIfNeeded()
        let timer = Timer(timeInterval: 60 * 60, repeats: true) { [weak self] _ in
            self?.checkAutomaticallyIfNeeded()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @discardableResult
    func checkAutomaticallyIfNeeded() -> Bool {
        guard UpdateCheckPolicy.isDue(
            lastCheck: store.lastAutomaticCheckDate,
            now: now()
        ) else {
            return false
        }
        checkNow()
        return true
    }

    func checkNow(completion: ((UpdateCheckState) -> Void)? = nil) {
        if let completion {
            completions.append(completion)
        }
        if case .checking = state {
            return
        }
        beginCheck()
    }

    private func beginCheck() {
        let installedVersion = state.installedVersion
        guard let installed = AppVersion(installedVersion) else {
            finish(
                with: .failed(
                    installedVersion: installedVersion,
                    message: "目前安裝版本的版本號格式不正確。"
                )
            )
            return
        }

        store.lastAutomaticCheckDate = now()
        state = .checking(installedVersion: installedVersion)
        fetcher.fetchLatestRelease { [weak self] result in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                switch result {
                case let .success(release):
                    self.store.cachedRelease = release
                    if release.version > installed {
                        self.finish(
                            with: .updateAvailable(
                                release: release,
                                installedVersion: installedVersion
                            )
                        )
                    } else {
                        self.finish(
                            with: .upToDate(installedVersion: installedVersion)
                        )
                    }
                case let .failure(error):
                    if let cachedRelease = self.store.cachedRelease,
                       cachedRelease.version > installed {
                        self.finish(
                            with: .updateAvailable(
                                release: cachedRelease,
                                installedVersion: installedVersion
                            )
                        )
                    } else {
                        self.finish(
                            with: .failed(
                                installedVersion: installedVersion,
                                message: error.localizedDescription
                            )
                        )
                    }
                }
            }
        }
    }

    private func finish(with newState: UpdateCheckState) {
        state = newState
        let callbacks = completions
        completions.removeAll()
        for callback in callbacks {
            callback(newState)
        }
    }
}
