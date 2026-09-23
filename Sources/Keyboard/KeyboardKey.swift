enum KeyboardKey: Hashable {
    case digit0
    case digit1
    case digit2
    case digit3
    case digit4
    case digit5
    case digit6
    case digit7
    case digit8
    case digit9
    case letterA
    case letterB
    case letterC
    case letterD
    case letterE
    case letterF
    case letterG
    case letterH
    case letterI
    case letterJ
    case letterK
    case letterL
    case letterM
    case letterN
    case letterO
    case letterP
    case letterQ
    case letterR
    case letterS
    case letterT
    case letterU
    case letterV
    case letterW
    case letterX
    case letterY
    case letterZ
    case comma
    case period
    case semicolon
    case slash
    case minus
    // Unused by the standard arrangement. Milestone 9 places punctuation on the
    // bracket keys; Milestone 10 uses quote and equal for other arrangements.
    case quote
    case equal
    case leftBracket
    case rightBracket
    case backslash
    case space
    case deleteBackward
    case escape
    case returnKey
    case keypadEnter
}


extension KeyboardKey {
    var lowercaseASCIILetter: String? {
        switch self {
        case .letterA: return "a"
        case .letterB: return "b"
        case .letterC: return "c"
        case .letterD: return "d"
        case .letterE: return "e"
        case .letterF: return "f"
        case .letterG: return "g"
        case .letterH: return "h"
        case .letterI: return "i"
        case .letterJ: return "j"
        case .letterK: return "k"
        case .letterL: return "l"
        case .letterM: return "m"
        case .letterN: return "n"
        case .letterO: return "o"
        case .letterP: return "p"
        case .letterQ: return "q"
        case .letterR: return "r"
        case .letterS: return "s"
        case .letterT: return "t"
        case .letterU: return "u"
        case .letterV: return "v"
        case .letterW: return "w"
        case .letterX: return "x"
        case .letterY: return "y"
        case .letterZ: return "z"
        default: return nil
        }
    }

    var decimalDigit: Int? {
        switch self {
        case .digit0: return 0
        case .digit1: return 1
        case .digit2: return 2
        case .digit3: return 3
        case .digit4: return 4
        case .digit5: return 5
        case .digit6: return 6
        case .digit7: return 7
        case .digit8: return 8
        case .digit9: return 9
        default: return nil
        }
    }
}
