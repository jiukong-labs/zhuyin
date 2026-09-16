import Foundation
import XCTest

final class UserDataLocationTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
        try super.tearDownWithError()
    }

    func testBuildsDocumentedApplicationSupportPaths() throws {
        let root = try makeTemporaryDirectory()
        let location = UserDataLocation(applicationSupportRootURL: root)

        XCTAssertEqual(
            location.directoryURL,
            root.appendingPathComponent("JiukongZhuyin", isDirectory: true)
        )
        XCTAssertEqual(
            location.databaseURL,
            root
                .appendingPathComponent("JiukongZhuyin", isDirectory: true)
                .appendingPathComponent("user.sqlite")
        )
    }

    func testPrepareCreatesPrivateDirectoryAndRepairsPermissions() throws {
        let root = try makeTemporaryDirectory()
        let location = UserDataLocation(applicationSupportRootURL: root)

        try location.prepareDirectory()
        XCTAssertEqual(try permissions(at: location.directoryURL), 0o700)

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: location.directoryURL.path
        )
        try location.prepareDirectory()
        XCTAssertEqual(try permissions(at: location.directoryURL), 0o700)
    }

    func testPrepareRejectsAFileAtTheDataDirectoryPath() throws {
        let root = try makeTemporaryDirectory()
        let location = UserDataLocation(applicationSupportRootURL: root)
        XCTAssertTrue(
            FileManager.default.createFile(
                atPath: location.directoryURL.path,
                contents: Data()
            )
        )

        XCTAssertThrowsError(try location.prepareDirectory()) { error in
            guard case UserDataLocationError.unsafeDirectory = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testPrepareRejectsASymbolicLink() throws {
        let root = try makeTemporaryDirectory()
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(
            at: destination,
            withIntermediateDirectories: false
        )
        let location = UserDataLocation(applicationSupportRootURL: root)
        try FileManager.default.createSymbolicLink(
            at: location.directoryURL,
            withDestinationURL: destination
        )

        XCTAssertThrowsError(try location.prepareDirectory()) { error in
            guard case UserDataLocationError.unsafeDirectory = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: false
        )
        temporaryDirectories.append(url)
        return url
    }

    private func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.path
        )
        let number = try XCTUnwrap(
            attributes[.posixPermissions] as? NSNumber
        )
        return number.intValue & 0o777
    }
}

final class CustomReadingServiceTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
        try super.tearDownWithError()
    }

    func testStoresFirstToneAliasAndReloadsIt() throws {
        let fileURL = try makeFileURL()
        let timestamp = Date(timeIntervalSince1970: 2_000_000_000)
        let service = CustomReadingService(
            fileURL: fileURL,
            now: { timestamp }
        )

        XCTAssertTrue(
            service.upsertCustomReading(
                character: "播",
                pronunciation: "ㄅㄛ"
            )
        )
        XCTAssertEqual(
            service.customReadings(for: "ㄅㄛ"),
            [
                CustomReadingRecord(
                    character: "播",
                    pronunciation: "ㄅㄛ",
                    createdAt: timestamp,
                    updatedAt: timestamp
                ),
            ]
        )

        let reloaded = CustomReadingService(fileURL: fileURL)
        XCTAssertEqual(
            reloaded.customReadings(for: "ㄅㄛ").map(\.character),
            ["播"]
        )
        XCTAssertEqual(
            reloaded.customReadings(for: "ㄅㄛˋ"),
            []
        )
        XCTAssertEqual(try permissions(at: fileURL), 0o600)
    }

    func testReplaceMovesOnlyTheCustomAliasIdentity() throws {
        let fileURL = try makeFileURL()
        var timestamp = Date(timeIntervalSince1970: 100)
        let service = CustomReadingService(
            fileURL: fileURL,
            now: { timestamp }
        )
        XCTAssertTrue(
            service.upsertCustomReading(
                character: "播",
                pronunciation: "ㄅㄛ"
            )
        )
        let old = try XCTUnwrap(service.customReadings(for: "ㄅㄛ").first)

        timestamp = Date(timeIntervalSince1970: 200)
        XCTAssertTrue(
            service.replaceCustomReading(
                old,
                character: "播",
                pronunciation: "ㄅㄛˊ"
            )
        )

        XCTAssertTrue(service.customReadings(for: "ㄅㄛ").isEmpty)
        let replacement = try XCTUnwrap(
            service.customReadings(for: "ㄅㄛˊ").first
        )
        XCTAssertEqual(replacement.character, "播")
        XCTAssertEqual(replacement.createdAt, old.createdAt)
        XCTAssertEqual(replacement.updatedAt, timestamp)
    }

    func testRejectsMultiCharacterAndNonBopomofoAliases() throws {
        let service = CustomReadingService(fileURL: try makeFileURL())

        XCTAssertFalse(
            service.upsertCustomReading(
                character: "播放",
                pronunciation: "ㄅㄛ"
            )
        )
        XCTAssertFalse(
            service.upsertCustomReading(
                character: "播",
                pronunciation: "bo"
            )
        )
        XCTAssertTrue(service.allCustomReadings().isEmpty)
    }

    func testDeletingAliasPersistsAcrossReload() throws {
        let fileURL = try makeFileURL()
        let service = CustomReadingService(fileURL: fileURL)
        XCTAssertTrue(
            service.upsertCustomReading(
                character: "播",
                pronunciation: "ㄅㄛ"
            )
        )
        XCTAssertTrue(
            service.deleteCustomReading(
                character: "播",
                pronunciation: "ㄅㄛ"
            )
        )

        XCTAssertTrue(
            CustomReadingService(fileURL: fileURL)
                .allCustomReadings()
                .isEmpty
        )
    }

    private func makeFileURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        temporaryDirectories.append(directory)
        return directory.appendingPathComponent(
            "custom-readings.json",
            isDirectory: false
        )
    }

    private func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.path
        )
        let number = try XCTUnwrap(
            attributes[.posixPermissions] as? NSNumber
        )
        return number.intValue & 0o777
    }
}
