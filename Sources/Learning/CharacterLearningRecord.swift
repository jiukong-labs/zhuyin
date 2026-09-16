import Foundation

struct CharacterLearningRecord: Equatable {
    let character: String
    let pronunciation: String
    let selectionCount: Int64
    let lastSelectedAt: Date?
    let pinned: Bool
}

protocol UserLearningProviding: AnyObject {
    func records(for pronunciation: String) -> [String: CharacterLearningRecord]
    func recordSelection(character: String, pronunciation: String)

    func setPinned(
        _ pinned: Bool,
        character: String,
        pronunciation: String
    )

    func phraseRecords(
        for pronunciationSequence: [String]
    ) -> [UserPhraseRecord]

    @discardableResult
    func addPhrase(
        phrase: String,
        pronunciationSequence: [String],
        createdAt: Date
    ) -> Bool

    @discardableResult
    func addPhrase(
        phrase: String,
        pronunciationSequence: [String],
        outputPattern: PhraseOutputPattern,
        createdAt: Date
    ) -> Bool

    func recordPhraseSelection(
        phrase: String,
        pronunciationSequence: [String],
        at date: Date
    )

    func setPhrasePinned(
        _ pinned: Bool,
        phrase: String,
        pronunciationSequence: [String]
    )

    @discardableResult
    func deletePhrase(
        phrase: String,
        pronunciationSequence: [String]
    ) -> Bool

    /// The built-in phrase texts the user removed for this exact reading
    /// sequence. Candidate lookup drops them from the dictionary's own
    /// results.
    func suppressedPhrases(
        for pronunciationSequence: [String]
    ) -> Set<String>

    @discardableResult
    func suppressPhrase(
        phrase: String,
        pronunciationSequence: [String],
        at date: Date
    ) -> Bool

    @discardableResult
    func restorePhrase(
        phrase: String,
        pronunciationSequence: [String]
    ) -> Bool
}

extension UserLearningProviding {
    func setPinned(
        _ pinned: Bool,
        character: String,
        pronunciation: String
    ) {}

    func phraseRecords(
        for pronunciationSequence: [String]
    ) -> [UserPhraseRecord] {
        []
    }

    @discardableResult
    func addPhrase(
        phrase: String,
        pronunciationSequence: [String],
        createdAt: Date
    ) -> Bool {
        false
    }

    @discardableResult
    func addPhrase(
        phrase: String,
        pronunciationSequence: [String],
        outputPattern: PhraseOutputPattern,
        createdAt: Date
    ) -> Bool {
        addPhrase(
            phrase: phrase,
            pronunciationSequence: pronunciationSequence,
            createdAt: createdAt
        )
    }

    func recordPhraseSelection(
        phrase: String,
        pronunciationSequence: [String],
        at date: Date
    ) {}

    func setPhrasePinned(
        _ pinned: Bool,
        phrase: String,
        pronunciationSequence: [String]
    ) {}

    @discardableResult
    func deletePhrase(
        phrase: String,
        pronunciationSequence: [String]
    ) -> Bool {
        false
    }

    func suppressedPhrases(
        for pronunciationSequence: [String]
    ) -> Set<String> {
        []
    }

    @discardableResult
    func suppressPhrase(
        phrase: String,
        pronunciationSequence: [String],
        at date: Date
    ) -> Bool {
        false
    }

    @discardableResult
    func restorePhrase(
        phrase: String,
        pronunciationSequence: [String]
    ) -> Bool {
        false
    }
}

protocol UserLearningStoring: AnyObject {
    func records(
        for pronunciation: String
    ) throws -> [String: CharacterLearningRecord]

    func recordSelection(
        character: String,
        pronunciation: String,
        at date: Date
    ) throws

    func setPinned(
        _ pinned: Bool,
        character: String,
        pronunciation: String
    ) throws

    func phraseRecords(
        for pronunciationSequence: [String]
    ) throws -> [UserPhraseRecord]

    func addPhrase(
        phrase: String,
        pronunciationSequence: [String],
        createdAt: Date
    ) throws

    func addPhrase(
        phrase: String,
        pronunciationSequence: [String],
        outputPattern: PhraseOutputPattern,
        createdAt: Date
    ) throws

    func recordPhraseSelection(
        phrase: String,
        pronunciationSequence: [String],
        at date: Date
    ) throws

    func setPhrasePinned(
        _ pinned: Bool,
        phrase: String,
        pronunciationSequence: [String]
    ) throws

    func suppressedPhrases(
        for pronunciationSequence: [String]
    ) throws -> Set<String>

    func suppressPhrase(
        phrase: String,
        pronunciationSequence: [String],
        at date: Date
    ) throws

    func restorePhrase(
        phrase: String,
        pronunciationSequence: [String]
    ) throws

    func clearCharacterLearning() throws
    func clearUserPhrases() throws
    func clearSuppressedPhrases() throws
    func clearAllUserData() throws

    func allCharacterRecords() throws -> [CharacterLearningRecord]
    func allPhraseRecords() throws -> [UserPhraseRecord]
    func allSuppressedPhrases() throws -> [SuppressedPhraseRecord]

    func deleteCharacterRecord(
        character: String,
        pronunciation: String
    ) throws

    func deletePhrase(
        phrase: String,
        pronunciationSequence: [String]
    ) throws

    @discardableResult
    func merge(_ archive: UserDataArchive) throws -> UserDataMergeSummary
}

extension UserLearningStoring {
    func phraseRecords(
        for pronunciationSequence: [String]
    ) throws -> [UserPhraseRecord] {
        []
    }

    func addPhrase(
        phrase: String,
        pronunciationSequence: [String],
        createdAt: Date
    ) throws {}

    func addPhrase(
        phrase: String,
        pronunciationSequence: [String],
        outputPattern: PhraseOutputPattern,
        createdAt: Date
    ) throws {
        try addPhrase(
            phrase: phrase,
            pronunciationSequence: pronunciationSequence,
            createdAt: createdAt
        )
    }

    func recordPhraseSelection(
        phrase: String,
        pronunciationSequence: [String],
        at date: Date
    ) throws {}

    func setPhrasePinned(
        _ pinned: Bool,
        phrase: String,
        pronunciationSequence: [String]
    ) throws {}

    func suppressedPhrases(
        for pronunciationSequence: [String]
    ) throws -> Set<String> {
        []
    }

    func suppressPhrase(
        phrase: String,
        pronunciationSequence: [String],
        at date: Date
    ) throws {}

    func restorePhrase(
        phrase: String,
        pronunciationSequence: [String]
    ) throws {}

    func clearCharacterLearning() throws {}
    func clearUserPhrases() throws {}
    func clearSuppressedPhrases() throws {}
    func clearAllUserData() throws {}

    func allCharacterRecords() throws -> [CharacterLearningRecord] {
        []
    }

    func allPhraseRecords() throws -> [UserPhraseRecord] {
        []
    }

    func allSuppressedPhrases() throws -> [SuppressedPhraseRecord] {
        []
    }

    func deleteCharacterRecord(
        character: String,
        pronunciation: String
    ) throws {}

    func deletePhrase(
        phrase: String,
        pronunciationSequence: [String]
    ) throws {}

    @discardableResult
    func merge(_ archive: UserDataArchive) throws -> UserDataMergeSummary {
        UserDataMergeSummary()
    }
}

/// One user-authored alias between a single character and one canonical
/// Bopomofo reading. It augments the bundled dictionary instead of editing it.
struct CustomReadingRecord: Equatable, Hashable, Codable {
    let character: String
    let pronunciation: String
    let createdAt: Date
    let updatedAt: Date
}

enum CustomReadingValidationError: LocalizedError, Equatable {
    case invalidCharacter
    case invalidPronunciation

    var errorDescription: String? {
        switch self {
        case .invalidCharacter:
            return "自訂讀音一次只能指定一個字。"
        case .invalidPronunciation:
            return "請輸入完整且合法的注音，例如「ㄅㄛ」或「ㄅㄛˋ」。"
        }
    }
}

struct ValidatedCustomReading: Equatable {
    let character: String
    let pronunciation: String
}

enum CustomReadingValidator {
    static func validate(
        character: String,
        pronunciation: String
    ) throws -> ValidatedCustomReading {
        let normalizedCharacter = normalizeTextFieldInput(character)
        let normalizedPronunciation = normalizeTextFieldInput(pronunciation)

        guard normalizedCharacter.count == 1 else {
            throw CustomReadingValidationError.invalidCharacter
        }
        guard CanonicalBopomofoReading.isValid(normalizedPronunciation) else {
            throw CustomReadingValidationError.invalidPronunciation
        }
        return ValidatedCustomReading(
            character: normalizedCharacter,
            pronunciation: normalizedPronunciation
        )
    }

    /// AppKit field editors can leave non-printing control or formatting
    /// scalars around marked text while an input method commits composition.
    /// They are not part of a character or a Bopomofo reading, so discard them
    /// before validating the user's visible input. Variation selectors are not
    /// format scalars and remain intact as part of the visible character.
    private static func normalizeTextFieldInput(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.unicodeScalars
            .filter { scalar in
                if scalar.value == 0xFFFC {
                    return false
                }
                switch scalar.properties.generalCategory {
                case .control, .format:
                    return false
                default:
                    return true
                }
            }
            .map { String($0) }
            .joined()
        return cleaned.precomposedStringWithCanonicalMapping
    }
}

protocol CustomReadingProviding: AnyObject {
    func customReadings(for pronunciation: String) -> [CustomReadingRecord]
}

protocol CustomReadingManaging: CustomReadingProviding {
    func allCustomReadings() -> [CustomReadingRecord]

    @discardableResult
    func upsertCustomReading(
        character: String,
        pronunciation: String
    ) -> Bool

    @discardableResult
    func replaceCustomReading(
        _ oldRecord: CustomReadingRecord,
        character: String,
        pronunciation: String
    ) -> Bool

    @discardableResult
    func deleteCustomReading(
        character: String,
        pronunciation: String
    ) -> Bool
}

/// A deliberately separate persistence layer for pronunciation aliases.
///
/// Keeping aliases out of the bundled dictionary means a dictionary update can
/// never overwrite a user's preferred reading. Keeping them outside the
/// learning SQLite schema also lets this feature evolve independently from
/// selection-frequency data.
final class CustomReadingService: CustomReadingManaging {
    static let didChangeNotification = Notification.Name(
        "tw.idv.jiukong.inputmethod.zhuyin.custom-readings-changed"
    )
    static let shared = CustomReadingService()

    private static let formatIdentifier = "jiukong-zhuyin-custom-readings"
    private static let currentVersion = 1
    private static let fileName = "custom-readings.json"

    private struct Document: Codable {
        let format: String
        let version: Int
        let records: [CustomReadingRecord]
    }

    private let fileURL: URL?
    private let fileManager: FileManager
    private let now: () -> Date
    private let lock = NSRecursiveLock()
    private var recordsByIdentity: [String: CustomReadingRecord] = [:]

    private convenience init() {
        // The provider's default dependency must not make unit tests depend on
        // whichever custom readings happen to exist in the developer account.
        // Tests that exercise this feature use the explicit fileURL initializer.
        let environment = ProcessInfo.processInfo.environment
        if environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil {
            self.init(fileURL: nil)
            return
        }

        let fileURL: URL?
        do {
            let location = try UserDataLocation.userDomain()
            try location.prepareDirectory()
            fileURL = location.directoryURL.appendingPathComponent(
                Self.fileName,
                isDirectory: false
            )
        } catch {
            fileURL = nil
        }
        self.init(fileURL: fileURL)
    }

    /// Internal initializer keeps persistence deterministic in unit tests.
    init(
        fileURL: URL?,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.now = now
        loadFromDisk()
    }

    func customReadings(for pronunciation: String) -> [CustomReadingRecord] {
        let reading = pronunciation
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
        guard CanonicalBopomofoReading.isValid(reading) else {
            return []
        }
        return withRecordsLock {
            recordsByIdentity.values
                .filter { $0.pronunciation == reading }
                .sorted(by: Self.recordSort)
        }
    }

    func allCustomReadings() -> [CustomReadingRecord] {
        withRecordsLock {
            recordsByIdentity.values.sorted(by: Self.recordSort)
        }
    }

    @discardableResult
    func upsertCustomReading(
        character: String,
        pronunciation: String
    ) -> Bool {
        guard let validated = try? CustomReadingValidator.validate(
            character: character,
            pronunciation: pronunciation
        ) else {
            return false
        }

        let changed = withRecordsLock { () -> Bool in
            let identity = Self.identity(
                character: validated.character,
                pronunciation: validated.pronunciation
            )
            let previous = recordsByIdentity
            let timestamp = now()
            let existing = recordsByIdentity[identity]
            recordsByIdentity[identity] = CustomReadingRecord(
                character: validated.character,
                pronunciation: validated.pronunciation,
                createdAt: existing?.createdAt ?? timestamp,
                updatedAt: timestamp
            )
            guard persistLocked() else {
                recordsByIdentity = previous
                return false
            }
            return true
        }
        if changed {
            postDidChange()
        }
        return changed
    }

    @discardableResult
    func replaceCustomReading(
        _ oldRecord: CustomReadingRecord,
        character: String,
        pronunciation: String
    ) -> Bool {
        guard let validated = try? CustomReadingValidator.validate(
            character: character,
            pronunciation: pronunciation
        ) else {
            return false
        }

        let changed = withRecordsLock { () -> Bool in
            let oldIdentity = Self.identity(
                character: oldRecord.character,
                pronunciation: oldRecord.pronunciation
            )
            guard recordsByIdentity[oldIdentity] != nil else {
                return false
            }

            let previous = recordsByIdentity
            recordsByIdentity.removeValue(forKey: oldIdentity)
            let newIdentity = Self.identity(
                character: validated.character,
                pronunciation: validated.pronunciation
            )
            let existing = recordsByIdentity[newIdentity]
            recordsByIdentity[newIdentity] = CustomReadingRecord(
                character: validated.character,
                pronunciation: validated.pronunciation,
                createdAt: min(
                    oldRecord.createdAt,
                    existing?.createdAt ?? oldRecord.createdAt
                ),
                updatedAt: now()
            )
            guard persistLocked() else {
                recordsByIdentity = previous
                return false
            }
            return true
        }
        if changed {
            postDidChange()
        }
        return changed
    }

    @discardableResult
    func deleteCustomReading(
        character: String,
        pronunciation: String
    ) -> Bool {
        guard let validated = try? CustomReadingValidator.validate(
            character: character,
            pronunciation: pronunciation
        ) else {
            return false
        }

        let changed = withRecordsLock { () -> Bool in
            let identity = Self.identity(
                character: validated.character,
                pronunciation: validated.pronunciation
            )
            guard recordsByIdentity[identity] != nil else {
                return false
            }
            let previous = recordsByIdentity
            recordsByIdentity.removeValue(forKey: identity)
            guard persistLocked() else {
                recordsByIdentity = previous
                return false
            }
            return true
        }
        if changed {
            postDidChange()
        }
        return changed
    }

    private func loadFromDisk() {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let document = try? Self.decoder().decode(Document.self, from: data),
              document.format == Self.formatIdentifier,
              document.version == Self.currentVersion else {
            return
        }

        var loaded: [String: CustomReadingRecord] = [:]
        for record in document.records {
            guard let validated = try? CustomReadingValidator.validate(
                character: record.character,
                pronunciation: record.pronunciation
            ) else {
                continue
            }
            let normalized = CustomReadingRecord(
                character: validated.character,
                pronunciation: validated.pronunciation,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt
            )
            let identity = Self.identity(
                character: normalized.character,
                pronunciation: normalized.pronunciation
            )
            if let existing = loaded[identity] {
                loaded[identity] = existing.updatedAt >= normalized.updatedAt
                    ? existing
                    : normalized
            } else {
                loaded[identity] = normalized
            }
        }
        recordsByIdentity = loaded
    }

    private func persistLocked() -> Bool {
        guard let fileURL else {
            return false
        }
        let document = Document(
            format: Self.formatIdentifier,
            version: Self.currentVersion,
            records: recordsByIdentity.values.sorted(by: Self.recordSort)
        )
        do {
            let parent = fileURL.deletingLastPathComponent()
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(
                atPath: parent.path,
                isDirectory: &isDirectory
            ) {
                guard isDirectory.boolValue else {
                    return false
                }
            } else {
                try fileManager.createDirectory(
                    at: parent,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            }
            let data = try Self.encoder().encode(document)
            try data.write(to: fileURL, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
            return true
        } catch {
            return false
        }
    }

    private func postDidChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.didChangeNotification,
                object: self
            )
        }
    }

    private func withRecordsLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private static func identity(
        character: String,
        pronunciation: String
    ) -> String {
        pronunciation + "\u{1F}" + character
    }

    private static func recordSort(
        _ lhs: CustomReadingRecord,
        _ rhs: CustomReadingRecord
    ) -> Bool {
        if lhs.pronunciation != rhs.pronunciation {
            return lhs.pronunciation < rhs.pronunciation
        }
        if lhs.character != rhs.character {
            return lhs.character < rhs.character
        }
        return lhs.updatedAt > rhs.updatedAt
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
