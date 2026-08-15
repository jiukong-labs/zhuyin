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
