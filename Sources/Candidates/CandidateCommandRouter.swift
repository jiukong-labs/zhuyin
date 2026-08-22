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
        isExpanded: Bool,
        isExplicitSelectionContext: Bool = false,
        mappedBopomofoComponent: BopomofoComponent? = nil,
        highlightedSelectionKeyIndex: Int? = nil
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
            return numberCommand(
                0,
                isExpanded: isExpanded,
                isExplicitSelectionContext: isExplicitSelectionContext,
                mappedBopomofoComponent: mappedBopomofoComponent,
                highlightedSelectionKeyIndex: highlightedSelectionKeyIndex
            )
        case kVK_ANSI_2:
            return numberCommand(
                1,
                isExpanded: isExpanded,
                isExplicitSelectionContext: isExplicitSelectionContext,
                mappedBopomofoComponent: mappedBopomofoComponent,
                highlightedSelectionKeyIndex: highlightedSelectionKeyIndex
            )
        case kVK_ANSI_3:
            return numberCommand(
                2,
                isExpanded: isExpanded,
                isExplicitSelectionContext: isExplicitSelectionContext,
                mappedBopomofoComponent: mappedBopomofoComponent,
                highlightedSelectionKeyIndex: highlightedSelectionKeyIndex
            )
        case kVK_ANSI_4:
            return numberCommand(
                3,
                isExpanded: isExpanded,
                isExplicitSelectionContext: isExplicitSelectionContext,
                mappedBopomofoComponent: mappedBopomofoComponent,
                highlightedSelectionKeyIndex: highlightedSelectionKeyIndex
            )
        case kVK_ANSI_5:
            return numberCommand(
                4,
                isExpanded: isExpanded,
                isExplicitSelectionContext: isExplicitSelectionContext,
                mappedBopomofoComponent: mappedBopomofoComponent,
                highlightedSelectionKeyIndex: highlightedSelectionKeyIndex
            )
        case kVK_ANSI_6:
            return numberCommand(
                5,
                isExpanded: isExpanded,
                isExplicitSelectionContext: isExplicitSelectionContext,
                mappedBopomofoComponent: mappedBopomofoComponent,
                highlightedSelectionKeyIndex: highlightedSelectionKeyIndex
            )
        case kVK_ANSI_7:
            return numberCommand(
                6,
                isExpanded: isExpanded,
                isExplicitSelectionContext: isExplicitSelectionContext,
                mappedBopomofoComponent: mappedBopomofoComponent,
                highlightedSelectionKeyIndex: highlightedSelectionKeyIndex
            )
        case kVK_ANSI_8:
            return numberCommand(
                7,
                isExpanded: isExpanded,
                isExplicitSelectionContext: isExplicitSelectionContext,
                mappedBopomofoComponent: mappedBopomofoComponent,
                highlightedSelectionKeyIndex: highlightedSelectionKeyIndex
            )
        case kVK_ANSI_9:
            return numberCommand(
                8,
                isExpanded: isExpanded,
                isExplicitSelectionContext: isExplicitSelectionContext,
                mappedBopomofoComponent: mappedBopomofoComponent,
                highlightedSelectionKeyIndex: highlightedSelectionKeyIndex
            )
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

    /// Compact candidates remain composition-first for ambiguous number-row
    /// Bopomofo keys, except that the number printed on the current highlight
    /// always confirms that candidate. This makes the default `1` actionable
    /// while a different ambiguous digit can still begin the next syllable.
    /// Expanded presentation and text revision are explicit contexts: every
    /// printed 1-9 key selects there, even when the key maps to Bopomofo.
    private static func numberCommand(
        _ selectionKeyIndex: Int,
        isExpanded: Bool,
        isExplicitSelectionContext: Bool,
        mappedBopomofoComponent: BopomofoComponent?,
        highlightedSelectionKeyIndex: Int?
    ) -> CandidateCommand? {
        if !isExpanded,
           !isExplicitSelectionContext,
           mappedBopomofoComponent?.canBeginSyllable == true,
           selectionKeyIndex != highlightedSelectionKeyIndex {
            return nil
        }
        return .select(selectionKeyIndex)
    }

    private static func hasNoShortcutModifiers(
        _ modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        let modifiers = modifierFlags.intersection(.deviceIndependentFlagsMask)
        return modifiers.intersection(shortcutModifiers).isEmpty
    }
}
