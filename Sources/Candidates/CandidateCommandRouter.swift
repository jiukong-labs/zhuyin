import AppKit
import Carbon

enum CandidateCommand: Equatable {
    case expand
    case navigate(CandidateNavigation)
    case select(Int)
    case commitFirst
    case commitHighlighted
    case cancel
    case deleteBackward
}

enum CandidateCommandRouter {
    private static let shortcutModifiers: NSEvent.ModifierFlags = [
        .command,
        .control,
        .option,
        .shift
    ]

    static func command(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        isExpanded: Bool
    ) -> CandidateCommand? {
        guard hasNoShortcutModifiers(modifierFlags) else {
            return nil
        }

        switch Int(keyCode) {
        case kVK_DownArrow:
            return isExpanded ? .navigate(.down) : .expand
        case kVK_UpArrow:
            return isExpanded ? .navigate(.up) : .navigate(.previous)
        case kVK_LeftArrow:
            return .navigate(.previous)
        case kVK_RightArrow:
            return .navigate(.next)
        case kVK_Home:
            return .navigate(.first)
        case kVK_End:
            return .navigate(.last)
        case kVK_PageUp:
            return .navigate(.previousPage)
        case kVK_PageDown:
            return .navigate(.nextPage)
        case kVK_ANSI_1:
            return .select(0)
        case kVK_ANSI_2:
            return .select(1)
        case kVK_ANSI_3:
            return .select(2)
        case kVK_ANSI_4:
            return .select(3)
        case kVK_ANSI_5:
            return .select(4)
        case kVK_ANSI_6:
            return .select(5)
        case kVK_ANSI_7:
            return .select(6)
        case kVK_ANSI_8:
            return .select(7)
        case kVK_ANSI_9:
            return .select(8)
        case kVK_Space:
            return .commitFirst
        case kVK_Return, kVK_ANSI_KeypadEnter:
            return .commitHighlighted
        case kVK_Escape:
            return .cancel
        case kVK_Delete:
            return .deleteBackward
        default:
            return nil
        }
    }

    private static func hasNoShortcutModifiers(
        _ modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        let modifiers = modifierFlags.intersection(.deviceIndependentFlagsMask)
        return modifiers.intersection(shortcutModifiers).isEmpty
    }
}
