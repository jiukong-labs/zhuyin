import AppKit
import Carbon

enum CompositionSelectionCommand: Equatable {
    case extendLeft
    case extendRight
}

/// Recognizes only the two directional phrase-selection gestures owned by
/// composition.
/// Carbon reports arrow keys with `.function` and some keyboards may also set
/// `.numericPad`; those inherent flags are allowed. Real shortcut modifiers
/// remain available to the client application.
enum CompositionSelectionCommandRouter {
    private static let rejectedModifiers: NSEvent.ModifierFlags = [
        .command,
        .control,
        .option
    ]

    static func command(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    ) -> CompositionSelectionCommand? {
        let modifiers = modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.shift),
              modifiers.intersection(rejectedModifiers).isEmpty else {
            return nil
        }

        switch Int(keyCode) {
        case kVK_LeftArrow:
            return .extendLeft
        case kVK_RightArrow:
            return .extendRight
        default:
            return nil
        }
    }
}

enum CompositionCursorCommand: Equatable {
    case previousReading
    case nextReading
}

enum CompositionRevisionCandidateCommand: Equatable {
    case openCandidates
    case returnToPositioning
}

/// Down opens candidates only after a revision caret has been positioned.
/// While those candidates are open, Up returns to text positioning. Keeping
/// this route ahead of ordinary candidate navigation gives the two modes an
/// explicit, reversible boundary.
enum CompositionRevisionCandidateCommandRouter {
    private static let rejectedModifiers: NSEvent.ModifierFlags = [
        .command,
        .control,
        .option,
        .shift
    ]

    static func command(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        hasRevisionCaret: Bool,
        isChoosingCandidates: Bool
    ) -> CompositionRevisionCandidateCommand? {
        let modifiers = modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.intersection(rejectedModifiers).isEmpty else {
            return nil
        }

        switch Int(keyCode) {
        case kVK_DownArrow where hasRevisionCaret && !isChoosingCandidates:
            return .openCandidates
        case kVK_UpArrow where isChoosingCandidates:
            return .returnToPositioning
        default:
            return nil
        }
    }
}

/// Plain left/right arrows move through uncommitted reading units. Function,
/// numeric-pad, and Caps Lock flags are inherent/non-semantic; actual shortcut
/// modifiers remain available to the client application.
enum CompositionCursorCommandRouter {
    private static let rejectedModifiers: NSEvent.ModifierFlags = [
        .command,
        .control,
        .option,
        .shift
    ]

    static func command(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    ) -> CompositionCursorCommand? {
        let modifiers = modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.intersection(rejectedModifiers).isEmpty else {
            return nil
        }

        switch Int(keyCode) {
        case kVK_LeftArrow:
            return .previousReading
        case kVK_RightArrow:
            return .nextReading
        default:
            return nil
        }
    }
}

enum CompositionDeletionCommand: Equatable {
    case deleteBackward
    case deleteForward
}

/// Recognizes the two physical deletion keys only when no real shortcut
/// modifier is present. The controller claims them only for an explicit
/// composition focus or phrase range; otherwise normal candidate, syllable,
/// and client editing behavior remains in charge.
enum CompositionDeletionCommandRouter {
    private static let rejectedModifiers: NSEvent.ModifierFlags = [
        .command,
        .control,
        .option,
        .shift
    ]

    static func command(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    ) -> CompositionDeletionCommand? {
        let modifiers = modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.intersection(rejectedModifiers).isEmpty else {
            return nil
        }

        switch Int(keyCode) {
        case kVK_Delete:
            return .deleteBackward
        case kVK_ForwardDelete:
            return .deleteForward
        default:
            return nil
        }
    }
}
