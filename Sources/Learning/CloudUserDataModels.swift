import CryptoKit
import Foundation

/// The stable identity of one independently mergeable learning record.
///
/// CloudKit record names use a digest of this value, so neither selected text
/// nor its Bopomofo readings leak through record metadata. The actual fields
/// are stored with CloudKit's encrypted-values API by the transport.
struct CloudUserDataIdentity: Codable, Equatable, Hashable {
    enum Kind: String, Codable {
        case character
        case phrase
    }

    let kind: Kind
    let text: String
    let readings: [String]

    init(character: String, pronunciation: String) throws {
        let normalizedCharacter = character.precomposedStringWithCanonicalMapping
        let normalizedPronunciation = pronunciation
            .precomposedStringWithCanonicalMapping
        guard normalizedCharacter.count == 1,
              CanonicalBopomofoReading.isValid(normalizedPronunciation) else {
            throw CloudUserDataModelError.invalidCharacterIdentity
        }
        kind = .character
        text = normalizedCharacter
        readings = [normalizedPronunciation]
    }

    init(phrase: String, readings: [String]) throws {
        let validated = try UserPhraseValidator.validate(
            phrase: phrase,
            pronunciationSequence: readings
        )
        kind = .phrase
        text = validated.phrase
        self.readings = validated.pronunciationSequence
    }

    /// Bounded, deterministic, and opaque enough to use as a CloudKit name and
    /// as the key in the local pending-mutation journal.
    var recordName: String {
        var bytes = Data("jiukong-cloud-user-data-v1\u{0}".utf8)
        bytes.append(contentsOf: kind.rawValue.utf8)
        appendLengthPrefixed(Data(text.utf8), to: &bytes)
        for reading in readings {
            appendLengthPrefixed(Data(reading.utf8), to: &bytes)
        }
        let digest = SHA256.hash(data: bytes)
        return "v1-" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private func appendLengthPrefixed(_ value: Data, to data: inout Data) {
        var length = UInt64(value.count).bigEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(value)
    }
}

enum CloudUserDataModelError: LocalizedError, Equatable {
    case invalidCharacterIdentity
    case identityKindMismatch
    case invalidRecordName
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .invalidCharacterIdentity:
            return "The cloud character identity is invalid."
        case .identityKindMismatch:
            return "The cloud record kind does not match its payload."
        case .invalidRecordName:
            return "The cloud record name does not match its identity."
        case .invalidPayload:
            return "The cloud learning record contains invalid data."
        }
    }
}

/// A normalized record exchanged with the CloudKit transport. Deletions stay
/// as tombstones so a Mac that was offline cannot restore a removed entry.
struct CloudUserDataRecord: Equatable {
    enum Payload: Equatable {
        case character(ArchivedCharacter)
        case phrase(ArchivedPhrase)
        case deleted
    }

    let identity: CloudUserDataIdentity
    let payload: Payload

    init(identity: CloudUserDataIdentity, payload: Payload) throws {
        switch (identity.kind, payload) {
        case (.character, .character), (.phrase, .phrase), (_, .deleted):
            break
        default:
            throw CloudUserDataModelError.identityKindMismatch
        }
        self.identity = identity
        self.payload = payload
    }

    static func character(_ record: CharacterLearningRecord) throws -> Self {
        let identity = try CloudUserDataIdentity(
            character: record.character,
            pronunciation: record.pronunciation
        )
        return try Self(
            identity: identity,
            payload: .character(
                ArchivedCharacter(
                    character: record.character,
                    pronunciation: record.pronunciation,
                    selectionCount: record.selectionCount,
                    lastSelectedAt: record.lastSelectedAt.map(milliseconds),
                    pinned: record.pinned
                )
            )
        )
    }

    static func phrase(_ record: UserPhraseRecord) throws -> Self {
        let identity = try CloudUserDataIdentity(
            phrase: record.phrase,
            readings: record.pronunciationSequence
        )
        return try Self(
            identity: identity,
            payload: .phrase(
                ArchivedPhrase(
                    phrase: record.phrase,
                    readings: record.pronunciationSequence,
                    selectionCount: record.selectionCount,
                    createdAt: milliseconds(record.createdAt),
                    lastUsedAt: record.lastUsedAt.map(milliseconds),
                    pinned: record.pinned
                )
            )
        )
    }

    static func tombstone(_ identity: CloudUserDataIdentity) throws -> Self {
        try Self(identity: identity, payload: .deleted)
    }

    var archive: UserDataArchive? {
        switch payload {
        case let .character(character):
            return UserDataArchive(
                exportedAt: 0,
                characters: [character],
                phrases: []
            )
        case let .phrase(phrase):
            return UserDataArchive(
                exportedAt: 0,
                characters: [],
                phrases: [phrase]
            )
        case .deleted:
            return nil
        }
    }

    var pinned: Bool? {
        switch payload {
        case let .character(record):
            return record.pinned
        case let .phrase(record):
            return record.pinned
        case .deleted:
            return nil
        }
    }

    private static func milliseconds(_ date: Date) -> Int64 {
        let value = date.timeIntervalSince1970 * 1_000
        if value >= Double(Int64.max) {
            return Int64.max
        }
        if value <= Double(Int64.min) {
            return Int64.min
        }
        return Int64(value.rounded(.towardZero))
    }
}

enum CloudSyncMutationAction: String, Codable, Equatable {
    case upsert
    case delete
}

struct CloudSyncPendingMutation: Codable, Equatable {
    let identity: CloudUserDataIdentity
    let action: CloudSyncMutationAction
    let revision: Int64
}

struct CloudSyncPersistedState: Codable, Equatable {
    static let currentVersion = 1

    var version = currentVersion
    var completedInitialMerge = false
    var nextRevision: Int64 = 1
    var pending: [String: CloudSyncPendingMutation] = [:]

    mutating func note(
        _ action: CloudSyncMutationAction,
        identity: CloudUserDataIdentity
    ) {
        let revision = nextRevision
        if nextRevision < Int64.max {
            nextRevision += 1
        }
        pending[identity.recordName] = CloudSyncPendingMutation(
            identity: identity,
            action: action,
            revision: revision
        )
    }

    mutating func clear(_ mutations: [CloudSyncPendingMutation]) {
        for mutation in mutations
            where pending[mutation.identity.recordName] == mutation {
            pending.removeValue(forKey: mutation.identity.recordName)
        }
    }

    func validated() -> CloudSyncPersistedState? {
        guard version == Self.currentVersion,
              nextRevision >= 1,
              pending.allSatisfy({ key, mutation in
                  key == mutation.identity.recordName && mutation.revision >= 1
              }) else {
            return nil
        }
        return self
    }
}
