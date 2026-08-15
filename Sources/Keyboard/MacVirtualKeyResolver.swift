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
