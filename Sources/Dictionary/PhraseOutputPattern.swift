import Foundation

/// One compact, persisted description of how phrase text maps to readings.
/// `R` consumes one canonical Bopomofo reading; `P` emits one reading-free
/// punctuation character. Existing phrases are represented by all `R`s.
struct PhraseOutputPattern: Equatable, Hashable, Codable {
    static let readingMarker: Character = "R"
    static let punctuationMarker: Character = "P"
    static let maximumUnitCount = 64

    /// Keep this repertoire aligned with `PunctuationLayout.standard`.
    static let supportedPunctuation: Set<Character> = [
        "「", "」", "、", "，", "。", "？", "：", "！", "…", "（", "）",
        "—", "『", "』", "／",
    ]

    let rawValue: String

    init?(rawValue: String) {
        let markers = Array(rawValue)
        guard !markers.isEmpty,
              markers.count <= Self.maximumUnitCount,
              markers.allSatisfy({
                  $0 == Self.readingMarker || $0 == Self.punctuationMarker
              }) else {
            return nil
        }
        self.rawValue = rawValue
    }

    static func allReadings(count: Int) -> PhraseOutputPattern? {
        guard count > 0, count <= maximumUnitCount else {
            return nil
        }
        return PhraseOutputPattern(
            rawValue: String(repeating: readingMarker, count: count)
        )
    }

    static func inferred(
        from text: String,
        readingCount: Int
    ) -> PhraseOutputPattern? {
        let rawValue = String(text.map { character in
            supportedPunctuation.contains(character)
                ? punctuationMarker
                : readingMarker
        })
        guard let pattern = PhraseOutputPattern(rawValue: rawValue),
              pattern.readingCount == readingCount else {
            return nil
        }
        return pattern
    }

    var markers: [Character] {
        Array(rawValue)
    }

    var unitCount: Int {
        rawValue.count
    }

    var readingCount: Int {
        markers.filter { $0 == Self.readingMarker }.count
    }

    var containsPunctuation: Bool {
        markers.contains(Self.punctuationMarker)
    }

    func validates(text: String, readingCount: Int) -> Bool {
        let characters = Array(text)
        let markers = markers
        guard characters.count == markers.count,
              self.readingCount == readingCount else {
            return false
        }
        return zip(characters, markers).allSatisfy { character, marker in
            marker == Self.readingMarker
                || Self.supportedPunctuation.contains(character)
        }
    }
}
