import Foundation
import os

final class UserLearningService: UserLearningProviding {
    static let shared = UserLearningService()

    private static let logger = Logger(
        subsystem: "tw.org.cloudgate.jiukong.inputmethod.zhuyin",
        category: "UserLearning"
    )

    private let queue: DispatchQueue
    private let store: UserLearningStoring?
    private let now: () -> Date

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
        queueLabel: String = "tw.org.cloudgate.jiukong.user-learning"
    ) {
        self.store = store
        self.now = now
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
        queue.sync {
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
            } catch {
                Self.logger.error(
                    "Could not update a user phrase pin; input will continue."
                )
            }
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

    private func clear(
        _ description: String,
        operation: (any UserLearningStoring) throws -> Void
    ) -> Bool {
        queue.sync {
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
    }
}
