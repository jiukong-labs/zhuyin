import Foundation

/// One phrase in a shared word list: the text, its ordered readings, and how
/// the two line up. Deliberately nothing else — a pack handed to another
/// person carries no selection counts, timestamps, or pins, so sharing a word
/// list never discloses how often someone types.
struct SharedPhrase: Equatable, Codable {
    let phrase: String
    let readings: [String]
    let unitPattern: String?

    init(phrase: String, readings: [String], unitPattern: String? = nil) {
        self.phrase = phrase
        self.readings = readings
        self.unitPattern = unitPattern
    }
}

enum PhraseSharePackError: LocalizedError, Equatable {
    case malformedDocument
    case personalBackupDocument
    case unknownFormat(String)
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .malformedDocument:
            return "The file is not a readable Jiukong Zhuyin phrase pack."
        case .personalBackupDocument:
            return "The file is a personal user-data backup, not a shared phrase pack."
        case let .unknownFormat(format):
            return "Unexpected phrase pack format \"\(format)\"."
        case let .unsupportedVersion(version):
            return "Unsupported phrase pack version \(version); this build reads version \(PhraseSharePack.currentVersion)."
        }
    }
}

/// Entries dropped while reading a pack, so the recipient can be told that a
/// file was imported only in part instead of silently losing words.
struct PhraseSharePackIssues: Equatable {
    var skippedPhrases = 0
    var skippedRemovals = 0

    var isEmpty: Bool {
        skippedPhrases == 0 && skippedRemovals == 0
    }
}

/// A word list one person can hand to another.
///
/// This is not the personal backup document. A backup restores one Mac's own
/// learning, including its selection statistics; a pack describes only *which
/// words* someone keeps: the phrases they authored, and the built-in phrases
/// they removed.
///
/// The bulk of the built-in dictionary is deliberately not copied into a pack.
/// Both Macs ship the identical dictionary, so importing a pack reproduces the
/// sender's word list exactly without redistributing the bundled lexicon.
struct PhraseSharePack: Equatable, Codable {
    static let formatIdentifier = "jiukong-zhuyin-phrase-pack"
    static let currentVersion = 1

    let format: String
    let version: Int
    let exportedAt: Int64
    let phrases: [SharedPhrase]
    let removedBuiltInPhrases: [SharedPhrase]

    init(
        format: String = PhraseSharePack.formatIdentifier,
        version: Int = PhraseSharePack.currentVersion,
        exportedAt: Int64,
        phrases: [SharedPhrase],
        removedBuiltInPhrases: [SharedPhrase]
    ) {
        self.format = format
        self.version = version
        self.exportedAt = exportedAt
        self.phrases = phrases
        self.removedBuiltInPhrases = removedBuiltInPhrases
    }

    var isEmpty: Bool {
        phrases.isEmpty && removedBuiltInPhrases.isEmpty
    }

    static func make(
        phrases: [UserPhraseRecord],
        removedBuiltInPhrases: [SuppressedPhraseRecord],
        exportedAt: Date
    ) -> PhraseSharePack {
        PhraseSharePack(
            exportedAt: milliseconds(from: exportedAt),
            phrases: phrases.map { record in
                SharedPhrase(
                    phrase: record.phrase,
                    readings: record.pronunciationSequence,
                    unitPattern: record.outputPattern.rawValue
                )
            },
            removedBuiltInPhrases: removedBuiltInPhrases.map { record in
                SharedPhrase(
                    phrase: record.phrase,
                    readings: record.pronunciationSequence,
                    unitPattern: record.outputPattern.rawValue
                )
            }
        )
    }

    /// Pretty printed with sorted keys so a pack is stable and diffable.
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Decoding is total in the same way the backup document is: a structurally
    /// valid pack with some unusable rows is accepted without them, and the
    /// caller is told how many were dropped.
    static func decoded(
        from data: Data
    ) throws -> (pack: PhraseSharePack, issues: PhraseSharePackIssues) {
        let decoded: PhraseSharePack
        do {
            decoded = try JSONDecoder().decode(PhraseSharePack.self, from: data)
        } catch {
            // Both documents are JSON, so name the likely mistake instead of
            // reporting an unreadable file.
            if let format = try? formatIdentifier(of: data),
               format == UserDataArchive.formatIdentifier {
                throw PhraseSharePackError.personalBackupDocument
            }
            throw PhraseSharePackError.malformedDocument
        }

        guard decoded.format == formatIdentifier else {
            if decoded.format == UserDataArchive.formatIdentifier {
                throw PhraseSharePackError.personalBackupDocument
            }
            throw PhraseSharePackError.unknownFormat(decoded.format)
        }
        guard decoded.version >= 1, decoded.version <= currentVersion else {
            throw PhraseSharePackError.unsupportedVersion(decoded.version)
        }

        var issues = PhraseSharePackIssues()
        let phrases = normalized(
            decoded.phrases,
            skipped: &issues.skippedPhrases
        )
        let removals = normalized(
            decoded.removedBuiltInPhrases,
            skipped: &issues.skippedRemovals
        )

        return (
            PhraseSharePack(
                format: decoded.format,
                version: decoded.version,
                exportedAt: decoded.exportedAt,
                phrases: phrases,
                removedBuiltInPhrases: removals
            ),
            issues
        )
    }

    /// Reuses the merge the backup import already performs, so an imported
    /// pack is idempotent and cannot lower a count or unpin anything the
    /// recipient chose: shared phrases arrive with a zero count and no pin.
    func archive(
        importedAt: Date,
        includesRemovals: Bool
    ) -> UserDataArchive {
        let timestamp = Self.milliseconds(from: importedAt)
        return UserDataArchive(
            exportedAt: timestamp,
            characters: [],
            phrases: phrases.map { entry in
                ArchivedPhrase(
                    phrase: entry.phrase,
                    readings: entry.readings,
                    unitPattern: entry.unitPattern,
                    selectionCount: 0,
                    createdAt: timestamp,
                    lastUsedAt: nil,
                    pinned: false
                )
            },
            suppressions: includesRemovals
                ? removedBuiltInPhrases.map { entry in
                    ArchivedSuppressedPhrase(
                        phrase: entry.phrase,
                        readings: entry.readings,
                        suppressedAt: timestamp
                    )
                }
                : []
        )
    }

    private static func normalized(
        _ entries: [SharedPhrase],
        skipped: inout Int
    ) -> [SharedPhrase] {
        var result: [SharedPhrase] = []
        var seen: Set<String> = []
        for entry in entries {
            guard let normalized = entry.normalized(),
                  let key = try? UserPhrasePronunciationKey.encode(
                      normalized.readings
                  ),
                  seen.insert(key + "\u{1}" + normalized.phrase).inserted else {
                skipped += 1
                continue
            }
            result.append(normalized)
        }
        return result
    }

    private static func formatIdentifier(of data: Data) throws -> String? {
        let object = try JSONSerialization.jsonObject(with: data)
        return (object as? [String: Any])?["format"] as? String
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

private extension SharedPhrase {
    /// A shared phrase names an exact phrase identity, so it is validated the
    /// same way a locally stored one is. A pack from a stranger is untrusted
    /// input: nothing reaches the database without passing this.
    func normalized() -> SharedPhrase? {
        let outputPattern: PhraseOutputPattern?
        if let unitPattern {
            outputPattern = PhraseOutputPattern(rawValue: unitPattern)
        } else {
            outputPattern = PhraseOutputPattern.inferred(
                from: phrase,
                readingCount: readings.count
            )
        }
        guard let outputPattern,
              let identity = try? UserPhraseValidator.validate(
                  phrase: phrase,
                  pronunciationSequence: readings,
                  outputPattern: outputPattern
              ) else {
            return nil
        }

        return SharedPhrase(
            phrase: identity.phrase,
            readings: identity.pronunciationSequence,
            unitPattern: identity.outputPattern.rawValue
        )
    }
}
