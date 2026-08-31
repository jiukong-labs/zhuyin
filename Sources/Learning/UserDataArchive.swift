import Foundation

/// One exported character-selection row. Timestamps are UTC Unix milliseconds,
/// matching the database, so an export never depends on a locale or time zone.
struct ArchivedCharacter: Equatable, Codable {
    let character: String
    let pronunciation: String
    let selectionCount: Int64
    let lastSelectedAt: Int64?
    let pinned: Bool
}

/// One exported user phrase with its ordered readings.
struct ArchivedPhrase: Equatable, Codable {
    let phrase: String
    let readings: [String]
    let unitPattern: String?
    let selectionCount: Int64
    let createdAt: Int64
    let lastUsedAt: Int64?
    let pinned: Bool

    init(
        phrase: String,
        readings: [String],
        unitPattern: String? = nil,
        selectionCount: Int64,
        createdAt: Int64,
        lastUsedAt: Int64?,
        pinned: Bool
    ) {
        self.phrase = phrase
        self.readings = readings
        self.unitPattern = unitPattern
        self.selectionCount = selectionCount
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.pinned = pinned
    }
}

enum UserDataArchiveError: LocalizedError, Equatable {
    case malformedDocument
    case unknownFormat(String)
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .malformedDocument:
            return "The file is not a readable Jiukong Zhuyin user data document."
        case let .unknownFormat(format):
            return "Unexpected user data format \"\(format)\"."
        case let .unsupportedVersion(version):
            return "Unsupported user data version \(version); this build reads version \(UserDataArchive.currentVersion)."
        }
    }
}

/// Entries dropped while reading a document, so the user can be told that a
/// file was imported only in part instead of silently losing rows.
struct UserDataArchiveIssues: Equatable {
    var skippedCharacters = 0
    var skippedPhrases = 0

    var isEmpty: Bool {
        skippedCharacters == 0 && skippedPhrases == 0
    }
}

/// How many entries an import actually applied.
struct UserDataMergeSummary: Equatable {
    var mergedCharacters = 0
    var mergedPhrases = 0
}

/// The portable, versioned representation of everything this Mac has learned.
///
/// Decoding is total: a structurally valid document with some unusable rows is
/// accepted without them, and the caller is told how many were dropped. Only an
/// unreadable file, a foreign format, or a newer version is refused outright.
struct UserDataArchive: Equatable, Codable {
    static let formatIdentifier = "jiukong-zhuyin-user-data"
    static let currentVersion = 2

    let format: String
    let version: Int
    let exportedAt: Int64
    let characters: [ArchivedCharacter]
    let phrases: [ArchivedPhrase]

    init(
        format: String = UserDataArchive.formatIdentifier,
        version: Int = UserDataArchive.currentVersion,
        exportedAt: Int64,
        characters: [ArchivedCharacter],
        phrases: [ArchivedPhrase]
    ) {
        self.format = format
        self.version = version
        self.exportedAt = exportedAt
        self.characters = characters
        self.phrases = phrases
    }

    var isEmpty: Bool {
        characters.isEmpty && phrases.isEmpty
    }

    static func make(
        characters: [CharacterLearningRecord],
        phrases: [UserPhraseRecord],
        exportedAt: Date
    ) -> UserDataArchive {
        UserDataArchive(
            exportedAt: milliseconds(from: exportedAt),
            characters: characters.map { record in
                ArchivedCharacter(
                    character: record.character,
                    pronunciation: record.pronunciation,
                    selectionCount: record.selectionCount,
                    lastSelectedAt: record.lastSelectedAt.map(milliseconds(from:)),
                    pinned: record.pinned
                )
            },
            phrases: phrases.map { record in
                ArchivedPhrase(
                    phrase: record.phrase,
                    readings: record.pronunciationSequence,
                    unitPattern: record.outputPattern.rawValue,
                    selectionCount: record.selectionCount,
                    createdAt: milliseconds(from: record.createdAt),
                    lastUsedAt: record.lastUsedAt.map(milliseconds(from:)),
                    pinned: record.pinned
                )
            }
        )
    }

    /// Pretty printed with sorted keys so an export is stable and diffable.
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    static func decoded(
        from data: Data
    ) throws -> (archive: UserDataArchive, issues: UserDataArchiveIssues) {
        let decoded: UserDataArchive
        do {
            decoded = try JSONDecoder().decode(UserDataArchive.self, from: data)
        } catch {
            throw UserDataArchiveError.malformedDocument
        }

        guard decoded.format == formatIdentifier else {
            throw UserDataArchiveError.unknownFormat(decoded.format)
        }
        guard decoded.version >= 1, decoded.version <= currentVersion else {
            throw UserDataArchiveError.unsupportedVersion(decoded.version)
        }

        var issues = UserDataArchiveIssues()
        var characters: [ArchivedCharacter] = []
        var seenCharacters: Set<String> = []
        for entry in decoded.characters {
            guard let normalized = entry.normalized(),
                  seenCharacters.insert(
                      normalized.pronunciation + "\u{1}" + normalized.character
                  ).inserted else {
                issues.skippedCharacters += 1
                continue
            }
            characters.append(normalized)
        }

        var phrases: [ArchivedPhrase] = []
        var seenPhrases: Set<String> = []
        for entry in decoded.phrases {
            guard let normalized = entry.normalized(),
                  let key = try? UserPhrasePronunciationKey.encode(
                      normalized.readings
                  ),
                  seenPhrases.insert(key + "\u{1}" + normalized.phrase)
                    .inserted else {
                issues.skippedPhrases += 1
                continue
            }
            phrases.append(normalized)
        }

        return (
            UserDataArchive(
                format: decoded.format,
                version: decoded.version,
                exportedAt: decoded.exportedAt,
                characters: characters,
                phrases: phrases
            ),
            issues
        )
    }

    private static func milliseconds(from date: Date) -> Int64 {
        let milliseconds = date.timeIntervalSince1970 * 1_000
        if milliseconds >= Double(Int64.max) {
            return Int64.max
        }
        if milliseconds <= Double(Int64.min) {
            return Int64.min
        }
        return Int64(milliseconds.rounded(.towardZero))
    }
}

private extension ArchivedCharacter {
    /// A learned character is exactly one Swift `Character` with a canonical
    /// reading; anything else could not have been produced by conversion.
    func normalized() -> ArchivedCharacter? {
        let character = self.character.precomposedStringWithCanonicalMapping
        let pronunciation = self.pronunciation
            .precomposedStringWithCanonicalMapping
        guard character.count == 1,
              CanonicalBopomofoReading.isValid(pronunciation),
              selectionCount >= 0 else {
            return nil
        }

        return ArchivedCharacter(
            character: character,
            pronunciation: pronunciation,
            selectionCount: selectionCount,
            lastSelectedAt: lastSelectedAt,
            pinned: pinned
        )
    }
}

private extension ArchivedPhrase {
    func normalized() -> ArchivedPhrase? {
        let outputPattern: PhraseOutputPattern?
        if let unitPattern {
            outputPattern = PhraseOutputPattern(rawValue: unitPattern)
        } else {
            outputPattern = PhraseOutputPattern.inferred(
                from: phrase,
                readingCount: readings.count
            )
        }
        guard selectionCount >= 0,
              let outputPattern,
              let identity = try? UserPhraseValidator.validate(
                  phrase: phrase,
                  pronunciationSequence: readings,
                  outputPattern: outputPattern
              ) else {
            return nil
        }

        return ArchivedPhrase(
            phrase: identity.phrase,
            readings: identity.pronunciationSequence,
            unitPattern: identity.outputPattern.rawValue,
            selectionCount: selectionCount,
            createdAt: createdAt,
            lastUsedAt: lastUsedAt,
            pinned: pinned
        )
    }
}
