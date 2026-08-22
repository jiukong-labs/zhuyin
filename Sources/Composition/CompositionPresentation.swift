import AppKit

/// A pure marked-text snapshot ready for `IMKTextInput.setMarkedText`.
///
/// Converted buffer selection is exposed only while there is no active raw
/// syllable or candidate reading. An active suffix always owns the caret.
struct CompositionPresentation: Equatable {
    let text: String
    let selectionRange: NSRange

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
/// The selection range remains authoritative for the client, while the
/// background and thick underline stay visible in clients that paint the
/// entire active composition with one selection color.
enum CompositionMarkedTextRenderer {
    static func make(
        presentation: CompositionPresentation,
        focusedRange: NSRange?
    ) -> NSAttributedString {
        let markedText = NSMutableAttributedString(
            string: presentation.text
        )
        guard let focusedRange,
              focusedRange.location != NSNotFound,
              focusedRange.length > 0,
              focusedRange.location <= presentation.text.utf16.count,
              focusedRange.length
                <= presentation.text.utf16.count - focusedRange.location else {
            return markedText
        }

        markedText.addAttributes(
            [
                .backgroundColor: NSColor.systemYellow.withAlphaComponent(0.32),
                .underlineColor: NSColor.systemOrange,
                .underlineStyle: NSUnderlineStyle.thick.rawValue,
            ],
            range: focusedRange
        )
        return markedText
    }
}
