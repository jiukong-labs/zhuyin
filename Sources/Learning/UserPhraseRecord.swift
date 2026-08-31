import Foundation

/// One exact, user-created phrase and the ordered readings that identify it.
struct UserPhraseRecord: Equatable, Hashable {
    let phraseID: Int64
    let phrase: String
    let pronunciationSequence: [String]
    let outputPattern: PhraseOutputPattern
    let createdAt: Date
    let lastUsedAt: Date?
    let selectionCount: Int64
    let pinned: Bool

    init(
        phraseID: Int64,
        phrase: String,
        pronunciationSequence: [String],
        outputPattern: PhraseOutputPattern? = nil,
        createdAt: Date,
        lastUsedAt: Date?,
        selectionCount: Int64,
        pinned: Bool
    ) {
        self.phraseID = phraseID
        self.phrase = phrase
        self.pronunciationSequence = pronunciationSequence
        self.outputPattern = outputPattern
            ?? PhraseOutputPattern.inferred(
                from: phrase,
                readingCount: pronunciationSequence.count
            )!
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.selectionCount = selectionCount
        self.pinned = pinned
    }
}

enum UserPhraseValidationError: LocalizedError, Equatable {
    case invalidUnitCount(Int)
    case emptyPhrase
    case textReadingCountMismatch(textCount: Int, readingCount: Int)
    case invalidOutputPattern
    case unsupportedPunctuation(index: Int)
    case emptyPronunciation(index: Int)
    case invalidPronunciation(index: Int)

    var errorDescription: String? {
        switch self {
        case let .invalidUnitCount(count):
            return "A user phrase must contain 2 through 64 readings; received \(count)."
        case .emptyPhrase:
            return "A user phrase cannot be empty."
        case let .textReadingCountMismatch(textCount, readingCount):
            return "A user phrase has \(textCount) text units but \(readingCount) readings."
        case .invalidOutputPattern:
            return "A user phrase has an invalid reading/punctuation pattern."
        case let .unsupportedPunctuation(index):
            return "User phrase punctuation \(index) is not supported."
        case let .emptyPronunciation(index):
            return "User phrase reading \(index) cannot be empty."
        case let .invalidPronunciation(index):
            return "User phrase reading \(index) is not canonical Bopomofo."
        }
    }
}

/// A normalized identity safe to persist or use for an exact lookup.
struct ValidatedUserPhrase: Equatable {
    let phrase: String
    let pronunciationSequence: [String]
    let pronunciationKey: String
    let outputPattern: PhraseOutputPattern
}

enum UserPhraseValidator {
    static let allowedUnitCount = 2 ... 64

    static func validate(
        phrase: String,
        pronunciationSequence: [String],
        outputPattern: PhraseOutputPattern? = nil
    ) throws -> ValidatedUserPhrase {
        let normalizedPhrase = phrase.precomposedStringWithCanonicalMapping
        let normalizedReadings = pronunciationSequence.map {
            $0.precomposedStringWithCanonicalMapping
        }

        guard !normalizedPhrase.isEmpty else {
            throw UserPhraseValidationError.emptyPhrase
        }
        guard (1 ... allowedUnitCount.upperBound).contains(
            normalizedReadings.count
        ) else {
            throw UserPhraseValidationError.invalidUnitCount(
                normalizedReadings.count
            )
        }

        let resolvedPattern: PhraseOutputPattern
        if let outputPattern {
            resolvedPattern = outputPattern
        } else if let inferred = PhraseOutputPattern(
            rawValue: String(normalizedPhrase.map { character in
                PhraseOutputPattern.supportedPunctuation.contains(character)
                    ? PhraseOutputPattern.punctuationMarker
                    : PhraseOutputPattern.readingMarker
            })
        ) {
            resolvedPattern = inferred
        } else {
            throw UserPhraseValidationError.invalidOutputPattern
        }

        let minimumReadingCount = resolvedPattern.containsPunctuation ? 1 : 2
        guard (minimumReadingCount ... allowedUnitCount.upperBound)
            .contains(normalizedReadings.count) else {
            throw UserPhraseValidationError.invalidUnitCount(
                normalizedReadings.count
            )
        }
        let textUnitCount = normalizedPhrase.count
        guard resolvedPattern.unitCount == textUnitCount,
              resolvedPattern.readingCount == normalizedReadings.count else {
            if outputPattern == nil {
                throw UserPhraseValidationError.textReadingCountMismatch(
                    textCount: textUnitCount,
                    readingCount: normalizedReadings.count
                )
            }
            throw UserPhraseValidationError.invalidOutputPattern
        }
        for (index, pair) in zip(
            Array(normalizedPhrase), resolvedPattern.markers
        ).enumerated() where pair.1 == PhraseOutputPattern.punctuationMarker {
            guard PhraseOutputPattern.supportedPunctuation.contains(pair.0) else {
                throw UserPhraseValidationError.unsupportedPunctuation(index: index)
            }
        }
        guard resolvedPattern.validates(
            text: normalizedPhrase,
            readingCount: normalizedReadings.count
        ) else {
            throw UserPhraseValidationError.textReadingCountMismatch(
                textCount: textUnitCount,
                readingCount: normalizedReadings.count
            )
        }
        if let emptyIndex = normalizedReadings.firstIndex(where: \.isEmpty) {
            throw UserPhraseValidationError.emptyPronunciation(index: emptyIndex)
        }
        if let invalidIndex = normalizedReadings.firstIndex(where: {
            !CanonicalBopomofoReading.isValid($0)
        }) {
            throw UserPhraseValidationError.invalidPronunciation(
                index: invalidIndex
            )
        }

        return ValidatedUserPhrase(
            phrase: normalizedPhrase,
            pronunciationSequence: normalizedReadings,
            pronunciationKey: try UserPhrasePronunciationKey.encode(normalizedReadings),
            outputPattern: resolvedPattern
        )
    }
}

/// Versioned, UTF-8 length-prefixed encoding used only for exact SQL lookup.
///
/// Length prefixes keep sequences such as `["ab", "c"]` and `["a", "bc"]`
/// distinct without depending on a separator that might occur in a reading.
enum UserPhrasePronunciationKey {
    static let currentVersion = 1
    private static let prefix = "v\(currentVersion)|"

    static func encode(_ pronunciationSequence: [String]) throws -> String {
        guard (1 ... UserPhraseValidator.allowedUnitCount.upperBound).contains(
            pronunciationSequence.count
        ) else {
            throw UserPhraseValidationError.invalidUnitCount(
                pronunciationSequence.count
            )
        }

        let normalizedReadings = pronunciationSequence.map {
            $0.precomposedStringWithCanonicalMapping
        }
        if let emptyIndex = normalizedReadings.firstIndex(where: \.isEmpty) {
            throw UserPhraseValidationError.emptyPronunciation(index: emptyIndex)
        }
        if let invalidIndex = normalizedReadings.firstIndex(where: {
            !CanonicalBopomofoReading.isValid($0)
        }) {
            throw UserPhraseValidationError.invalidPronunciation(
                index: invalidIndex
            )
        }

        return prefix + normalizedReadings.map { reading in
            "\(reading.utf8.count):\(reading)"
        }.joined()
    }
}
