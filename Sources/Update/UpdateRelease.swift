import Foundation

struct UpdateRelease: Equatable {
    let version: AppVersion
    let pageURL: URL

    init(version: AppVersion, pageURL: URL) {
        self.version = version
        self.pageURL = pageURL
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

    static func isTrustedDownload(_ url: URL) -> Bool {
        isHTTPSGitHubURL(url)
            && url.path.hasPrefix("/jiukong-labs/zhuyin/releases/download/")
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

        let packageName = "Jiukong-Zhuyin-\(version).pkg"
        let checksumName = "\(packageName).sha256"
        guard let package = payload.assets.first(where: { $0.name == packageName }),
              let checksum = payload.assets.first(where: { $0.name == checksumName }) else {
            throw UpdateReleaseDecodingError.missingReleaseAssets
        }
        guard UpdateRelease.isTrustedDownload(package.browserDownloadURL),
              UpdateRelease.isTrustedDownload(checksum.browserDownloadURL) else {
            throw UpdateReleaseDecodingError.untrustedURL
        }

        return UpdateRelease(
            version: version,
            pageURL: payload.htmlURL
        )
    }
}
