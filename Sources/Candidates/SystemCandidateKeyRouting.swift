import AppKit
import Carbon

enum SystemCandidateKeyRouting {
    private static let shortcutModifiers: NSEvent.ModifierFlags = [
        .command,
        .control,
        .option,
        .shift
    ]

    static func navigation(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    ) -> CandidateNavigation? {
        guard hasNoShortcutModifiers(modifierFlags) else {
            return nil
        }

        switch Int(keyCode) {
        case kVK_LeftArrow, kVK_UpArrow:
            return .previous
        case kVK_RightArrow, kVK_DownArrow:
            return .next
        case kVK_Home:
            return .first
        case kVK_End:
            return .last
        case kVK_PageUp:
            return .previousPage
        case kVK_PageDown:
            return .nextPage
        default:
            return nil
        }
    }

    static func selectionKeyIndex(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Int? {
        guard hasNoShortcutModifiers(modifierFlags) else {
            return nil
        }

        switch Int(keyCode) {
        case kVK_ANSI_1: return 0
        case kVK_ANSI_2: return 1
        case kVK_ANSI_3: return 2
        case kVK_ANSI_4: return 3
        case kVK_ANSI_5: return 4
        case kVK_ANSI_6: return 5
        case kVK_ANSI_7: return 6
        case kVK_ANSI_8: return 7
        case kVK_ANSI_9: return 8
        default: return nil
        }
    }

    private static func hasNoShortcutModifiers(
        _ modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        let modifiers = modifierFlags.intersection(.deviceIndependentFlagsMask)
        return modifiers.intersection(shortcutModifiers).isEmpty
    }
}
