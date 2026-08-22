import Foundation

/// One uncommitted piece of converted text and the reading that produced it.
///
/// A unit normally represents one Swift `Character`. Keeping the text as a
/// `String` also lets the input method preserve a raw Bopomofo syllable when
/// dictionary conversion is unavailable.
struct CompositionUnit: Identifiable, Equatable, Hashable {
    /// Punctuation occupies the buffer like any other text, but it carries no
    /// reading, so it can never take part in a user phrase or a phrase lookup.
    enum Kind: Equatable, Hashable {
        case reading
        case punctuation
    }

    let id: UUID
    let text: String
    let pronunciation: String
    let kind: Kind

    init(
        id: UUID = UUID(),
        text: String,
        pronunciation: String,
        kind: Kind = .reading
    ) {
        self.id = id
        self.text = text
        self.pronunciation = pronunciation
        self.kind = kind
    }
}

/// A candidate choice that may be learned once the complete marked text is
/// actually committed to the client application.
///
/// Unit identifiers make the event self-invalidating: replacing or deleting
/// any covered unit removes the event before the eventual commit snapshot.
struct PendingCandidateSelection: Equatable {
    let candidate: Candidate
    let reason: CandidateCommitReason
    let coveredUnitIDs: [UUID]
}

/// An exact user-phrase lookup to perform while the final reading is active.
///
/// `existingSuffixUnitIDs` covers all readings except the final active one.
/// Queries are emitted longest-first by `CompositionBuffer`.
struct CompositionPhraseQuery: Equatable {
    let pronunciationSequence: [String]
    let existingSuffixUnitIDs: [UUID]

    var unitCount: Int {
        pronunciationSequence.count
    }
}

/// The currently selected suffix of the marked composition, suitable for
/// adding to the user dictionary.
struct CompositionPhraseSelection: Equatable {
    let units: [CompositionUnit]

    var text: String {
        units.map(\.text).joined()
    }

    var pronunciationSequence: [String] {
        units.map(\.pronunciation)
    }
}

/// A stable, user-visible description of the reading unit currently targeted
/// by plain Left/Right revision.
struct CompositionRevisionFocus: Equatable {
    let unitID: UUID
    let text: String
    let pronunciation: String
    /// One-based position among reading units; punctuation is not counted.
    let readingPosition: Int
    let readingCount: Int

    var locatingDisplayText: String {
        "定位 \(readingPosition)／\(readingCount)：\(text)　\(pronunciation)　↓ 進入選字"
    }

    var choosingDisplayText: String {
        "選字 \(readingPosition)／\(readingCount)：\(text)　←／→ 選候選　Esc 返回"
    }
}

/// A detached, immutable value passed to the real client-commit path.
struct CompositionCommitSnapshot: Equatable {
    let units: [CompositionUnit]
    let pendingCandidateSelections: [PendingCandidateSelection]

    var text: String {
        units.map(\.text).joined()
    }

    var pronunciationSequence: [String] {
        units.map(\.pronunciation)
    }
}

/// Owns all converted text that has not yet been inserted into the client.
///
/// Selection is intentionally a suffix anchored at the end of the buffer.
/// This mirrors the familiar Shift-Left / Shift-Right phrase-selection model
/// without reading or modifying text that is already outside the input method.
struct CompositionBuffer: Equatable {
    static let minimumPhraseUnitCount = 2
    static let maximumPhraseUnitCount = 64

    private(set) var units: [CompositionUnit] = []
    private(set) var pendingCandidateSelections: [PendingCandidateSelection] = []
    private(set) var selectedSuffixUnitCount = 0

    var isEmpty: Bool {
        units.isEmpty
    }

    var hasSelection: Bool {
        selectedSuffixUnitCount > 0
    }

    var text: String {
        units.map(\.text).joined()
    }

    var pronunciationSequence: [String] {
        units.map(\.pronunciation)
    }

    var selectedUnitRange: Range<Int>? {
        guard hasSelection else {
            return nil
        }

        return (units.count - selectedSuffixUnitCount) ..< units.count
    }

    var lastReadingUnitID: UUID? {
        units.last(where: { $0.kind == .reading })?.id
    }

    /// The AppKit marked-text selection, expressed in UTF-16 code units.
    /// When no phrase range is selected, this is a caret at the text end.
    var markedSelectionRange: NSRange {
        markedSelectionRange(focusedUnitID: nil)
    }

    /// The AppKit range for phrase selection, a focused revision unit, or the
    /// caret at the end. A phrase selection remains the highest-priority view.
    func markedSelectionRange(focusedUnitID: UUID?) -> NSRange {
        guard let selectedUnitRange else {
            if let focusedUnitID,
               let focusedIndex = units.firstIndex(where: {
                   $0.id == focusedUnitID
               }) {
                let prefix = units[..<focusedIndex].map(\.text).joined()
                return NSRange(
                    location: prefix.utf16.count,
                    length: units[focusedIndex].text.utf16.count
                )
            }
            return NSRange(location: text.utf16.count, length: 0)
        }

        let prefix = units[..<selectedUnitRange.lowerBound]
            .map(\.text)
            .joined()
        let selection = units[selectedUnitRange]
            .map(\.text)
            .joined()
        return NSRange(
            location: prefix.utf16.count,
            length: selection.utf16.count
        )
    }

    func unit(withID unitID: UUID) -> CompositionUnit? {
        units.first(where: { $0.id == unitID })
    }

    func revisionFocus(for unitID: UUID) -> CompositionRevisionFocus? {
        let readingUnits = units.filter { $0.kind == .reading }
        guard let index = readingUnits.firstIndex(where: {
            $0.id == unitID
        }) else {
            return nil
        }

        let unit = readingUnits[index]
        return CompositionRevisionFocus(
            unitID: unit.id,
            text: unit.text,
            pronunciation: unit.pronunciation,
            readingPosition: index + 1,
            readingCount: readingUnits.count
        )
    }

    /// Finds the previous reading unit. Passing `nil` starts at the text end.
    func readingUnitID(before unitID: UUID?) -> UUID? {
        let endIndex: Int
        if let unitID,
           let index = units.firstIndex(where: { $0.id == unitID }) {
            endIndex = index
        } else {
            endIndex = units.endIndex
        }

        return units[..<endIndex].reversed()
            .first(where: { $0.kind == .reading })?.id
    }

    func readingUnitID(after unitID: UUID) -> UUID? {
        guard let index = units.firstIndex(where: { $0.id == unitID }),
              index < units.index(before: units.endIndex) else {
            return nil
        }

        return units[units.index(after: index)...]
            .first(where: { $0.kind == .reading })?.id
    }

    /// Returns a phrase only when at least two composition units are selected
    /// and every one of them carries a reading.
    var selectedPhrase: CompositionPhraseSelection? {
        guard let selectedUnitRange,
              selectedUnitRange.count >= Self.minimumPhraseUnitCount,
              units[selectedUnitRange].allSatisfy({ $0.kind == .reading }) else {
            return nil
        }

        return CompositionPhraseSelection(
            units: Array(units[selectedUnitRange])
        )
    }

    /// Adds unlearned text, such as a raw Bopomofo fallback, to the buffer.
    @discardableResult
    mutating func append(
        text: String,
        pronunciation: String,
        kind: CompositionUnit.Kind = .reading
    ) -> CompositionUnit? {
        let unit = CompositionUnit(
            text: text,
            pronunciation: pronunciation,
            kind: kind
        )
        return append(unit) ? unit : nil
    }

    /// Adds punctuation, which occupies the buffer without a reading.
    @discardableResult
    mutating func appendPunctuation(_ text: String) -> CompositionUnit? {
        append(text: text, pronunciation: text, kind: .punctuation)
    }

    /// Adds a pre-built unit. This overload is useful when another pure model
    /// needs to retain a stable identifier across a state transition.
    @discardableResult
    mutating func append(_ unit: CompositionUnit) -> Bool {
        guard isValid(unit),
              !units.contains(where: { $0.id == unit.id }) else {
            return false
        }

        units.append(unit)
        clearSelection()
        return true
    }

    /// Accepts a candidate into marked composition without learning it yet.
    /// Character candidates append one unit; phrase candidates replace their
    /// exact reading suffix and the currently active final reading.
    @discardableResult
    mutating func acceptCandidate(
        _ candidate: Candidate,
        reason: CandidateCommitReason
    ) -> Bool {
        switch candidate.type {
        case .character:
            return appendCharacterCandidate(candidate, reason: reason)
        case .phrase:
            return replaceSuffix(with: candidate, reason: reason)
        }
    }

    /// Replaces one existing reading unit during left/right revision.
    ///
    /// The stable unit ID keeps the revision focus attached. Any older pending
    /// selection that covered the unit is invalidated before the new event is
    /// recorded, including a multi-unit phrase event.
    @discardableResult
    mutating func replaceUnit(
        withID unitID: UUID,
        candidate: Candidate,
        reason: CandidateCommitReason
    ) -> Bool {
        guard let index = units.firstIndex(where: { $0.id == unitID }),
              units[index].kind == .reading,
              candidate.type == .character,
              candidate.text.count == 1,
              candidate.pronunciationSequence == [units[index].pronunciation]
        else {
            return false
        }

        // Opening a revision panel focuses the current character. Accepting
        // that unchanged snapshot is a no-op and must not erase a pending
        // phrase selection that still accurately describes the buffer.
        guard candidate.text != units[index].text else {
            clearSelection()
            return true
        }

        pendingCandidateSelections.removeAll {
            $0.coveredUnitIDs.contains(unitID)
        }
        units[index] = CompositionUnit(
            id: unitID,
            text: candidate.text,
            pronunciation: units[index].pronunciation
        )
        pendingCandidateSelections.append(
            PendingCandidateSelection(
                candidate: candidate,
                reason: reason,
                coveredUnitIDs: [unitID]
            )
        )
        clearSelection()
        return true
    }

    @discardableResult
    mutating func deleteUnit(withID unitID: UUID) -> CompositionUnit? {
        guard let index = units.firstIndex(where: { $0.id == unitID }) else {
            return nil
        }

        let deletedUnit = units.remove(at: index)
        selectedSuffixUnitCount = 0
        pruneInvalidPendingSelections()
        return deletedUnit
    }

    /// Produces every exact suffix lookup ending in `pronunciation`, ordered
    /// from the longest useful phrase to the shortest (which is two units).
    func phraseLookupQueries(
        appending pronunciation: String,
        minimumUnitCount: Int = Self.minimumPhraseUnitCount,
        maximumUnitCount: Int = Self.maximumPhraseUnitCount
    ) -> [CompositionPhraseQuery] {
        guard !pronunciation.isEmpty,
              minimumUnitCount >= Self.minimumPhraseUnitCount,
              maximumUnitCount >= minimumUnitCount else {
            return []
        }

        // A phrase never spans punctuation, so only the trailing run of units
        // that carry readings can extend the query.
        let longestCount = min(maximumUnitCount, trailingReadingUnitCount + 1)
        guard longestCount >= minimumUnitCount else {
            return []
        }

        return stride(
            from: longestCount,
            through: minimumUnitCount,
            by: -1
        ).map { unitCount in
            let existingUnitCount = unitCount - 1
            let suffix = units.suffix(existingUnitCount)
            return CompositionPhraseQuery(
                pronunciationSequence: suffix.map(\.pronunciation)
                    + [pronunciation],
                existingSuffixUnitIDs: suffix.map(\.id)
            )
        }
    }

    func containsExactSuffix(
        pronunciationSequence: [String]
    ) -> Bool {
        guard !pronunciationSequence.isEmpty,
              pronunciationSequence.count <= trailingReadingUnitCount else {
            return false
        }

        return units.suffix(pronunciationSequence.count)
            .map(\.pronunciation) == pronunciationSequence
    }

    /// How many units at the end of the buffer carry a reading.
    private var trailingReadingUnitCount: Int {
        units.reversed().prefix { $0.kind == .reading }.count
    }

    /// Extends the selected suffix by one unit toward the beginning.
    @discardableResult
    mutating func expandSelectionBackward() -> Bool {
        guard selectedSuffixUnitCount < units.count else {
            return false
        }

        selectedSuffixUnitCount += 1
        return true
    }

    /// Shrinks the selected suffix by one unit toward the end.
    @discardableResult
    mutating func shrinkSelectionForward() -> Bool {
        guard selectedSuffixUnitCount > 0 else {
            return false
        }

        selectedSuffixUnitCount -= 1
        return true
    }

    @discardableResult
    mutating func clearSelection() -> Bool {
        guard selectedSuffixUnitCount > 0 else {
            return false
        }

        selectedSuffixUnitCount = 0
        return true
    }

    /// Deletes the selected suffix, or one trailing unit when there is no
    /// selection. Returned units preserve their original display order.
    @discardableResult
    mutating func deleteBackward() -> [CompositionUnit] {
        guard !units.isEmpty else {
            return []
        }

        let deletionCount = hasSelection ? selectedSuffixUnitCount : 1
        let deletionStart = units.count - deletionCount
        let deletedUnits = Array(units[deletionStart...])
        units.removeSubrange(deletionStart...)
        selectedSuffixUnitCount = 0
        pruneInvalidPendingSelections()
        return deletedUnits
    }

    /// Detaches all commit data and resets first, so a client callback cannot
    /// cause the same pending learning event to be consumed twice.
    @discardableResult
    mutating func takeCommitSnapshot() -> CompositionCommitSnapshot? {
        guard !units.isEmpty else {
            return nil
        }

        let snapshot = CompositionCommitSnapshot(
            units: units,
            pendingCandidateSelections: pendingCandidateSelections
        )
        discard()
        return snapshot
    }

    /// Drops all marked text and uncommitted learning without producing work.
    mutating func discard() {
        units.removeAll(keepingCapacity: false)
        pendingCandidateSelections.removeAll(keepingCapacity: false)
        selectedSuffixUnitCount = 0
    }

    @discardableResult
    private mutating func appendCharacterCandidate(
        _ candidate: Candidate,
        reason: CandidateCommitReason
    ) -> Bool {
        guard candidate.type == .character,
              !candidate.text.isEmpty,
              candidate.pronunciationSequence.count == 1,
              let pronunciation = candidate.pronunciationSequence.first,
              !pronunciation.isEmpty else {
            return false
        }

        let unit = CompositionUnit(
            text: candidate.text,
            pronunciation: pronunciation
        )
        units.append(unit)
        pendingCandidateSelections.append(
            PendingCandidateSelection(
                candidate: candidate,
                reason: reason,
                coveredUnitIDs: [unit.id]
            )
        )
        clearSelection()
        return true
    }

    @discardableResult
    private mutating func replaceSuffix(
        with candidate: Candidate,
        reason: CandidateCommitReason
    ) -> Bool {
        let readings = candidate.pronunciationSequence
        let characters = Array(candidate.text)
        guard candidate.type == .phrase,
              (Self.minimumPhraseUnitCount ... Self.maximumPhraseUnitCount)
                .contains(readings.count),
              characters.count == readings.count,
              readings.allSatisfy({ !$0.isEmpty }) else {
            return false
        }

        let existingReadings = Array(readings.dropLast())
        guard containsExactSuffix(
            pronunciationSequence: existingReadings
        ) else {
            return false
        }

        units.removeLast(existingReadings.count)
        pruneInvalidPendingSelections()

        let replacementUnits = zip(characters, readings).map {
            CompositionUnit(text: String($0), pronunciation: $1)
        }
        units.append(contentsOf: replacementUnits)
        pendingCandidateSelections.append(
            PendingCandidateSelection(
                candidate: candidate,
                reason: reason,
                coveredUnitIDs: replacementUnits.map(\.id)
            )
        )
        clearSelection()
        return true
    }

    private func isValid(_ unit: CompositionUnit) -> Bool {
        !unit.text.isEmpty && !unit.pronunciation.isEmpty
    }

    private mutating func pruneInvalidPendingSelections() {
        let survivingUnitIDs = Set(units.map(\.id))
        pendingCandidateSelections.removeAll { selection in
            selection.coveredUnitIDs.isEmpty
                || !selection.coveredUnitIDs.allSatisfy(
                    survivingUnitIDs.contains
                )
        }
    }
}
