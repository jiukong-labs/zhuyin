import Foundation

/// One built-in phrase the user removed from the candidate window.
///
/// Suppressions live in the user's own database, never in the bundled
/// dictionary, so a dictionary rebuild shipped with an app update cannot
/// bring a removed phrase back. The record keeps the exact identity that was
/// removed — text plus its ordered readings — so a different reading of the
/// same characters stays available.
struct SuppressedPhraseRecord: Equatable, Hashable {
    let phrase: String
    let pronunciationSequence: [String]
    let outputPattern: PhraseOutputPattern
    let suppressedAt: Date

    init(
        phrase: String,
        pronunciationSequence: [String],
        outputPattern: PhraseOutputPattern? = nil,
        suppressedAt: Date
    ) {
        self.phrase = phrase
        self.pronunciationSequence = pronunciationSequence
        self.outputPattern = outputPattern
            ?? PhraseOutputPattern.inferred(
                from: phrase,
                readingCount: pronunciationSequence.count
            )!
        self.suppressedAt = suppressedAt
    }
}
