import Foundation

struct UpdateRelease: Equatable {
    let version: AppVersion
    let pageURL: URL
    let packageURL: URL
    let checksumURL: URL

    init(version: AppVersion, pageURL: URL) {
        let packageURL = Self.canonicalAssetURL(
            version: version,
            fileName: Self.packageName(for: version)
        )
        self.version = version
        self.pageURL = pageURL
        self.packageURL = packageURL
        checksumURL = packageURL.appendingPathExtension("sha256")
    }

    init(
        version: AppVersion,
        pageURL: URL,
        packageURL: URL,
        checksumURL: URL
    ) {
        self.version = version
        self.pageURL = pageURL
        self.packageURL = packageURL
        self.checksumURL = checksumURL
    }

    init?(cachedVersion: String, pageURL: URL) {
        guard let version = AppVersion(cachedVersion),
              Self.isTrustedReleasePage(pageURL) else {
            return nil
        }
        self.init(version: version, pageURL: pageURL)
    }

    static func isTrustedReleasePage(_ url: URL) -> Bool {
        isHTTPSGitHubURL(url)
            && url.path.hasPrefix("/jiukong-labs/zhuyin/releases/")
    }

    static func isTrustedDownload(
        _ url: URL,
        version: AppVersion,
        fileName: String
    ) -> Bool {
        isHTTPSGitHubURL(url)
            && url.path
                == "/jiukong-labs/zhuyin/releases/download/v\(version)/\(fileName)"
            && url.query == nil
            && url.fragment == nil
    }

    static func packageName(for version: AppVersion) -> String {
        "Jiukong-Zhuyin-\(version).pkg"
    }

    private static func canonicalAssetURL(
        version: AppVersion,
        fileName: String
    ) -> URL {
        URL(
            string: "https://github.com/jiukong-labs/zhuyin/releases/download/v\(version)/\(fileName)"
        )!
    }

    private static func isHTTPSGitHubURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == "github.com"
            && url.user == nil
            && url.password == nil
    }
}

enum UpdateReleaseDecodingError: LocalizedError, Equatable {
    case invalidResponse
    case unpublishedRelease
    case invalidVersion
    case untrustedURL
    case missingReleaseAssets

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "更新伺服器回傳了無法辨識的資料。"
        case .unpublishedRelease:
            return "最新版本尚未正式發布。"
        case .invalidVersion:
            return "最新版本的版本號格式不正確。"
        case .untrustedURL:
            return "更新伺服器回傳了不受信任的下載網址。"
        case .missingReleaseAssets:
            return "最新版本缺少安裝套件或檢查碼。"
        }
    }
}

enum UpdateReleaseDecoder {
    private struct Payload: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let htmlURL: URL
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case draft
            case prerelease
            case assets
        }
    }

    static func decode(_ data: Data) throws -> UpdateRelease {
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw UpdateReleaseDecodingError.invalidResponse
        }

        guard !payload.draft, !payload.prerelease else {
            throw UpdateReleaseDecodingError.unpublishedRelease
        }
        guard let version = AppVersion(payload.tagName) else {
            throw UpdateReleaseDecodingError.invalidVersion
        }
        guard UpdateRelease.isTrustedReleasePage(payload.htmlURL) else {
            throw UpdateReleaseDecodingError.untrustedURL
        }

        let packageName = UpdateRelease.packageName(for: version)
        let checksumName = "\(packageName).sha256"
        guard let package = payload.assets.first(where: { $0.name == packageName }),
              let checksum = payload.assets.first(where: { $0.name == checksumName }) else {
            throw UpdateReleaseDecodingError.missingReleaseAssets
        }
        guard UpdateRelease.isTrustedDownload(
            package.browserDownloadURL,
            version: version,
            fileName: packageName
        ),
        UpdateRelease.isTrustedDownload(
            checksum.browserDownloadURL,
            version: version,
            fileName: checksumName
        ) else {
            throw UpdateReleaseDecodingError.untrustedURL
        }

        return UpdateRelease(
            version: version,
            pageURL: payload.htmlURL,
            packageURL: package.browserDownloadURL,
            checksumURL: checksum.browserDownloadURL
        )
    }
}
