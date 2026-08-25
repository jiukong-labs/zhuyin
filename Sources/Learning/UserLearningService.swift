import Foundation
import os

enum UserLearningMutation: String, Equatable {
    case mergeable
    case replacement

    var requiresReplacement: Bool {
        self == .replacement
    }

    init(notification: Notification) {
        guard let rawValue = notification.userInfo?[
            UserLearningService.mutationUserInfoKey
        ] as? String,
              let mutation = UserLearningMutation(rawValue: rawValue) else {
            self = .mergeable
            return
        }
        self = mutation
    }
}

final class UserLearningService: UserLearningProviding {
    static let didChangeNotification = Notification.Name(
        "tw.idv.jiukong.UserLearningDidChange"
    )
    static let mutationUserInfoKey = "mutation"

    static let shared = UserLearningService()

    private static let logger = Logger(
        subsystem: "tw.idv.jiukong.inputmethod.zhuyin",
        category: "UserLearning"
    )

    private let queue: DispatchQueue
    private let store: UserLearningStoring?
    private let now: () -> Date
    private let notificationCenter: NotificationCenter

    private convenience init() {
        let store: UserLearningStoring?
        do {
            let location = try UserDataLocation.userDomain()
            store = try UserLearningStore(location: location)
        } catch {
            Self.logger.error(
                "User learning storage is unavailable; personalization is disabled."
            )
            store = nil
        }
        self.init(store: store)
    }

    init(
        store: UserLearningStoring?,
        now: @escaping () -> Date = Date.init,
        notificationCenter: NotificationCenter = .default,
        queueLabel: String = "tw.idv.jiukong.user-learning"
    ) {
        self.store = store
        self.now = now
        self.notificationCenter = notificationCenter
        queue = DispatchQueue(label: queueLabel, qos: .userInitiated)
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
        let changed: Bool = queue.sync {
            guard let store else {
                return false
            }
            do {
                try store.recordSelection(
                    character: character,
                    pronunciation: pronunciation,
                    at: now()
                )
                return true
            } catch {
                Self.logger.error(
                    "Could not update user learning data; input will continue."
                )
                return false
            }
        }
        if changed {
            notifyChange(.mergeable)
        }
    }

    func setPinned(
        _ pinned: Bool,
        character: String,
        pronunciation: String
    ) {
        let changed: Bool = queue.sync {
            guard let store else {
                return false
            }
            do {
                try store.setPinned(
                    pinned,
                    character: character,
                    pronunciation: pronunciation
                )
                return true
            } catch {
                Self.logger.error(
                    "Could not update a user learning pin; input will continue."
                )
                return false
            }
        }
        if changed {
            notifyChange(pinned ? .mergeable : .replacement)
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
        let changed: Bool = queue.sync {
            guard let store else {
                return false
            }
            do {
                try store.addPhrase(
                    phrase: phrase,
                    pronunciationSequence: pronunciationSequence,
                    createdAt: createdAt
                )
                return true
            } catch {
                Self.logger.error(
                    "Could not add a user phrase; input will continue."
                )
                return false
            }
        }
        if changed {
            notifyChange(.mergeable)
        }
        return changed
    }

    func recordPhraseSelection(
        phrase: String,
        pronunciationSequence: [String],
        at date: Date
    ) {
        let changed: Bool = queue.sync {
            guard let store else {
                return false
            }
            do {
                try store.recordPhraseSelection(
                    phrase: phrase,
                    pronunciationSequence: pronunciationSequence,
                    at: date
                )
                return true
            } catch {
                Self.logger.error(
                    "Could not update user phrase learning; input will continue."
                )
                return false
            }
        }
        if changed {
            notifyChange(.mergeable)
        }
    }

    func setPhrasePinned(
        _ pinned: Bool,
        phrase: String,
        pronunciationSequence: [String]
    ) {
        let changed: Bool = queue.sync {
            guard let store else {
                return false
            }
            do {
                try store.setPhrasePinned(
                    pinned,
                    phrase: phrase,
                    pronunciationSequence: pronunciationSequence
                )
                return true
            } catch {
                Self.logger.error(
                    "Could not update a user phrase pin; input will continue."
                )
                return false
            }
        }
        if changed {
            notifyChange(pinned ? .mergeable : .replacement)
        }
    }

    /// Reports success so the settings window can tell the user that a clear
    /// request did not take effect instead of silently appearing to succeed.
    @discardableResult
    func clearCharacterLearning() -> Bool {
        clear("character learning") { try $0.clearCharacterLearning() }
    }

    @discardableResult
    func clearUserPhrases() -> Bool {
        clear("user phrases") { try $0.clearUserPhrases() }
    }

    @discardableResult
    func clearAllUserData() -> Bool {
        clear("all user data") { try $0.clearAllUserData() }
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

    @discardableResult
    func deleteCharacterRecord(
        character: String,
        pronunciation: String
    ) -> Bool {
        clear("a character record") {
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
        clear("a user phrase") {
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

    func merge(
        _ archive: UserDataArchive,
        notifyChange: Bool = true
    ) -> UserDataMergeSummary? {
        let summary: UserDataMergeSummary? = queue.sync {
            guard let store else {
                return nil
            }
            do {
                return try store.merge(archive)
            } catch {
                Self.logger.error(
                    "Could not import user data; the existing data was kept."
                )
                return nil
            }
        }
        if summary != nil, notifyChange {
            self.notifyChange(.mergeable)
        }
        return summary
    }

    private func clear(
        _ description: String,
        operation: (any UserLearningStoring) throws -> Void
    ) -> Bool {
        let changed: Bool = queue.sync {
            guard let store else {
                return false
            }
            do {
                try operation(store)
                return true
            } catch {
                Self.logger.error(
                    "Could not clear \(description, privacy: .public); the existing data was kept."
                )
                return false
            }
        }
        if changed {
            notifyChange(.replacement)
        }
        return changed
    }

    private func notifyChange(_ mutation: UserLearningMutation) {
        notificationCenter.post(
            name: Self.didChangeNotification,
            object: self,
            userInfo: [Self.mutationUserInfoKey: mutation.rawValue]
        )
    }
}
