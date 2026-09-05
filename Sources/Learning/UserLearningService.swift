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
