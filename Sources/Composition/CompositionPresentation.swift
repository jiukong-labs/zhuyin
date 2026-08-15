import Foundation

/// A pure marked-text snapshot ready for `IMKTextInput.setMarkedText`.
///
/// Converted buffer selection is exposed only while there is no active raw
/// syllable or candidate reading. An active suffix always owns the caret.
struct CompositionPresentation: Equatable {
    let text: String
    let selectionRange: NSRange

    static func make(
        buffer: CompositionBuffer,
        activeSuffix: String?
    ) -> CompositionPresentation? {
        let suffix = activeSuffix ?? ""
        let text = buffer.text + suffix
        guard !text.isEmpty else {
            return nil
        }

        let selectionRange: NSRange
        if suffix.isEmpty {
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
}
