import AppKit

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
        focusedUnitID: UUID? = nil
    ) -> CompositionPresentation? {
        let suffix = activeSuffix ?? ""
        let text = buffer.text + suffix
        guard !text.isEmpty else {
            return nil
        }

        let selectionRange: NSRange
        if suffix.isEmpty {
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
    static func make(
        buffer: CompositionBuffer,
        previewing candidate: Candidate
    ) -> CompositionPresentation? {
        var previewBuffer = buffer
        guard previewBuffer.acceptCandidate(
            candidate,
            reason: .implicitPassThrough
        ) else {
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
        style: HighlightStyle = .revisionFocus
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
}
