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

}
