import Foundation
import XCTest

final class CloudUserDataModelsTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
        try super.tearDownWithError()
    }

    func testIdentityRecordNameIsStableOpaqueAndBounded() throws {
        let first = try CloudUserDataIdentity(
            phrase: "久空",
            readings: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"]
        )
        let same = try CloudUserDataIdentity(
            phrase: "久空",
            readings: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"]
        )
        let other = try CloudUserDataIdentity(
            phrase: "九空",
            readings: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"]
        )

        XCTAssertEqual(first.recordName, same.recordName)
        XCTAssertNotEqual(first.recordName, other.recordName)
        XCTAssertEqual(first.recordName.count, 67)
        XCTAssertFalse(first.recordName.contains("久"))
        XCTAssertFalse(first.recordName.contains("ㄐ"))
    }

    func testCharacterAndPhraseWithSimilarTextHaveDifferentIdentities() throws {
        let character = try CloudUserDataIdentity(
            character: "行",
            pronunciation: "ㄒㄧㄥˊ"
        )
        let phrase = try CloudUserDataIdentity(
            phrase: "行行",
            readings: ["ㄒㄧㄥˊ", "ㄒㄧㄥˊ"]
        )

        XCTAssertNotEqual(character.recordName, phrase.recordName)
        XCTAssertEqual(character.kind, .character)
        XCTAssertEqual(phrase.kind, .phrase)
    }

    func testPendingStateKeepsOnlyNewestMutationAndClearsExactly() throws {
        let identity = try CloudUserDataIdentity(
            character: "鍵",
            pronunciation: "ㄐㄧㄢˋ"
        )
        var state = CloudSyncPersistedState()
        state.note(.upsert, identity: identity)
        let stale = try XCTUnwrap(state.pending[identity.recordName])
        state.note(.delete, identity: identity)
        let current = try XCTUnwrap(state.pending[identity.recordName])

        state.clear([stale])
        XCTAssertEqual(state.pending[identity.recordName], current)
        state.clear([current])
        XCTAssertTrue(state.pending.isEmpty)
    }

    func testFileStateStoreRoundTripsPrivately() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        temporaryDirectories.append(root)
        let location = UserDataLocation(applicationSupportRootURL: root)
        let store = FileCloudSyncStateStore(location: location)
        let identity = try CloudUserDataIdentity(
            character: "鍵",
            pronunciation: "ㄐㄧㄢˋ"
        )
        var state = CloudSyncPersistedState()
        state.accountIdentifier = CloudAccountIdentifier(
            stableIdentifier: "account-a"
        )
        state.completedInitialMerge = true
        state.note(.upsert, identity: identity)

        try store.save(state)

        XCTAssertEqual(store.load(), state)
        let attributes = try FileManager.default.attributesOfItem(
            atPath: location.cloudSyncStateURL.path
        )
        XCTAssertEqual(
            (attributes[.posixPermissions] as? NSNumber)?.intValue,
            0o600
        )
    }

    func testStateWrittenBeforeAccountTrackingStillLoads() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        temporaryDirectories.append(root)
        let location = UserDataLocation(applicationSupportRootURL: root)
        try location.prepareDirectory()
        let previousState = """
        {"completedInitialMerge":true,"nextRevision":1,"pending":{},"version":1}
        """
        try Data(previousState.utf8).write(to: location.cloudSyncStateURL)

        let loaded = FileCloudSyncStateStore(location: location).load()

        XCTAssertTrue(loaded.completedInitialMerge)
        XCTAssertNil(loaded.accountIdentifier)
    }

    func testMalformedStateFallsBackWithoutThrowing() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        temporaryDirectories.append(root)
        let location = UserDataLocation(applicationSupportRootURL: root)
        try location.prepareDirectory()
        try Data("not-json".utf8).write(to: location.cloudSyncStateURL)

        XCTAssertEqual(
            FileCloudSyncStateStore(location: location).load(),
            CloudSyncPersistedState()
        )
    }
}
