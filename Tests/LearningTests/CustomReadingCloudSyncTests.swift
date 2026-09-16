import Foundation
import XCTest

final class CustomReadingCloudSyncTests: XCTestCase {
    func testNewerRemoteRecordWins() {
        let local = Date(timeIntervalSince1970: 100)
        let remote = Date(timeIntervalSince1970: 101)

        XCTAssertTrue(
            CustomReadingCloudSyncCoordinator.remoteWinsForTesting(
                remoteTimestamp: remote,
                remoteDeleted: false,
                localTimestamp: local,
                localDeleted: false
            )
        )
    }

    func testOlderRemoteRecordDoesNotReplaceLocalState() {
        let local = Date(timeIntervalSince1970: 101)
        let remote = Date(timeIntervalSince1970: 100)

        XCTAssertFalse(
            CustomReadingCloudSyncCoordinator.remoteWinsForTesting(
                remoteTimestamp: remote,
                remoteDeleted: false,
                localTimestamp: local,
                localDeleted: false
            )
        )
    }

    func testDeletionWinsTimestampTieToPreventResurrection() {
        let timestamp = Date(timeIntervalSince1970: 100)

        XCTAssertTrue(
            CustomReadingCloudSyncCoordinator.remoteWinsForTesting(
                remoteTimestamp: timestamp,
                remoteDeleted: true,
                localTimestamp: timestamp,
                localDeleted: false
            )
        )
        XCTAssertFalse(
            CustomReadingCloudSyncCoordinator.remoteWinsForTesting(
                remoteTimestamp: timestamp,
                remoteDeleted: false,
                localTimestamp: timestamp,
                localDeleted: true
            )
        )
    }

    func testEqualEquivalentStateKeepsLocalCopy() {
        let timestamp = Date(timeIntervalSince1970: 100)

        XCTAssertFalse(
            CustomReadingCloudSyncCoordinator.remoteWinsForTesting(
                remoteTimestamp: timestamp,
                remoteDeleted: false,
                localTimestamp: timestamp,
                localDeleted: false
            )
        )
        XCTAssertFalse(
            CustomReadingCloudSyncCoordinator.remoteWinsForTesting(
                remoteTimestamp: timestamp,
                remoteDeleted: true,
                localTimestamp: timestamp,
                localDeleted: true
            )
        )
    }
}
