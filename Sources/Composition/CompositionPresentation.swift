import AppKit
import Carbon

/// A pure marked-text snapshot ready for `IMKTextInput.setMarkedText`.
///
/// Converted buffer selection is exposed only while there is no active raw
/// syllable or candidate reading. An active suffix always owns the caret.
struct CompositionPresentation: Equatable {
    let text: String
    let selectionRange: NSRange

    /// Web-backed clients may relocate the insertion point when they receive
    /// a non-empty marked-text selection. Phrase selection stays authoritative
    /// in the buffer, while the client receives a caret after that range.
    var caretAfterSelectionRange: NSRange {
        NSRange(
            location: selectionRange.location + selectionRange.length,
            length: 0
        )
    }

    static func make(
        buffer: CompositionBuffer,
        activeSuffix: String?,
        focusedUnitID: UUID? = nil,
        insertionAnchorUnitID: UUID? = nil
    ) -> CompositionPresentation? {
        let suffix = activeSuffix ?? ""
        let anchorIndex = insertionAnchorUnitID.flatMap { anchorID in
            buffer.units.firstIndex(where: { $0.id == anchorID })
        }
        let prefix: String
        let trailingText: String
        if let anchorIndex {
            prefix = buffer.units[..<anchorIndex].map(\.text).joined()
            trailingText = buffer.units[anchorIndex...].map(\.text).joined()
        } else {
            prefix = buffer.text
            trailingText = ""
        }
        let text = prefix + suffix + trailingText
        guard !text.isEmpty else {
            return nil
        }

        let selectionRange: NSRange
        if insertionAnchorUnitID != nil {
            selectionRange = NSRange(
                location: prefix.utf16.count + suffix.utf16.count,
                length: 0
            )
        } else if suffix.isEmpty, let focusedUnitID {
            let focusedRange = buffer.markedSelectionRange(
                focusedUnitID: focusedUnitID
            )
            selectionRange = NSRange(
                location: focusedRange.location,
                length: 0
            )
        } else if suffix.isEmpty {
            selectionRange = buffer.markedSelectionRange
        } else {
            selectionRange = NSRange(
                location: text.utf16.count,
                length: 0
            )
        }

        return CompositionPresentation(
            text: text,
            selectionRange: selectionRange
        )
    }

    /// Renders the current first/highlighted candidate without mutating the
    /// real composition buffer. This supports a quiet inline preview before
    /// the user explicitly opens the candidate window with Down Arrow.
    ///
    /// `insertionAnchorUnitID`, when set, previews landing right before that
    /// existing unit (mirroring `CompositionBuffer.insertCandidate(before:)`)
    /// instead of appending at the buffer's end — matching what will actually
    /// happen once the caller accepts this candidate while the caret is
    /// positioned via revision-focus navigation.
    static func make(
        buffer: CompositionBuffer,
        previewing candidate: Candidate,
        insertionAnchorUnitID: UUID? = nil
    ) -> CompositionPresentation? {
        var previewBuffer = buffer
        let didInsert: Bool
        if let insertionAnchorUnitID {
            didInsert = !previewBuffer.insertCandidate(
                candidate,
                before: insertionAnchorUnitID,
                reason: .implicitPassThrough
            ).isEmpty
        } else {
            didInsert = previewBuffer.acceptCandidate(
                candidate,
                reason: .implicitPassThrough
            )
        }
        guard didInsert else {
            return nil
        }
        return make(buffer: previewBuffer, activeSuffix: nil)
    }
}

/// Builds marked text with an explicit visual cue for Left/Right revision.
/// The selection range remains authoritative for the client, while explicit
/// attributes provide an additional cue in clients that honor marked-text
/// styling.
enum CompositionMarkedTextRenderer {
    enum HighlightStyle {
        case revisionFocus
        case phraseSelection
    }

    static func make(
        presentation: CompositionPresentation,
        highlightedRange: NSRange?,
        style: HighlightStyle = .phraseSelection
    ) -> NSAttributedString {
        let markedText = NSMutableAttributedString(
            string: presentation.text
        )
        guard let highlightedRange,
              highlightedRange.location != NSNotFound,
              highlightedRange.length > 0,
              highlightedRange.location <= presentation.text.utf16.count,
              highlightedRange.length
                <= presentation.text.utf16.count - highlightedRange.location else {
            return markedText
        }

        let attributes: [NSAttributedString.Key: Any]
        switch style {
        case .revisionFocus:
            attributes = [
                .backgroundColor: NSColor.systemYellow.withAlphaComponent(0.32),
                .underlineColor: NSColor.systemOrange,
                .underlineStyle: NSUnderlineStyle.thick.rawValue,
            ]
        case .phraseSelection:
            attributes = [
                .backgroundColor: NSColor.selectedTextBackgroundColor,
                .foregroundColor: NSColor.selectedTextColor,
                .underlineColor: NSColor.systemGreen,
                .underlineStyle: NSUnderlineStyle.thick.rawValue,
            ]
        }
        markedText.addAttributes(
            attributes,
            range: highlightedRange
        )
        return markedText
    }

    /// Prevents text clients from drawing their own marked-clause selection
    /// box while the revision caret is moving between existing units.
    ///
    /// The caret position is still carried separately by `selectionRange`.
    /// Supplying explicit no-highlight attributes keeps that position from
    /// being interpreted as a visually selected marked clause by clients
    /// such as Word and WebKit-backed editors.
    static func makeUnhighlighted(
        presentation: CompositionPresentation
    ) -> NSAttributedString {
        let markedText = NSMutableAttributedString(
            string: presentation.text
        )
        guard markedText.length > 0 else {
            return markedText
        }
        markedText.addAttributes(
            [
                .backgroundColor: NSColor.clear,
                .underlineStyle: 0,
                .markedClauseSegment: Int(kTSMHiliteNoHilite),
            ],
            range: NSRange(location: 0, length: markedText.length)
        )
        return markedText
    }
}
