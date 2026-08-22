import AppKit
import Carbon

enum CompositionSelectionCommand: Equatable {
    case expandBackward
    case shrinkForward
}

/// Recognizes only the two phrase-selection gestures owned by composition.
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
            return .expandBackward
        case kVK_RightArrow:
            return .shrinkForward
        default:
            return nil
        }
    }
}

enum CompositionCursorCommand: Equatable {
    case previousReading
    case nextReading
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
