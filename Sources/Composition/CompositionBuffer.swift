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

/// The currently selected reading span of the marked composition, suitable
/// for adding to the user dictionary.
struct CompositionPhraseSelection: Equatable {
    let units: [CompositionUnit]

    var text: String {
        units.map(\.text).joined()
    }

    var pronunciationSequence: [String] {
        units.map(\.pronunciation)
    }
}

/// A display-only snapshot of the current phrase range. Keeping this separate
/// from `selectedPhrase` lets the UI report a one-character starting range
/// before it is long enough to save.
struct CompositionPhraseSelectionStatus: Equatable {
    let text: String
    let unitCount: Int

    var displayText: String {
        let minimumHint = unitCount >= CompositionBuffer.minimumPhraseUnitCount
            ? ""
            : "　至少選 2 字"
        return "造詞範圍 \(unitCount) 字：【\(text)】　⇧←／→ 擴張\(minimumHint)"
    }
}

/// A stable, user-visible description of the reading unit currently offered
/// for candidate revision.
struct CompositionRevisionFocus: Equatable {
    let unitID: UUID
    let text: String
    let pronunciation: String
    /// One-based position among reading units; punctuation is not counted.
    let readingPosition: Int
    let readingCount: Int

    var locatingDisplayText: String {
        "定位 \(readingPosition)／\(readingCount)：\(text)　\(pronunciation)　⇧←／→ 造詞　⌫ 改左字音　Del 改右字音　↓ 選字"
    }

    var choosingDisplayText: String {
        "選字 \(readingPosition)／\(readingCount)：\(text)　←／→ 選候選　⌫ 改左字音　Del 改右字音　↑／Esc 返回"
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

/// The boundary used when the first Shift-arrow creates a phrase range.
///
/// A positioned caret stores the unit immediately following it; `nil` means
/// the caret is explicitly at the text end. Without positioning, buffer-edge
/// selection starts with one unit and lets later presses expand it.
enum CompositionPhraseSelectionAnchor: Equatable {
    case bufferEdge
    case caret(followingUnitID: UUID?)
}

/// Owns all converted text that has not yet been inserted into the client.
///
/// Phrase selection is always a contiguous range inside this input method's
/// own marked text. It never reads or modifies text that has already been
/// committed to the client application.
struct CompositionBuffer: Equatable {
    static let minimumPhraseUnitCount = 2
    static let maximumPhraseUnitCount = 64

    private(set) var units: [CompositionUnit] = []
    private(set) var pendingCandidateSelections: [PendingCandidateSelection] = []
    private(set) var selectedUnitRange: Range<Int>?

    var isEmpty: Bool {
        units.isEmpty
    }

    var hasSelection: Bool {
        selectedUnitRange != nil
    }

    var text: String {
        units.map(\.text).joined()
    }

    var pronunciationSequence: [String] {
        units.map(\.pronunciation)
    }

    var lastReadingUnitID: UUID? {
        units.last(where: { $0.kind == .reading })?.id
    }

    /// Moves the insertion-caret anchor one displayed unit to the left.
    ///
    /// The anchor is the unit immediately following the caret; `nil` is the
    /// text end. Punctuation is deliberately included because it occupies a
    /// visible caret boundary even though it has no candidate reading.
    func caretAnchorUnitID(movingLeftFrom followingUnitID: UUID?) -> UUID? {
        guard let followingUnitID else {
            return units.last?.id
        }
        guard let followingIndex = units.firstIndex(where: {
            $0.id == followingUnitID
        }), followingIndex > units.startIndex else {
            return nil
        }
        return units[units.index(before: followingIndex)].id
    }

    /// Moves the insertion-caret anchor one displayed unit to the right.
    /// Returning `nil` means the caret has reached the text end.
    func caretAnchorUnitID(movingRightFrom followingUnitID: UUID?) -> UUID? {
        guard let followingUnitID,
              let followingIndex = units.firstIndex(where: {
                  $0.id == followingUnitID
              }),
              followingIndex < units.index(before: units.endIndex) else {
            return nil
        }
        return units[units.index(after: followingIndex)].id
    }

    /// The AppKit marked-text selection, expressed in UTF-16 code units.
    /// When no phrase range is selected, this is a caret at the text end.
    var markedSelectionRange: NSRange {
        markedSelectionRange(focusedUnitID: nil)
    }

    /// The AppKit range for phrase selection, a revision caret immediately
    /// before the focused unit, or the caret at the end. A phrase selection
    /// remains the highest-priority view.
    func markedSelectionRange(focusedUnitID: UUID?) -> NSRange {
        guard let selectedUnitRange else {
            if let focusedUnitID,
               let focusedIndex = units.firstIndex(where: {
                   $0.id == focusedUnitID
               }) {
                let prefix = units[..<focusedIndex].map(\.text).joined()
                return NSRange(
                    location: prefix.utf16.count,
                    length: 0
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

    /// Returns the reading unit immediately before `unitID`. Unlike revision
    /// arrow navigation, this deliberately does not skip punctuation because
    /// Backspace must never reach across a punctuation boundary.
    func readingUnitID(immediatelyBefore unitID: UUID) -> UUID? {
        guard let index = units.firstIndex(where: { $0.id == unitID }),
              index > units.startIndex else {
            return nil
        }
        let previousUnit = units[units.index(before: index)]
        return previousUnit.kind == .reading ? previousUnit.id : nil
    }

    /// Returns the reading immediately before a revision caret. A `nil`
    /// following unit represents an active caret at the text end. This lookup
    /// is deliberately adjacency-based, so candidate revision never jumps
    /// backward across punctuation.
    func readingUnitID(immediatelyBeforeCaretAt followingUnitID: UUID?) -> UUID? {
        guard let followingUnitID else {
            return units.last?.kind == .reading ? units.last?.id : nil
        }
        return readingUnitID(immediatelyBefore: followingUnitID)
    }

    /// Candidate revision always targets the reading immediately before the
    /// insertion caret, while the caret itself keeps its independent anchor.
    func revisionFocus(immediatelyBeforeCaretAt followingUnitID: UUID?)
        -> CompositionRevisionFocus? {
        guard let unitID = readingUnitID(
            immediatelyBeforeCaretAt: followingUnitID
        ) else {
            return nil
        }
        return revisionFocus(for: unitID)
    }

    /// Resolves the reading revised by Down Arrow at a positioned caret.
    /// Ordinarily this is the reading immediately before the caret. At the
    /// absolute text start there is no left-hand reading, so the first reading
    /// on the right is the only useful target.
    func revisionFocusForCandidate(
        atCaretFollowing followingUnitID: UUID?
    ) -> CompositionRevisionFocus? {
        if let precedingFocus = revisionFocus(
            immediatelyBeforeCaretAt: followingUnitID
        ) {
            return precedingFocus
        }

        guard let followingUnitID,
              units.first?.id == followingUnitID,
              units.first?.kind == .reading else {
            return nil
        }
        return revisionFocus(for: followingUnitID)
    }

    /// Returns the unit immediately following `unitID`, including punctuation.
    /// A forward pronunciation edit removes the focused reading and uses this
    /// surviving unit as its insertion anchor so the raw reading stays at the
    /// original cursor position.
    func unitID(immediatelyAfter unitID: UUID) -> UUID? {
        guard let index = units.firstIndex(where: { $0.id == unitID }),
              index < units.index(before: units.endIndex) else {
            return nil
        }
        return units[units.index(after: index)].id
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

    var phraseSelectionStatus: CompositionPhraseSelectionStatus? {
        guard let selectedUnitRange else {
            return nil
        }
        return CompositionPhraseSelectionStatus(
            text: units[selectedUnitRange].map(\.text).joined(),
            unitCount: selectedUnitRange.count
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

    /// Adds unlearned text (such as a raw Bopomofo fallback) immediately
    /// before `anchorUnitID`, instead of at the end of the buffer. Used while
    /// the caret is positioned via revision-focus navigation.
    @discardableResult
    mutating func insert(
        text: String,
        pronunciation: String,
        before anchorUnitID: UUID,
        kind: CompositionUnit.Kind = .reading
    ) -> CompositionUnit? {
        guard let anchorIndex = units.firstIndex(where: { $0.id == anchorUnitID }) else {
            return nil
        }

        let unit = CompositionUnit(text: text, pronunciation: pronunciation, kind: kind)
        guard isValid(unit) else {
            return nil
        }

        units.insert(unit, at: anchorIndex)
        clearSelection()
        return unit
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

    /// Inserts a candidate immediately before `anchorUnitID` instead of at the
    /// end of the buffer, mirroring `acceptCandidate`. Used while the caret is
    /// positioned via revision-focus navigation and the user types a new
    /// reading rather than replacing the focused one. Returns the inserted
    /// units (empty on failure) so the caller can refocus onto them.
    @discardableResult
    mutating func insertCandidate(
        _ candidate: Candidate,
        before anchorUnitID: UUID,
        reason: CandidateCommitReason
    ) -> [CompositionUnit] {
        switch candidate.type {
        case .character:
            return insertCharacterCandidate(
                candidate,
                before: anchorUnitID,
                reason: reason
            )
        case .phrase:
            return insertPhraseSuffix(
                candidate,
                before: anchorUnitID,
                reason: reason
            )
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
        selectedUnitRange = nil
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

    /// Like `phraseLookupQueries(appending:)`, but scoped to the context that
    /// precedes `anchorUnitID` (not including it) instead of the trailing end
    /// of the whole buffer. Used while the caret is positioned via
    /// revision-focus navigation and the new reading is about to be inserted
    /// right before that unit, so a phrase can only combine with readings up
    /// to the insertion point rather than the anchor or anything after it.
    func phraseLookupQueries(
        appending pronunciation: String,
        before anchorUnitID: UUID,
        minimumUnitCount: Int = Self.minimumPhraseUnitCount,
        maximumUnitCount: Int = Self.maximumPhraseUnitCount
    ) -> [CompositionPhraseQuery] {
        guard !pronunciation.isEmpty,
              minimumUnitCount >= Self.minimumPhraseUnitCount,
              maximumUnitCount >= minimumUnitCount,
              let anchorIndex = units.firstIndex(where: { $0.id == anchorUnitID })
        else {
            return []
        }

        let context = units[..<anchorIndex]
        let trailingReadingCount = context.reversed()
            .prefix { $0.kind == .reading }.count
        let longestCount = min(maximumUnitCount, trailingReadingCount + 1)
        guard longestCount >= minimumUnitCount else {
            return []
        }

        return stride(
            from: longestCount,
            through: minimumUnitCount,
            by: -1
        ).map { unitCount in
            let existingUnitCount = unitCount - 1
            let suffix = context.suffix(existingUnitCount)
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

    /// Extends the selection's left edge. With no existing selection, this
    /// preserves the original end-anchored Shift-Left behavior.
    @discardableResult
    mutating func expandSelectionBackward() -> Bool {
        guard !units.isEmpty else {
            return false
        }

        if let selectedUnitRange {
            guard selectedUnitRange.lowerBound > units.startIndex else {
                return false
            }
            self.selectedUnitRange =
                (selectedUnitRange.lowerBound - 1) ..< selectedUnitRange.upperBound
        } else {
            selectedUnitRange = units.index(before: units.endIndex) ..< units.endIndex
        }
        return true
    }

    /// Shrinks the selection by moving its left edge toward the end.
    /// Retained for model-level compatibility; interactive Shift-Right now
    /// extends the right edge instead.
    @discardableResult
    mutating func shrinkSelectionForward() -> Bool {
        guard let selectedUnitRange else {
            return false
        }

        let newLowerBound = selectedUnitRange.lowerBound + 1
        self.selectedUnitRange = newLowerBound < selectedUnitRange.upperBound
            ? newLowerBound ..< selectedUnitRange.upperBound
            : nil
        return true
    }

    /// Extends a phrase selection toward the preceding reading unit.
    ///
    /// With a positioned caret, the first Shift-Left selects up to two
    /// readings immediately before the caret. Without a positioned caret,
    /// selection starts at the final reading and subsequent presses continue
    /// toward the beginning.
    @discardableResult
    mutating func extendSelectionLeft(
        from anchor: CompositionPhraseSelectionAnchor
    ) -> Bool {
        if let selectedUnitRange {
            guard selectedUnitRange.count < Self.maximumPhraseUnitCount,
                  selectedUnitRange.lowerBound > units.startIndex else {
                return false
            }

            let adjacentIndex = selectedUnitRange.lowerBound - 1
            guard units[adjacentIndex].kind == .reading else {
                return false
            }
            self.selectedUnitRange = adjacentIndex ..< selectedUnitRange.upperBound
            return true
        }

        switch anchor {
        case .bufferEdge:
            guard let lastReadingIndex = units.lastIndex(where: {
                $0.kind == .reading
            }) else {
                return false
            }
            return beginDirectionalSelection(
                at: lastReadingIndex,
                offset: -1,
                includeAdjacent: false
            )
        case let .caret(followingUnitID):
            guard let boundaryIndex = caretBoundaryIndex(
                followingUnitID: followingUnitID
            ), boundaryIndex > units.startIndex else {
                return false
            }
            let precedingIndex = boundaryIndex - 1
            guard units[precedingIndex].kind == .reading else {
                return false
            }
            return beginDirectionalSelection(
                at: precedingIndex,
                offset: -1,
                includeAdjacent: true
            )
        }
    }

    /// Extends a phrase selection toward the following reading unit.
    ///
    /// With a positioned caret, the first Shift-Right selects up to two
    /// readings immediately after the caret. Without a positioned caret,
    /// selection starts at the first reading so a prefix can be learned using
    /// Shift-Right alone.
    @discardableResult
    mutating func extendSelectionRight(
        from anchor: CompositionPhraseSelectionAnchor
    ) -> Bool {
        if let selectedUnitRange {
            guard selectedUnitRange.count < Self.maximumPhraseUnitCount,
                  selectedUnitRange.upperBound < units.endIndex else {
                return false
            }

            let adjacentIndex = selectedUnitRange.upperBound
            guard units[adjacentIndex].kind == .reading else {
                return false
            }
            self.selectedUnitRange = selectedUnitRange.lowerBound
                ..< (adjacentIndex + 1)
            return true
        }

        switch anchor {
        case .bufferEdge:
            guard let firstReadingIndex = units.firstIndex(where: {
                $0.kind == .reading
            }) else {
                return false
            }
            return beginDirectionalSelection(
                at: firstReadingIndex,
                offset: 1,
                includeAdjacent: false
            )
        case let .caret(followingUnitID):
            guard let followingUnitID,
                  let followingIndex = units.firstIndex(where: {
                      $0.id == followingUnitID
                  }), units[followingIndex].kind == .reading else {
                return false
            }
            return beginDirectionalSelection(
                at: followingIndex,
                offset: 1,
                includeAdjacent: true
            )
        }
    }

    @discardableResult
    mutating func clearSelection() -> Bool {
        guard selectedUnitRange != nil else {
            return false
        }

        selectedUnitRange = nil
        return true
    }

    /// Deletes the selected range, or one trailing unit when there is no
    /// selection. Returned units preserve their original display order.
    @discardableResult
    mutating func deleteBackward() -> [CompositionUnit] {
        guard !units.isEmpty else {
            return []
        }

        let deletionRange = selectedUnitRange
            ?? units.index(before: units.endIndex) ..< units.endIndex
        let deletedUnits = Array(units[deletionRange])
        units.removeSubrange(deletionRange)
        selectedUnitRange = nil
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
        selectedUnitRange = nil
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

    @discardableResult
    private mutating func insertCharacterCandidate(
        _ candidate: Candidate,
        before anchorUnitID: UUID,
        reason: CandidateCommitReason
    ) -> [CompositionUnit] {
        guard candidate.type == .character,
              !candidate.text.isEmpty,
              candidate.pronunciationSequence.count == 1,
              let pronunciation = candidate.pronunciationSequence.first,
              !pronunciation.isEmpty,
              let anchorIndex = units.firstIndex(where: { $0.id == anchorUnitID })
        else {
            return []
        }

        let unit = CompositionUnit(text: candidate.text, pronunciation: pronunciation)
        units.insert(unit, at: anchorIndex)
        pendingCandidateSelections.append(
            PendingCandidateSelection(
                candidate: candidate,
                reason: reason,
                coveredUnitIDs: [unit.id]
            )
        )
        clearSelection()
        return [unit]
    }

    @discardableResult
    private mutating func insertPhraseSuffix(
        _ candidate: Candidate,
        before anchorUnitID: UUID,
        reason: CandidateCommitReason
    ) -> [CompositionUnit] {
        let readings = candidate.pronunciationSequence
        let characters = Array(candidate.text)
        guard candidate.type == .phrase,
              (Self.minimumPhraseUnitCount ... Self.maximumPhraseUnitCount)
                .contains(readings.count),
              characters.count == readings.count,
              readings.allSatisfy({ !$0.isEmpty }),
              let anchorIndex = units.firstIndex(where: { $0.id == anchorUnitID })
        else {
            return []
        }

        let existingReadings = Array(readings.dropLast())
        let context = units[..<anchorIndex]
        guard context.suffix(existingReadings.count).map(\.pronunciation)
                == existingReadings else {
            return []
        }

        let removalRange = (anchorIndex - existingReadings.count) ..< anchorIndex
        units.removeSubrange(removalRange)
        pruneInvalidPendingSelections()

        let replacementUnits = zip(characters, readings).map {
            CompositionUnit(text: String($0), pronunciation: $1)
        }
        units.insert(contentsOf: replacementUnits, at: removalRange.lowerBound)
        pendingCandidateSelections.append(
            PendingCandidateSelection(
                candidate: candidate,
                reason: reason,
                coveredUnitIDs: replacementUnits.map(\.id)
            )
        )
        clearSelection()
        return replacementUnits
    }

    private func isValid(_ unit: CompositionUnit) -> Bool {
        !unit.text.isEmpty && !unit.pronunciation.isEmpty
    }

    private func caretBoundaryIndex(followingUnitID: UUID?) -> Int? {
        guard let followingUnitID else {
            return units.endIndex
        }
        return units.firstIndex(where: { $0.id == followingUnitID })
    }

    private mutating func beginDirectionalSelection(
        at startIndex: Int,
        offset: Int,
        includeAdjacent: Bool
    ) -> Bool {
        guard units.indices.contains(startIndex),
              units[startIndex].kind == .reading else {
            return false
        }

        let adjacentIndex = startIndex + offset
        if includeAdjacent,
           units.indices.contains(adjacentIndex),
           units[adjacentIndex].kind == .reading {
            selectedUnitRange = min(startIndex, adjacentIndex)
                ..< (max(startIndex, adjacentIndex) + 1)
        } else {
            selectedUnitRange = startIndex ..< (startIndex + 1)
        }
        return true
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
