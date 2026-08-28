import Foundation
import XCTest

final class AppVersionTests: XCTestCase {
    func testParsesReleaseTagsAndComparesNumericComponents() throws {
        XCTAssertEqual(try XCTUnwrap(AppVersion("v1.2.3")).description, "1.2.3")
        XCTAssertLessThan(
            try XCTUnwrap(AppVersion("1.9.9")),
            try XCTUnwrap(AppVersion("1.10.0"))
        )
        XCTAssertEqual(
            try XCTUnwrap(AppVersion("2.0")),
            try XCTUnwrap(AppVersion("2.0.0"))
        )
    }

    func testRejectsPrereleaseAndMalformedVersions() {
        XCTAssertNil(AppVersion("v1.2.3-beta"))
        XCTAssertNil(AppVersion("1..3"))
        XCTAssertNil(AppVersion("v"))
        XCTAssertNil(AppVersion("1.2.3.4.5"))
    }
}

final class UpdateReleaseDecoderTests: XCTestCase {
    func testDecodesPublishedReleaseWithExpectedArtifacts() throws {
        let release = try UpdateReleaseDecoder.decode(payload())

        XCTAssertEqual(release.version, AppVersion("0.2.0"))
        XCTAssertEqual(
            release.pageURL.absoluteString,
            "https://github.com/jiukong-labs/zhuyin/releases/tag/v0.2.0"
        )
    }

    func testRejectsDraftAndPrereleaseVersions() {
        XCTAssertThrowsError(try UpdateReleaseDecoder.decode(payload(draft: true))) {
            XCTAssertEqual($0 as? UpdateReleaseDecodingError, .unpublishedRelease)
        }
        XCTAssertThrowsError(try UpdateReleaseDecoder.decode(payload(prerelease: true))) {
            XCTAssertEqual($0 as? UpdateReleaseDecodingError, .unpublishedRelease)
        }
    }

    func testRejectsMissingChecksum() {
        XCTAssertThrowsError(try UpdateReleaseDecoder.decode(payload(hasChecksum: false))) {
            XCTAssertEqual($0 as? UpdateReleaseDecodingError, .missingReleaseAssets)
        }
    }

    func testRejectsForeignDownloadHost() {
        XCTAssertThrowsError(try UpdateReleaseDecoder.decode(payload(downloadHost: "example.com"))) {
            XCTAssertEqual($0 as? UpdateReleaseDecodingError, .untrustedURL)
        }
    }

    private func payload(
        draft: Bool = false,
        prerelease: Bool = false,
        hasChecksum: Bool = true,
        downloadHost: String = "github.com"
    ) -> Data {
        var assets = """
        {
          "name": "Jiukong-Zhuyin-0.2.0.pkg",
          "browser_download_url": "https://\(downloadHost)/jiukong-labs/zhuyin/releases/download/v0.2.0/Jiukong-Zhuyin-0.2.0.pkg"
        }
        """
        if hasChecksum {
            assets += """
            ,
            {
              "name": "Jiukong-Zhuyin-0.2.0.pkg.sha256",
              "browser_download_url": "https://github.com/jiukong-labs/zhuyin/releases/download/v0.2.0/Jiukong-Zhuyin-0.2.0.pkg.sha256"
            }
            """
        }

        return Data(
            """
            {
              "tag_name": "v0.2.0",
              "html_url": "https://github.com/jiukong-labs/zhuyin/releases/tag/v0.2.0",
              "draft": \(draft),
              "prerelease": \(prerelease),
              "assets": [\(assets)]
            }
            """.utf8
        )
    }
}

final class UpdateCheckPolicyTests: XCTestCase {
    func testFirstCheckIsDueAndRecentCheckIsNot() {
        let now = Date(timeIntervalSince1970: 2_000_000)

        XCTAssertTrue(UpdateCheckPolicy.isDue(lastCheck: nil, now: now))
        XCTAssertFalse(
            UpdateCheckPolicy.isDue(
                lastCheck: now.addingTimeInterval(-60),
                now: now
            )
        )
        XCTAssertTrue(
            UpdateCheckPolicy.isDue(
                lastCheck: now.addingTimeInterval(-UpdateCheckPolicy.automaticInterval),
                now: now
            )
        )
    }
}

final class UpdateControllerTests: XCTestCase {
    func testReportsNewerReleaseAndStoresCheckDate() throws {
        let release = UpdateRelease(
            version: try XCTUnwrap(AppVersion("0.2.0")),
            pageURL: try XCTUnwrap(URL(string: "https://github.com/jiukong-labs/zhuyin/releases/tag/v0.2.0"))
        )
        let now = Date(timeIntervalSince1970: 2_000_000)
        let store = MemoryUpdateCheckStore()
        let controller = UpdateController(
            installedVersion: "0.1.0",
            fetcher: StubUpdateReleaseFetcher(result: .success(release)),
            store: store,
            now: { now }
        )
        let completed = expectation(description: "update check completed")

        controller.checkNow { state in
            XCTAssertEqual(
                state,
                .updateAvailable(release: release, installedVersion: "0.1.0")
            )
            completed.fulfill()
        }

        wait(for: [completed], timeout: 1)
        XCTAssertEqual(store.lastAutomaticCheckDate, now)
        XCTAssertEqual(store.cachedRelease, release)
    }

    func testReportsUpToDateWhenRemoteVersionIsNotNewer() throws {
        let version = try XCTUnwrap(AppVersion("0.1.0"))
        let release = UpdateRelease(
            version: version,
            pageURL: URL(string: "https://github.com/jiukong-labs/zhuyin/releases/tag/v0.1.0")!
        )
        let controller = UpdateController(
            installedVersion: "0.1.0",
            fetcher: StubUpdateReleaseFetcher(result: .success(release)),
            store: MemoryUpdateCheckStore()
        )
        let completed = expectation(description: "update check completed")

        controller.checkNow { state in
            XCTAssertEqual(state, .upToDate(installedVersion: "0.1.0"))
            completed.fulfill()
        }

        wait(for: [completed], timeout: 1)
    }

    func testAutomaticCheckHonorsDailyInterval() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let store = MemoryUpdateCheckStore()
        store.lastAutomaticCheckDate = now.addingTimeInterval(-60)
        let fetcher = StubUpdateReleaseFetcher(
            result: .failure(TestUpdateError.unavailable)
        )
        let controller = UpdateController(
            installedVersion: "0.1.0",
            fetcher: fetcher,
            store: store,
            now: { now }
        )

        XCTAssertFalse(controller.checkAutomaticallyIfNeeded())
        XCTAssertEqual(fetcher.callCount, 0)
    }

    func testRestoresCachedNewerReleaseWithoutAnotherNetworkRequest() throws {
        let release = UpdateRelease(
            version: try XCTUnwrap(AppVersion("0.2.0")),
            pageURL: try XCTUnwrap(URL(string: "https://github.com/jiukong-labs/zhuyin/releases/tag/v0.2.0"))
        )
        let now = Date(timeIntervalSince1970: 2_000_000)
        let store = MemoryUpdateCheckStore()
        store.lastAutomaticCheckDate = now.addingTimeInterval(-60)
        store.cachedRelease = release
        let fetcher = StubUpdateReleaseFetcher(
            result: .failure(TestUpdateError.unavailable)
        )
        let controller = UpdateController(
            installedVersion: "0.1.0",
            fetcher: fetcher,
            store: store,
            now: { now }
        )

        XCTAssertEqual(
            controller.state,
            .updateAvailable(release: release, installedVersion: "0.1.0")
        )
        XCTAssertFalse(controller.checkAutomaticallyIfNeeded())
        XCTAssertEqual(fetcher.callCount, 0)
    }
}

private final class StubUpdateReleaseFetcher: UpdateReleaseFetching {
    let result: Result<UpdateRelease, Error>
    private(set) var callCount = 0

    init(result: Result<UpdateRelease, Error>) {
        self.result = result
    }

    func fetchLatestRelease(
        completion: @escaping (Result<UpdateRelease, Error>) -> Void
    ) {
        callCount += 1
        completion(result)
    }
}

private final class MemoryUpdateCheckStore: UpdateCheckStoring {
    var lastAutomaticCheckDate: Date?
    var cachedRelease: UpdateRelease?
}

private enum TestUpdateError: Error {
    case unavailable
}
