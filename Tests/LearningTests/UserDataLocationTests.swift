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

    func testCustomFirstToneAliasAugmentsBuiltInFourthTone() throws {
        let service = CustomReadingService(fileURL: try makeFileURL())
        XCTAssertTrue(
            service.upsertCustomReading(
                character: "播",
                pronunciation: "ㄅㄛ"
            )
        )
        let dictionary = try CharacterDictionary(databaseURL: databaseURL)
        let provider = CharacterCandidateProvider(
            dictionary: dictionary,
            customReadings: service
        )

        XCTAssertTrue(
            try provider.candidates(for: "ㄅㄛ").contains {
                $0.text == "播" && $0.pronunciation == "ㄅㄛ"
            }
        )
        XCTAssertTrue(
            try provider.candidates(for: "ㄅㄛˋ").contains {
                $0.text == "播" && $0.pronunciation == "ㄅㄛˋ"
            }
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var databaseURL: URL {
        repositoryRoot
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("Dictionary", isDirectory: true)
            .appendingPathComponent("JiukongZhuyin.sqlite3")
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

final class CustomReadingValidatorTests: XCTestCase {
    func testAcceptsOneVisibleCharacterWithFieldEditorFormattingScalars() throws {
        let validated = try CustomReadingValidator.validate(
            character: "\u{200B}播\u{200E}\u{FFFC}",
            pronunciation: "\u{2060}ㄅㄛ\u{FEFF}"
        )

        XCTAssertEqual(validated.character, "播")
        XCTAssertEqual(validated.pronunciation, "ㄅㄛ")
    }

    func testStillRejectsTwoVisibleCharacters() {
        XCTAssertThrowsError(
            try CustomReadingValidator.validate(
                character: "播放",
                pronunciation: "ㄅㄛ"
            )
        ) { error in
            XCTAssertEqual(
                error as? CustomReadingValidationError,
                .invalidCharacter
            )
        }
    }

    func testKeepsOrdinaryToneMarksWhileRemovingInvisibleFormatting() throws {
        let validated = try CustomReadingValidator.validate(
            character: "播",
            pronunciation: "\u{200B}ㄅㄛˋ\u{2060}"
        )

        XCTAssertEqual(validated.pronunciation, "ㄅㄛˋ")
    }
}

final class CustomReadingCloudSyncTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
        try super.tearDownWithError()
    }

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

    func testTwoMacAddThenDeleteDoesNotResurrectAlias() throws {
        let cloud = MemoryCustomReadingCloud()
        let clockA = TestClock(100)
        let clockB = TestClock(200)
        let macA = try makeDevice(clock: clockA)
        let macB = try makeDevice(clock: clockB)

        XCTAssertTrue(macA.add(character: "播", pronunciation: "ㄅㄛ"))
        macA.sync(with: cloud)
        XCTAssertEqual(cloud.activeCharacters(for: "ㄅㄛ"), ["播"])

        macB.sync(with: cloud)
        XCTAssertEqual(macB.characters(for: "ㄅㄛ"), ["播"])

        clockB.now = Date(timeIntervalSince1970: 300)
        XCTAssertTrue(macB.delete(character: "播", pronunciation: "ㄅㄛ"))
        macB.sync(with: cloud)
        XCTAssertTrue(cloud.isDeleted(character: "播", pronunciation: "ㄅㄛ"))

        clockA.now = Date(timeIntervalSince1970: 400)
        macA.sync(with: cloud)
        XCTAssertTrue(macA.characters(for: "ㄅㄛ").isEmpty)

        // A second sync is the regression guard: the now-empty Mac A must keep
        // the tombstone instead of treating its missing JSON row as a fresh
        // local deletion or re-uploading the stale active alias.
        macA.sync(with: cloud)
        XCTAssertTrue(macA.characters(for: "ㄅㄛ").isEmpty)
        XCTAssertTrue(cloud.isDeleted(character: "播", pronunciation: "ㄅㄛ"))
    }

    func testExplicitNewerReAddAfterDeletionRestoresAliasOnOtherMac() throws {
        let cloud = MemoryCustomReadingCloud()
        let clockA = TestClock(100)
        let clockB = TestClock(200)
        let macA = try makeDevice(clock: clockA)
        let macB = try makeDevice(clock: clockB)

        XCTAssertTrue(macA.add(character: "播", pronunciation: "ㄅㄛ"))
        macA.sync(with: cloud)
        macB.sync(with: cloud)

        clockB.now = Date(timeIntervalSince1970: 300)
        XCTAssertTrue(macB.delete(character: "播", pronunciation: "ㄅㄛ"))
        macB.sync(with: cloud)

        clockA.now = Date(timeIntervalSince1970: 400)
        macA.sync(with: cloud)
        XCTAssertTrue(macA.characters(for: "ㄅㄛ").isEmpty)

        clockA.now = Date(timeIntervalSince1970: 500)
        XCTAssertTrue(macA.add(character: "播", pronunciation: "ㄅㄛ"))
        macA.sync(with: cloud)
        XCTAssertEqual(cloud.activeCharacters(for: "ㄅㄛ"), ["播"])

        clockB.now = Date(timeIntervalSince1970: 600)
        macB.sync(with: cloud)
        XCTAssertEqual(macB.characters(for: "ㄅㄛ"), ["播"])
    }

    func testOlderOfflineMacCannotOverwriteNewerCloudDeletion() throws {
        let cloud = MemoryCustomReadingCloud()
        let onlineClock = TestClock(100)
        let offlineClock = TestClock(150)
        let onlineMac = try makeDevice(clock: onlineClock)
        let offlineMac = try makeDevice(clock: offlineClock)

        XCTAssertTrue(
            onlineMac.add(character: "播", pronunciation: "ㄅㄛ")
        )
        onlineMac.sync(with: cloud)
        offlineMac.sync(with: cloud)
        XCTAssertEqual(offlineMac.characters(for: "ㄅㄛ"), ["播"])

        onlineClock.now = Date(timeIntervalSince1970: 300)
        XCTAssertTrue(
            onlineMac.delete(character: "播", pronunciation: "ㄅㄛ")
        )
        onlineMac.sync(with: cloud)
        XCTAssertTrue(cloud.isDeleted(character: "播", pronunciation: "ㄅㄛ"))

        // The offline Mac still has the old active row, but its journal carries
        // the older cloud timestamp. Pull-before-push must apply the newer
        // tombstone instead of restoring the alias.
        offlineClock.now = Date(timeIntervalSince1970: 400)
        offlineMac.sync(with: cloud)
        XCTAssertTrue(offlineMac.characters(for: "ㄅㄛ").isEmpty)
        XCTAssertTrue(cloud.isDeleted(character: "播", pronunciation: "ㄅㄛ"))
    }

    private func makeDevice(clock: TestClock) throws -> SimulatedCustomReadingDevice {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        temporaryDirectories.append(directory)
        let service = CustomReadingService(
            fileURL: directory.appendingPathComponent("custom-readings.json"),
            now: { clock.now }
        )
        return SimulatedCustomReadingDevice(service: service, clock: clock)
    }
}

private final class TestClock {
    var now: Date

    init(_ seconds: TimeInterval) {
        now = Date(timeIntervalSince1970: seconds)
    }
}

/// Deterministic in-memory stand-in for the private CloudKit zone. It does not
/// contact Apple; it only enforces the same timestamp/deletion conflict rule
/// used by `CustomReadingCloudSyncCoordinator`.
private final class MemoryCustomReadingCloud {
    fileprivate struct Value: Equatable {
        let character: String
        let pronunciation: String
        let timestamp: Date
        let deleted: Bool
    }

    private var values: [String: Value] = [:]

    func fetchAll() -> [String: Value] {
        values
    }

    func save(_ proposed: [String: Value]) {
        for (key, value) in proposed {
            guard let existing = values[key] else {
                values[key] = value
                continue
            }
            let proposedWins = CustomReadingCloudSyncCoordinator
                .remoteWinsForTesting(
                    remoteTimestamp: value.timestamp,
                    remoteDeleted: value.deleted,
                    localTimestamp: existing.timestamp,
                    localDeleted: existing.deleted
                )
            if proposedWins {
                values[key] = value
            }
        }
    }

    func activeCharacters(for pronunciation: String) -> [String] {
        values.values
            .filter { !$0.deleted && $0.pronunciation == pronunciation }
            .map(\.character)
            .sorted()
    }

    func isDeleted(character: String, pronunciation: String) -> Bool {
        values[Self.key(character: character, pronunciation: pronunciation)]?
            .deleted == true
    }

    fileprivate static func key(
        character: String,
        pronunciation: String
    ) -> String {
        pronunciation + "\u{1F}" + character
    }
}

/// Models two independent Macs with separate local JSON stores and sidecar
/// journals. The synchronization order mirrors production: reconcile local
/// state, pull cloud values, resolve conflicts, apply remote changes, then push
/// the resulting journal back to the cloud.
private final class SimulatedCustomReadingDevice {
    private struct JournalEntry: Equatable {
        let character: String
        let pronunciation: String
        var cloudTimestamp: Date
        var localObservedUpdatedAt: Date?
        var deleted: Bool
    }

    private let service: CustomReadingService
    private let clock: TestClock
    private var journal: [String: JournalEntry] = [:]

    init(service: CustomReadingService, clock: TestClock) {
        self.service = service
        self.clock = clock
    }

    @discardableResult
    func add(character: String, pronunciation: String) -> Bool {
        service.upsertCustomReading(
            character: character,
            pronunciation: pronunciation
        )
    }

    @discardableResult
    func delete(character: String, pronunciation: String) -> Bool {
        service.deleteCustomReading(
            character: character,
            pronunciation: pronunciation
        )
    }

    func characters(for pronunciation: String) -> [String] {
        service.customReadings(for: pronunciation)
            .map(\.character)
            .sorted()
    }

    func sync(with cloud: MemoryCustomReadingCloud) {
        reconcileLocalSnapshot()
        let remote = cloud.fetchAll()
        let localCloud = cloudValues()
        let keys = Set(localCloud.keys).union(remote.keys)

        for key in keys.sorted() {
            guard let remoteValue = remote[key] else {
                continue
            }
            if let localValue = localCloud[key],
               !CustomReadingCloudSyncCoordinator.remoteWinsForTesting(
                    remoteTimestamp: remoteValue.timestamp,
                    remoteDeleted: remoteValue.deleted,
                    localTimestamp: localValue.timestamp,
                    localDeleted: localValue.deleted
               ) {
                continue
            }
            applyRemote(remoteValue, key: key)
        }

        reconcileLocalSnapshot()
        cloud.save(cloudValues())
    }

    private func applyRemote(
        _ remote: MemoryCustomReadingCloud.Value,
        key: String
    ) {
        if remote.deleted {
            if service.customReadings(for: remote.pronunciation).contains(
                where: { $0.character == remote.character }
            ) {
                _ = service.deleteCustomReading(
                    character: remote.character,
                    pronunciation: remote.pronunciation
                )
            }
            journal[key] = JournalEntry(
                character: remote.character,
                pronunciation: remote.pronunciation,
                cloudTimestamp: remote.timestamp,
                localObservedUpdatedAt: nil,
                deleted: true
            )
            return
        }

        var local = service.customReadings(for: remote.pronunciation).first {
            $0.character == remote.character
        }
        if local == nil {
            _ = service.upsertCustomReading(
                character: remote.character,
                pronunciation: remote.pronunciation
            )
            local = service.customReadings(for: remote.pronunciation).first {
                $0.character == remote.character
            }
        }
        guard let local else {
            return
        }
        journal[key] = JournalEntry(
            character: remote.character,
            pronunciation: remote.pronunciation,
            cloudTimestamp: remote.timestamp,
            localObservedUpdatedAt: local.updatedAt,
            deleted: false
        )
    }

    private func reconcileLocalSnapshot() {
        var localByKey: [String: CustomReadingRecord] = [:]
        for record in service.allCustomReadings() {
            localByKey[
                MemoryCustomReadingCloud.key(
                    character: record.character,
                    pronunciation: record.pronunciation
                )
            ] = record
        }

        for (key, entry) in Array(journal) {
            guard let local = localByKey[key] else {
                if !entry.deleted {
                    journal[key] = JournalEntry(
                        character: entry.character,
                        pronunciation: entry.pronunciation,
                        cloudTimestamp: clock.now,
                        localObservedUpdatedAt: nil,
                        deleted: true
                    )
                }
                continue
            }

            if entry.deleted {
                if local.updatedAt > entry.cloudTimestamp {
                    journal[key] = JournalEntry(
                        character: local.character,
                        pronunciation: local.pronunciation,
                        cloudTimestamp: local.updatedAt,
                        localObservedUpdatedAt: local.updatedAt,
                        deleted: false
                    )
                }
                continue
            }

            if local.updatedAt != entry.localObservedUpdatedAt {
                journal[key] = JournalEntry(
                    character: local.character,
                    pronunciation: local.pronunciation,
                    cloudTimestamp: local.updatedAt,
                    localObservedUpdatedAt: local.updatedAt,
                    deleted: false
                )
            }
        }

        for (key, local) in localByKey where journal[key] == nil {
            journal[key] = JournalEntry(
                character: local.character,
                pronunciation: local.pronunciation,
                cloudTimestamp: local.updatedAt,
                localObservedUpdatedAt: local.updatedAt,
                deleted: false
            )
        }
    }

    private func cloudValues() -> [String: MemoryCustomReadingCloud.Value] {
        Dictionary(
            uniqueKeysWithValues: journal.map { key, entry in
                (
                    key,
                    MemoryCustomReadingCloud.Value(
                        character: entry.character,
                        pronunciation: entry.pronunciation,
                        timestamp: entry.cloudTimestamp,
                        deleted: entry.deleted
                    )
                )
            }
        )
    }
}
