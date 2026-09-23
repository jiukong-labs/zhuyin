import CloudKit
import Foundation
import os

final class UserLearningService: UserLearningProviding {
    static let shared = UserLearningService()

    private static let logger = Logger(
        subsystem: "tw.idv.jiukong.inputmethod.zhuyin",
        category: "UserLearning"
    )

    private let queue: DispatchQueue
    private let store: UserLearningStoring?
    private let cloudSync: UserDataCloudSyncing?
    private let now: () -> Date

    private convenience init() {
        let store: UserLearningStoring?
        let cloudSync: UserDataCloudSyncing?
        do {
            let location = try UserDataLocation.userDomain()
            let learningStore = try UserLearningStore(location: location)
            let preferences = PreferencesController.shared
            store = learningStore
            // Constructing CKContainer without the container entitlement
            // traps the process rather than throwing, so an unentitled
            // build (the repository's own ad-hoc local build included) must
            // never reach it.
            if ProcessEntitlements.isEntitledForICloudContainer(
                CloudKitUserDataTransport.containerIdentifier
            ) {
                cloudSync = UserDataCloudSyncCoordinator(
                    store: learningStore,
                    transport: CloudKitUserDataTransport(),
                    stateStore: FileCloudSyncStateStore(location: location),
                    isEnabled: {
                        preferences.current.iCloudSyncEnabled
                    },
                    turnOffSyncAfterAccountChange: {
                        preferences.update {
                            $0.iCloudSyncEnabled = false
                        }
                    }
                )
            } else {
                Self.logger.notice(
                    "This build has no iCloud container entitlement; cloud sync is disabled."
                )
                cloudSync = nil
            }
        } catch {
            Self.logger.error(
                "User learning storage is unavailable; personalization is disabled."
            )
            store = nil
            cloudSync = nil
        }
        self.init(store: store, cloudSync: cloudSync)
    }

    init(
        store: UserLearningStoring?,
        cloudSync: UserDataCloudSyncing? = nil,
        now: @escaping () -> Date = Date.init,
        queueLabel: String = "tw.idv.jiukong.user-learning"
    ) {
        self.store = store
        self.cloudSync = cloudSync
        self.now = now
        queue = DispatchQueue(label: queueLabel, qos: .userInitiated)
    }

    var cloudSyncStatus: UserDataCloudSyncStatus {
        cloudSync?.status
            ?? .unavailable("本機學習資料庫目前無法使用。")
    }

    func startCloudSync() {
        cloudSync?.start()
    }

    func synchronizeCloudNow() {
        cloudSync?.synchronizeNow()
    }

    func refreshCloudIfNeeded() {
        cloudSync?.refreshIfNeeded()
    }

    func cloudSyncPreferenceDidChange() {
        cloudSync?.preferenceDidChange()
    }

    func records(
        for pronunciation: String
    ) -> [String: CharacterLearningRecord] {
        queue.sync {
            guard let store else {
                return [:]
            }
            do {
                return try store.records(for: pronunciation)
            } catch {
                Self.logger.error(
                    "Could not read user learning data; base ranking will be used."
                )
                return [:]
            }
        }
    }

    func recordSelection(character: String, pronunciation: String) {
        queue.sync {
            guard let store else {
                return
            }
            do {
                try store.recordSelection(
                    character: character,
                    pronunciation: pronunciation,
                    at: now()
                )
                noteCharacterUpsert(
                    character: character,
                    pronunciation: pronunciation
                )
            } catch {
                Self.logger.error(
                    "Could not update user learning data; input will continue."
                )
            }
        }
    }

    func setPinned(
        _ pinned: Bool,
        character: String,
        pronunciation: String
    ) {
        queue.sync {
            guard let store else {
                return
            }
            do {
                try store.setPinned(
                    pinned,
                    character: character,
                    pronunciation: pronunciation
                )
                noteCharacterUpsert(
                    character: character,
                    pronunciation: pronunciation
                )
            } catch {
                Self.logger.error(
                    "Could not update a user learning pin; input will continue."
                )
            }
        }
    }

    func phraseRecords(
        for pronunciationSequence: [String]
    ) -> [UserPhraseRecord] {
        queue.sync {
            guard let store else {
                return []
            }
            do {
                return try store.phraseRecords(
                    for: pronunciationSequence
                )
            } catch {
                Self.logger.error(
                    "Could not read user phrase data; phrase candidates are unavailable."
                )
                return []
            }
        }
    }

    @discardableResult
    func addPhrase(
        phrase: String,
        pronunciationSequence: [String],
        createdAt: Date
    ) -> Bool {
        guard let pattern = PhraseOutputPattern.inferred(
            from: phrase,
            readingCount: pronunciationSequence.count
        ) else {
            return false
        }
        return addPhrase(
            phrase: phrase,
            pronunciationSequence: pronunciationSequence,
            outputPattern: pattern,
            createdAt: createdAt
        )
    }

    @discardableResult
    func addPhrase(
        phrase: String,
        pronunciationSequence: [String],
        outputPattern: PhraseOutputPattern,
        createdAt: Date
    ) -> Bool {
        queue.sync {
            guard let store else {
                return false
            }
            do {
                try store.addPhrase(
                    phrase: phrase,
                    pronunciationSequence: pronunciationSequence,
                    outputPattern: outputPattern,
                    createdAt: createdAt
                )
                notePhraseUpsert(
                    phrase: phrase,
                    pronunciationSequence: pronunciationSequence
                )
                return true
            } catch {
                Self.logger.error(
                    "Could not add a user phrase; input will continue."
                )
                return false
            }
        }
    }

    func recordPhraseSelection(
        phrase: String,
        pronunciationSequence: [String],
        at date: Date
    ) {
        queue.sync {
            guard let store else {
                return
            }
            do {
                try store.recordPhraseSelection(
                    phrase: phrase,
                    pronunciationSequence: pronunciationSequence,
                    at: date
                )
                notePhraseUpsert(
                    phrase: phrase,
                    pronunciationSequence: pronunciationSequence
                )
            } catch {
                Self.logger.error(
                    "Could not update user phrase learning; input will continue."
                )
            }
        }
    }

    func setPhrasePinned(
        _ pinned: Bool,
        phrase: String,
        pronunciationSequence: [String]
    ) {
        queue.sync {
            guard let store else {
                return
            }
            do {
                try store.setPhrasePinned(
                    pinned,
                    phrase: phrase,
                    pronunciationSequence: pronunciationSequence
                )
                notePhraseUpsert(
                    phrase: phrase,
                    pronunciationSequence: pronunciationSequence
                )
            } catch {
                Self.logger.error(
                    "Could not update a user phrase pin; input will continue."
                )
            }
        }
    }

    func suppressedPhrases(
        for pronunciationSequence: [String]
    ) -> Set<String> {
        queue.sync {
            guard let store else {
                return []
            }
            do {
                return try store.suppressedPhrases(for: pronunciationSequence)
            } catch {
                Self.logger.error(
                    "Could not read removed built-in phrases; they stay visible."
                )
                return []
            }
        }
    }

    /// Removes one built-in phrase from the candidate window for good. The
    /// tombstone lives in the user's database, so a dictionary shipped with a
    /// later update cannot bring the phrase back.
    @discardableResult
    func suppressPhrase(
        phrase: String,
        pronunciationSequence: [String],
        at date: Date
    ) -> Bool {
        queue.sync {
            guard let store else {
                return false
            }
            do {
                try store.suppressPhrase(
                    phrase: phrase,
                    pronunciationSequence: pronunciationSequence,
                    at: date
                )
                noteSuppressionUpsert(
                    phrase: phrase,
                    pronunciationSequence: pronunciationSequence
                )
                return true
            } catch {
                Self.logger.error(
                    "Could not remove a built-in phrase; input will continue."
                )
                return false
            }
        }
    }

    @discardableResult
    func restorePhrase(
        phrase: String,
        pronunciationSequence: [String]
    ) -> Bool {
        clear(
            "a removed built-in phrase",
            identities: { _ in
                [try CloudUserDataIdentity(
                    suppressedPhrase: phrase,
                    readings: pronunciationSequence
                )]
            }
        ) {
            try $0.restorePhrase(
                phrase: phrase,
                pronunciationSequence: pronunciationSequence
            )
        }
    }

    @discardableResult
    func clearSuppressedPhrases() -> Bool {
        clear(
            "removed built-in phrases",
            identities: { store in
                try store.allSuppressedPhrases().compactMap {
                    try? CloudUserDataIdentity(
                        suppressedPhrase: $0.phrase,
                        readings: $0.pronunciationSequence
                    )
                }
            },
            operation: { try $0.clearSuppressedPhrases() }
        )
    }

    /// Reports success so the settings window can tell the user that a clear
    /// request did not take effect instead of silently appearing to succeed.
    @discardableResult
    func clearCharacterLearning() -> Bool {
        clear(
            "character learning",
            identities: { store in
                try store.allCharacterRecords().compactMap {
                    try? CloudUserDataIdentity(
                        character: $0.character,
                        pronunciation: $0.pronunciation
                    )
                }
            },
            operation: { try $0.clearCharacterLearning() }
        )
    }

    @discardableResult
    func clearUserPhrases() -> Bool {
        clear(
            "user phrases",
            identities: { store in
                try store.allPhraseRecords().compactMap {
                    try? CloudUserDataIdentity(
                        phrase: $0.phrase,
                        readings: $0.pronunciationSequence
                    )
                }
            },
            operation: { try $0.clearUserPhrases() }
        )
    }

    @discardableResult
    func clearAllUserData() -> Bool {
        clear(
            "all user data",
            identities: { store in
                let characters = try store.allCharacterRecords().compactMap {
                    try? CloudUserDataIdentity(
                        character: $0.character,
                        pronunciation: $0.pronunciation
                    )
                }
                let phrases = try store.allPhraseRecords().compactMap {
                    try? CloudUserDataIdentity(
                        phrase: $0.phrase,
                        readings: $0.pronunciationSequence
                    )
                }
                let suppressions = try store.allSuppressedPhrases()
                    .compactMap {
                        try? CloudUserDataIdentity(
                            suppressedPhrase: $0.phrase,
                            readings: $0.pronunciationSequence
                        )
                    }
                return characters + phrases + suppressions
            },
            operation: { try $0.clearAllUserData() }
        )
    }

    func allCharacterRecords() -> [CharacterLearningRecord] {
        queue.sync {
            guard let store else {
                return []
            }
            do {
                return try store.allCharacterRecords()
            } catch {
                Self.logger.error(
                    "Could not list user learning data; the settings list is empty."
                )
                return []
            }
        }
    }

    func allPhraseRecords() -> [UserPhraseRecord] {
        queue.sync {
            guard let store else {
                return []
            }
            do {
                return try store.allPhraseRecords()
            } catch {
                Self.logger.error(
                    "Could not list user phrases; the settings list is empty."
                )
                return []
            }
        }
    }

    func allSuppressedPhrases() -> [SuppressedPhraseRecord] {
        queue.sync {
            guard let store else {
                return []
            }
            do {
                return try store.allSuppressedPhrases()
            } catch {
                Self.logger.error(
                    "Could not list removed built-in phrases; the settings list is empty."
                )
                return []
            }
        }
    }

    @discardableResult
    func deleteCharacterRecord(
        character: String,
        pronunciation: String
    ) -> Bool {
        clear(
            "a character record",
            identities: { _ in
                [try CloudUserDataIdentity(
                    character: character,
                    pronunciation: pronunciation
                )]
            }
        ) {
            try $0.deleteCharacterRecord(
                character: character,
                pronunciation: pronunciation
            )
        }
    }

    @discardableResult
    func deletePhrase(
        phrase: String,
        pronunciationSequence: [String]
    ) -> Bool {
        clear(
            "a user phrase",
            identities: { _ in
                [try CloudUserDataIdentity(
                    phrase: phrase,
                    readings: pronunciationSequence
                )]
            }
        ) {
            try $0.deletePhrase(
                phrase: phrase,
                pronunciationSequence: pronunciationSequence
            )
        }
    }

    /// Reads both data sets under one lock so an export is a consistent pair.
    func exportArchive(at date: Date = Date()) -> UserDataArchive? {
        queue.sync {
            guard let store else {
                return nil
            }
            do {
                return UserDataArchive.make(
                    characters: try store.allCharacterRecords(),
                    phrases: try store.allPhraseRecords(),
                    suppressions: try store.allSuppressedPhrases(),
                    exportedAt: date
                )
            } catch {
                Self.logger.error(
                    "Could not read user data for export; nothing was written."
                )
                return nil
            }
        }
    }

    /// Builds the word list this Mac would hand to another person: the user's
    /// own phrases plus the built-in phrases they removed. Selection counts,
    /// timestamps, and pins are deliberately left out of a shared pack.
    func exportPhrasePack(at date: Date = Date()) -> PhraseSharePack? {
        queue.sync {
            guard let store else {
                return nil
            }
            do {
                return PhraseSharePack.make(
                    phrases: try store.allPhraseRecords(),
                    removedBuiltInPhrases: try store.allSuppressedPhrases(),
                    exportedAt: date
                )
            } catch {
                Self.logger.error(
                    "Could not read the phrase list for sharing; nothing was written."
                )
                return nil
            }
        }
    }

    /// Merges someone else's word list into this one. Nothing is replaced: a
    /// shared phrase arrives with a zero count and no pin, so an existing
    /// entry keeps the recipient's own statistics.
    func importPhrasePack(
        _ pack: PhraseSharePack,
        includesRemovals: Bool,
        at date: Date = Date()
    ) -> UserDataMergeSummary? {
        merge(
            pack.archive(
                importedAt: date,
                includesRemovals: includesRemovals
            )
        )
    }

    func merge(_ archive: UserDataArchive) -> UserDataMergeSummary? {
        queue.sync {
            guard let store else {
                return nil
            }
            do {
                let summary = try store.merge(archive)
                for entry in archive.characters {
                    noteCharacterUpsert(
                        character: entry.character,
                        pronunciation: entry.pronunciation
                    )
                }
                for entry in archive.phrases {
                    notePhraseUpsert(
                        phrase: entry.phrase,
                        pronunciationSequence: entry.readings
                    )
                }
                for entry in archive.suppressions {
                    noteSuppressionUpsert(
                        phrase: entry.phrase,
                        pronunciationSequence: entry.readings
                    )
                }
                return summary
            } catch {
                Self.logger.error(
                    "Could not import user data; the existing data was kept."
                )
                return nil
            }
        }
    }

    private func clear(
        _ description: String,
        identities: (any UserLearningStoring) throws -> [CloudUserDataIdentity],
        operation: (any UserLearningStoring) throws -> Void
    ) -> Bool {
        queue.sync {
            guard let store else {
                return false
            }
            do {
                let deletedIdentities = try identities(store)
                try operation(store)
                for identity in deletedIdentities {
                    cloudSync?.noteDeletion(identity)
                }
                return true
            } catch {
                Self.logger.error(
                    "Could not clear \(description, privacy: .public); the existing data was kept."
                )
                return false
            }
        }
    }

    private func noteCharacterUpsert(
        character: String,
        pronunciation: String
    ) {
        guard let identity = try? CloudUserDataIdentity(
            character: character,
            pronunciation: pronunciation
        ) else {
            return
        }
        cloudSync?.noteUpsert(identity)
    }

    private func notePhraseUpsert(
        phrase: String,
        pronunciationSequence: [String]
    ) {
        guard let identity = try? CloudUserDataIdentity(
            phrase: phrase,
            readings: pronunciationSequence
        ) else {
            return
        }
        cloudSync?.noteUpsert(identity)
    }

    private func noteSuppressionUpsert(
        phrase: String,
        pronunciationSequence: [String]
    ) {
        guard let identity = try? CloudUserDataIdentity(
            suppressedPhrase: phrase,
            readings: pronunciationSequence
        ) else {
            return
        }
        cloudSync?.noteUpsert(identity)
    }
}


struct CantoneseLearningRecord: Codable, Equatable {
    let text: String
    let key: String
    let selectionCount: Int64
    let lastSelectedAt: Date?
}

/// Local-only candidate preference learning for Cantonese.
///
/// This deliberately stays outside `user.sqlite` and the current CloudKit
/// model because those identities validate Bopomofo readings. Keeping a
/// separate versioned file prevents Jyutping data from masquerading as Zhuyin
/// while still allowing Cantonese candidates to learn immediately.
final class CantoneseLearningService {
    static let shared = CantoneseLearningService()

    private struct Archive: Codable {
        static let currentVersion = 1
        let version: Int
        let records: [CantoneseLearningRecord]
    }

    private let queue: DispatchQueue
    private let fileURL: URL?
    private let fileManager: FileManager
    private let now: () -> Date
    private var recordsByKey: [String: [String: CantoneseLearningRecord]]
    private var cloudSync: CantoneseLearningCloudSyncing?
    private var preferencesObserver: NSObjectProtocol?

    private convenience init() {
        do {
            let location = try UserDataLocation.userDomain()
            try location.prepareDirectory()
            self.init(fileURL: location.cantoneseLearningURL)

            let preferences = PreferencesController.shared
            if ProcessEntitlements.isEntitledForICloudContainer(
                CloudKitUserDataTransport.containerIdentifier
            ) {
                let coordinator = CantoneseLearningCloudSyncCoordinator(
                    transport: CloudKitCantoneseLearningTransport(),
                    isEnabled: {
                        preferences.current.iCloudSyncEnabled
                    },
                    localRecords: { [weak self] in
                        self?.allRecords() ?? []
                    },
                    mergeRemoteRecords: { [weak self] records in
                        self?.mergeRemote(records) ?? []
                    }
                )
                cloudSync = coordinator
                preferencesObserver = NotificationCenter.default.addObserver(
                    forName: PreferencesController.didChangeNotification,
                    object: preferences,
                    queue: nil
                ) { [weak self] _ in
                    self?.cloudSync?.preferenceDidChange()
                }
                coordinator.start()
            }
        } catch {
            self.init(fileURL: nil)
        }
    }

    init(
        fileURL: URL?,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init,
        queueLabel: String = "tw.idv.jiukong.cantonese-learning"
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.now = now
        queue = DispatchQueue(label: queueLabel, qos: .userInitiated)
        recordsByKey = Self.load(fileURL: fileURL, fileManager: fileManager)
        cloudSync = nil
        preferencesObserver = nil
    }

    deinit {
        if let preferencesObserver {
            NotificationCenter.default.removeObserver(preferencesObserver)
        }
    }

    func records(for key: String) -> [String: CantoneseLearningRecord] {
        queue.sync {
            recordsByKey[key] ?? [:]
        }
    }

    func recordSelection(text: String, key: String) {
        guard !text.isEmpty, !key.isEmpty else {
            return
        }

        queue.sync {
            let old = recordsByKey[key]?[text]
            let count = old?.selectionCount ?? 0
            let nextCount = count == Int64.max ? Int64.max : count + 1
            let record = CantoneseLearningRecord(
                text: text,
                key: key,
                selectionCount: nextCount,
                lastSelectedAt: now()
            )
            recordsByKey[key, default: [:]][text] = record
            persist()
            cloudSync?.noteLocalChange()
        }
    }

    func allRecords() -> [CantoneseLearningRecord] {
        queue.sync {
            Self.sortedRecords(recordsByKey)
        }
    }

    @discardableResult
    func mergeRemote(
        _ remoteRecords: [CantoneseLearningRecord]
    ) -> [CantoneseLearningRecord] {
        queue.sync {
            var changed = false
            for record in remoteRecords
            where !record.text.isEmpty && !record.key.isEmpty {
                let existing = recordsByKey[record.key]?[record.text]
                if Self.shouldPrefer(record, over: existing) {
                    recordsByKey[record.key, default: [:]][record.text] = record
                    changed = true
                }
            }
            if changed {
                persist()
            }
            return Self.sortedRecords(recordsByKey)
        }
    }

    private func persist() {
        guard let fileURL else {
            return
        }

        let allRecords = Self.sortedRecords(recordsByKey)
        let archive = Archive(
            version: Archive.currentVersion,
            records: allRecords
        )
        guard let data = try? JSONEncoder().encode(archive) else {
            return
        }

        do {
            try data.write(to: fileURL, options: .atomic)
            try? fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch {
            // Personalization is best-effort; input must keep working even if
            // the user data location becomes temporarily unwritable.
        }
    }

    private static func load(
        fileURL: URL?,
        fileManager: FileManager
    ) -> [String: [String: CantoneseLearningRecord]] {
        guard let fileURL,
              fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let archive = try? JSONDecoder().decode(Archive.self, from: data),
              archive.version == Archive.currentVersion else {
            return [:]
        }

        var result: [String: [String: CantoneseLearningRecord]] = [:]
        for record in archive.records
        where !record.text.isEmpty && !record.key.isEmpty {
            let existing = result[record.key]?[record.text]
            if shouldPrefer(record, over: existing) {
                result[record.key, default: [:]][record.text] = record
            }
        }
        return result
    }

    private static func shouldPrefer(
        _ candidate: CantoneseLearningRecord,
        over existing: CantoneseLearningRecord?
    ) -> Bool {
        guard let existing else {
            return true
        }
        if candidate.selectionCount != existing.selectionCount {
            return candidate.selectionCount > existing.selectionCount
        }
        return (candidate.lastSelectedAt ?? .distantPast)
            > (existing.lastSelectedAt ?? .distantPast)
    }

    private static func sortedRecords(
        _ recordsByKey: [String: [String: CantoneseLearningRecord]]
    ) -> [CantoneseLearningRecord] {
        recordsByKey.values
            .flatMap { $0.values }
            .sorted {
                if $0.key != $1.key {
                    return $0.key < $1.key
                }
                return $0.text < $1.text
            }
    }
}


protocol CantoneseLearningCloudSyncing: AnyObject {
    func start()
    func noteLocalChange()
    func preferenceDidChange()
}

protocol CantoneseLearningCloudTransporting: AnyObject {
    func fetch(
        completion: @escaping (Result<[CantoneseLearningRecord], Error>) -> Void
    )

    func save(
        _ records: [CantoneseLearningRecord],
        completion: @escaping (Result<Void, Error>) -> Void
    )
}

final class CantoneseLearningCloudSyncCoordinator:
    CantoneseLearningCloudSyncing
{
    private let queue = DispatchQueue(
        label: "tw.idv.jiukong.cantonese-learning-cloud",
        qos: .utility
    )
    private let transport: CantoneseLearningCloudTransporting
    private let isEnabled: () -> Bool
    private let localRecords: () -> [CantoneseLearningRecord]
    private let mergeRemoteRecords:
        ([CantoneseLearningRecord]) -> [CantoneseLearningRecord]
    private var debounceWorkItem: DispatchWorkItem?
    private var synchronizing = false
    private var synchronizeAgain = false

    init(
        transport: CantoneseLearningCloudTransporting,
        isEnabled: @escaping () -> Bool,
        localRecords: @escaping () -> [CantoneseLearningRecord],
        mergeRemoteRecords:
            @escaping ([CantoneseLearningRecord]) -> [CantoneseLearningRecord]
    ) {
        self.transport = transport
        self.isEnabled = isEnabled
        self.localRecords = localRecords
        self.mergeRemoteRecords = mergeRemoteRecords
    }

    func start() {
        queue.async { [weak self] in
            self?.synchronize()
        }
    }

    func preferenceDidChange() {
        queue.async { [weak self] in
            guard let self, isEnabled() else {
                return
            }
            synchronize()
        }
    }

    func noteLocalChange() {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            debounceWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.synchronize()
            }
            debounceWorkItem = work
            queue.asyncAfter(deadline: .now() + 1.5, execute: work)
        }
    }

    private func synchronize() {
        guard isEnabled() else {
            return
        }
        if synchronizing {
            synchronizeAgain = true
            return
        }

        synchronizing = true
        transport.fetch { [weak self] result in
            guard let self else {
                return
            }
            queue.async {
                switch result {
                case let .failure(error):
                    Self.log(error)
                    finish()
                case let .success(remote):
                    let merged = mergeRemoteRecords(remote)
                    let local = merged.isEmpty ? localRecords() : merged
                    transport.save(local) { [weak self] saveResult in
                        guard let self else {
                            return
                        }
                        queue.async {
                            if case let .failure(error) = saveResult {
                                Self.log(error)
                            }
                            finish()
                        }
                    }
                }
            }
        }
    }

    private func finish() {
        synchronizing = false
        if synchronizeAgain {
            synchronizeAgain = false
            synchronize()
        }
    }

    private static func log(_ error: Error) {
        Logger(
            subsystem: "tw.idv.jiukong.inputmethod.zhuyin",
            category: "CantoneseCloudLearning"
        ).error(
            "Cantonese iCloud learning sync failed: \(error.localizedDescription, privacy: .public)"
        )
    }
}

final class CloudKitCantoneseLearningTransport:
    CantoneseLearningCloudTransporting
{
    static let recordType = "JKCantoneseLearning"
    private static let recordName = "v1-learning"
    private static let schemaVersion: Int64 = 1
    private static let schemaField = "schemaVersion"
    private static let payloadField = "payload"

    private let container: CKContainer
    private let database: CKDatabase
    private let lock = NSLock()
    private var cachedRecord: CKRecord?

    init(
        container: CKContainer = CKContainer(
            identifier: CloudKitUserDataTransport.containerIdentifier
        )
    ) {
        self.container = container
        database = container.privateCloudDatabase
    }

    func fetch(
        completion: @escaping (Result<[CantoneseLearningRecord], Error>) -> Void
    ) {
        container.accountStatus { [weak self] status, error in
            guard let self else {
                return
            }
            if let error {
                completion(.failure(error))
                return
            }
            guard status == .available else {
                completion(.failure(Self.accountError(status)))
                return
            }

            let recordID = CKRecord.ID(recordName: Self.recordName)
            database.fetch(withRecordID: recordID) {
                [weak self] record, error in
                guard let self else {
                    return
                }
                if let ckError = error as? CKError,
                   ckError.code == .unknownItem {
                    lock.lock()
                    cachedRecord = nil
                    lock.unlock()
                    completion(.success([]))
                    return
                }
                if let error {
                    completion(.failure(error))
                    return
                }
                guard let record else {
                    completion(.success([]))
                    return
                }
                do {
                    let records = try Self.decode(record)
                    lock.lock()
                    cachedRecord = record
                    lock.unlock()
                    completion(.success(records))
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    func save(
        _ records: [CantoneseLearningRecord],
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        do {
            let data = try JSONEncoder().encode(records)
            lock.lock()
            let record = cachedRecord ?? CKRecord(
                recordType: Self.recordType,
                recordID: CKRecord.ID(recordName: Self.recordName)
            )
            lock.unlock()

            record[Self.schemaField] = NSNumber(value: Self.schemaVersion)
            record.encryptedValues[Self.payloadField] = data as NSData

            database.save(record) { [weak self] saved, error in
                if let error {
                    completion(.failure(error))
                    return
                }
                if let saved {
                    self?.lock.lock()
                    self?.cachedRecord = saved
                    self?.lock.unlock()
                }
                completion(.success(()))
            }
        } catch {
            completion(.failure(error))
        }
    }

    private static func decode(
        _ record: CKRecord
    ) throws -> [CantoneseLearningRecord] {
        guard record.recordType == recordType,
              (record[schemaField] as? NSNumber)?.int64Value
                == schemaVersion,
              let data = record.encryptedValues[payloadField] as? Data else {
            throw CloudUserDataModelError.invalidPayload
        }
        return try JSONDecoder().decode(
            [CantoneseLearningRecord].self,
            from: data
        )
    }

    private static func accountError(
        _ status: CKAccountStatus
    ) -> Error {
        switch status {
        case .noAccount:
            return CloudKitUserDataTransportError.noAccount
        case .restricted:
            return CloudKitUserDataTransportError.accountRestricted
        case .temporarilyUnavailable:
            return CloudKitUserDataTransportError
                .accountTemporarilyUnavailable
        case .couldNotDetermine, .available:
            return CloudKitUserDataTransportError.accountStatusUnknown
        @unknown default:
            return CloudKitUserDataTransportError.accountStatusUnknown
        }
    }
}
