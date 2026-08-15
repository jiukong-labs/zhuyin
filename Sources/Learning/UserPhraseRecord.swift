import Foundation

/// One exact, user-created phrase and the ordered readings that identify it.
struct UserPhraseRecord: Equatable, Hashable {
    let phraseID: Int64
    let phrase: String
    let pronunciationSequence: [String]
    let createdAt: Date
    let lastUsedAt: Date?
    let selectionCount: Int64
    let pinned: Bool
}

enum UserPhraseValidationError: LocalizedError, Equatable {
    case invalidUnitCount(Int)
    case emptyPhrase
    case textReadingCountMismatch(textCount: Int, readingCount: Int)
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
}

enum UserPhraseValidator {
    static let allowedUnitCount = 2 ... 64

    static func validate(
        phrase: String,
        pronunciationSequence: [String]
    ) throws -> ValidatedUserPhrase {
        let normalizedPhrase = phrase.precomposedStringWithCanonicalMapping
        let normalizedReadings = pronunciationSequence.map {
            $0.precomposedStringWithCanonicalMapping
        }

        guard allowedUnitCount.contains(normalizedReadings.count) else {
            throw UserPhraseValidationError.invalidUnitCount(
                normalizedReadings.count
            )
        }
        guard !normalizedPhrase.isEmpty else {
            throw UserPhraseValidationError.emptyPhrase
        }
        let textUnitCount = normalizedPhrase.count
        guard textUnitCount == normalizedReadings.count else {
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
            pronunciationKey: try UserPhrasePronunciationKey.encode(
                normalizedReadings
            )
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
        guard UserPhraseValidator.allowedUnitCount.contains(
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

/// Mirrors `BopomofoSyllable.text` without coupling persistence to parser state.
private enum CanonicalBopomofoReading {
    private static let initials = Set("ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙ")
    private static let medials = Set("ㄧㄨㄩ")
    private static let finals = Set("ㄚㄛㄜㄝㄞㄟㄠㄡㄢㄣㄤㄥㄦ")
    private static let suffixTones = Set("ˊˇˋ")
    private static let neutralTone: Character = "˙"

    static func isValid(_ reading: String) -> Bool {
        var components = Array(reading)
        guard !components.isEmpty else {
            return false
        }

        if components.first == neutralTone {
            components.removeFirst()
        } else if let last = components.last, suffixTones.contains(last) {
            components.removeLast()
        }
        guard !components.isEmpty else {
            return false
        }

        var previousSlot = -1
        for component in components {
            let slot: Int
            if initials.contains(component) {
                slot = 0
            } else if medials.contains(component) {
                slot = 1
            } else if finals.contains(component) {
                slot = 2
            } else {
                return false
            }
            guard slot > previousSlot else {
                return false
            }
            previousSlot = slot
        }
        return true
    }
}
