import AppKit
import Carbon

enum MacVirtualKeyResolver {
    static func key(for keyCode: UInt16) -> KeyboardKey? {
        switch Int(keyCode) {
        case kVK_ANSI_0: return .digit0
        case kVK_ANSI_1: return .digit1
        case kVK_ANSI_2: return .digit2
        case kVK_ANSI_3: return .digit3
        case kVK_ANSI_4: return .digit4
        case kVK_ANSI_5: return .digit5
        case kVK_ANSI_6: return .digit6
        case kVK_ANSI_7: return .digit7
        case kVK_ANSI_8: return .digit8
        case kVK_ANSI_9: return .digit9
        case kVK_ANSI_A: return .letterA
        case kVK_ANSI_B: return .letterB
        case kVK_ANSI_C: return .letterC
        case kVK_ANSI_D: return .letterD
        case kVK_ANSI_E: return .letterE
        case kVK_ANSI_F: return .letterF
        case kVK_ANSI_G: return .letterG
        case kVK_ANSI_H: return .letterH
        case kVK_ANSI_I: return .letterI
        case kVK_ANSI_J: return .letterJ
        case kVK_ANSI_K: return .letterK
        case kVK_ANSI_L: return .letterL
        case kVK_ANSI_M: return .letterM
        case kVK_ANSI_N: return .letterN
        case kVK_ANSI_O: return .letterO
        case kVK_ANSI_P: return .letterP
        case kVK_ANSI_Q: return .letterQ
        case kVK_ANSI_R: return .letterR
        case kVK_ANSI_S: return .letterS
        case kVK_ANSI_T: return .letterT
        case kVK_ANSI_U: return .letterU
        case kVK_ANSI_V: return .letterV
        case kVK_ANSI_W: return .letterW
        case kVK_ANSI_X: return .letterX
        case kVK_ANSI_Y: return .letterY
        case kVK_ANSI_Z: return .letterZ
        case kVK_ANSI_Comma: return .comma
        case kVK_ANSI_Period: return .period
        case kVK_ANSI_Semicolon: return .semicolon
        case kVK_ANSI_Slash: return .slash
        case kVK_ANSI_Minus: return .minus
        case kVK_ANSI_Quote: return .quote
        case kVK_ANSI_Equal: return .equal
        case kVK_ANSI_LeftBracket: return .leftBracket
        case kVK_ANSI_RightBracket: return .rightBracket
        case kVK_ANSI_Backslash: return .backslash
        case kVK_Space: return .space
        case kVK_Delete: return .deleteBackward
        case kVK_Escape: return .escape
        case kVK_Return: return .returnKey
        case kVK_ANSI_KeypadEnter: return .keypadEnter
        default: return nil
        }
    }
}

/// A Chinese-mode escape for entering ASCII letters and digits without
/// changing input mode. Other Option chords remain owned by the client.
enum OptionASCIIShortcut {
    static func text(
        for key: KeyboardKey?,
        modifierFlags: NSEvent.ModifierFlags
    ) -> String? {
        let modifiers = modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting(.capsLock)
        guard modifiers == .option || modifiers == [.option, .shift] else {
            return nil
        }

        switch key {
        case .digit0 where modifiers == .option: return "0"
        case .digit1 where modifiers == .option: return "1"
        case .digit2 where modifiers == .option: return "2"
        case .digit3 where modifiers == .option: return "3"
        case .digit4 where modifiers == .option: return "4"
        case .digit5 where modifiers == .option: return "5"
        case .digit6 where modifiers == .option: return "6"
        case .digit7 where modifiers == .option: return "7"
        case .digit8 where modifiers == .option: return "8"
        case .digit9 where modifiers == .option: return "9"
        case .letterA: return letter("a", modifiers: modifiers)
        case .letterB: return letter("b", modifiers: modifiers)
        case .letterC: return letter("c", modifiers: modifiers)
        case .letterD: return letter("d", modifiers: modifiers)
        case .letterE: return letter("e", modifiers: modifiers)
        case .letterF: return letter("f", modifiers: modifiers)
        case .letterG: return letter("g", modifiers: modifiers)
        case .letterH: return letter("h", modifiers: modifiers)
        case .letterI: return letter("i", modifiers: modifiers)
        case .letterJ: return letter("j", modifiers: modifiers)
        case .letterK: return letter("k", modifiers: modifiers)
        case .letterL: return letter("l", modifiers: modifiers)
        case .letterM: return letter("m", modifiers: modifiers)
        case .letterN: return letter("n", modifiers: modifiers)
        case .letterO: return letter("o", modifiers: modifiers)
        case .letterP: return letter("p", modifiers: modifiers)
        case .letterQ: return letter("q", modifiers: modifiers)
        case .letterR: return letter("r", modifiers: modifiers)
        case .letterS: return letter("s", modifiers: modifiers)
        case .letterT: return letter("t", modifiers: modifiers)
        case .letterU: return letter("u", modifiers: modifiers)
        case .letterV: return letter("v", modifiers: modifiers)
        case .letterW: return letter("w", modifiers: modifiers)
        case .letterX: return letter("x", modifiers: modifiers)
        case .letterY: return letter("y", modifiers: modifiers)
        case .letterZ: return letter("z", modifiers: modifiers)
        default: return nil
        }
    }

    private static func letter(
        _ lowercase: String,
        modifiers: NSEvent.ModifierFlags
    ) -> String {
        modifiers.contains(.shift) ? lowercase.uppercased() : lowercase
    }
}
