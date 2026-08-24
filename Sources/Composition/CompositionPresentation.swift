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
        } else if suffix.isEmpty {
            selectionRange = buffer.markedSelectionRange(
                focusedUnitID: focusedUnitID
            )
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

/// Builds marked text with an explicit visual cue for phrase selection.
/// Revision positioning requests a collapsed native selection range instead,
/// allowing clients that honor it to draw their normal blinking text cursor
/// without a colored fill.
enum CompositionMarkedTextRenderer {
    /// Suppresses the client's default marked-text fill while a revision caret
    /// is positioned. Clients that accept attributed marked text retain their
    /// native insertion caret without painting the whole composition as a
    /// selected block. The text-input client remains the final renderer.
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
                // Zero denotes an ordinary clause segment, which clients may
                // still paint as an active marked range. Carbon's explicit
                // no-highlight style leaves only the collapsed selection
                // range for the client to render as its blinking caret.
                .markedClauseSegment: Int(kTSMHiliteNoHilite),
                .underlineColor: NSColor.clear,
                .underlineStyle: 0,
            ],
            range: NSRange(location: 0, length: markedText.length)
        )
        return markedText
    }

    static func make(
        presentation: CompositionPresentation,
        highlightedRange: NSRange?
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

        markedText.addAttributes(
            [
                .backgroundColor: NSColor.selectedTextBackgroundColor,
                .foregroundColor: NSColor.selectedTextColor,
                .underlineColor: NSColor.systemGreen,
                .underlineStyle: NSUnderlineStyle.thick.rawValue,
            ],
            range: highlightedRange
        )
        return markedText
    }
}
