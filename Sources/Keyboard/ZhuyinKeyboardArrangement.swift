/// The physical Bopomofo arrangements this build can type on.
///
/// Every arrangement here is a one-to-one table: a key produces exactly one
/// component, so no arrangement needs disambiguation while composing. The
/// ambiguous 26-key arrangements are deliberately not included.
enum ZhuyinKeyboardArrangement: String, CaseIterable, Codable, Equatable {
    case standard
    case eten
    case ibm

    var layout: any KeyboardLayout {
        switch self {
        case .standard:
            return StandardZhuyinLayout()
        case .eten:
            return EtenZhuyinLayout()
        case .ibm:
            return IBMZhuyinLayout()
        }
    }

    var localizedName: String {
        switch self {
        case .standard:
            return "標準（大千）"
        case .eten:
            return "倚天傳統"
        case .ibm:
            return "IBM"
        }
    }
}

/// A one-to-one arrangement expressed as a table rather than a switch.
///
/// `TableZhuyinLayout` exists so an arrangement can be read as the physical
/// keyboard it describes, and so tests can assert that a table covers all 37
/// symbols and 5 tones without repeating a key.
struct TableZhuyinLayout: KeyboardLayout {
    let components: [KeyboardKey: BopomofoComponent]

    func component(for key: KeyboardKey) -> BopomofoComponent? {
        components[key]
    }
}

/// 倚天傳統: initials and finals follow Wade-Giles or visual similarity, so
/// every letter key carries exactly one symbol.
///
/// ```text
/// 1 ˙   2 ˊ   3 ˇ   4 ˋ   7 ㄑ  8 ㄢ  9 ㄣ  0 ㄤ  - ㄥ  = ㄦ
/// q ㄟ  w ㄝ  e ㄧ  r ㄜ  t ㄊ  y ㄡ  u ㄩ  i ㄞ  o ㄛ  p ㄆ
/// a ㄚ  s ㄙ  d ㄉ  f ㄈ  g ㄐ  h ㄏ  j ㄖ  k ㄎ  l ㄌ  ; ㄗ  ' ㄘ
/// z ㄠ  x ㄨ  c ㄒ  v ㄍ  b ㄅ  n ㄋ  m ㄇ  , ㄓ  . ㄔ  / ㄕ
/// Space 一聲
/// ```
struct EtenZhuyinLayout: KeyboardLayout {
    private static let table = TableZhuyinLayout(
        components: [
            .letterB: .initial(.b),
            .letterP: .initial(.p),
            .letterM: .initial(.m),
            .letterF: .initial(.f),
            .letterD: .initial(.d),
            .letterT: .initial(.t),
            .letterN: .initial(.n),
            .letterL: .initial(.l),
            .letterV: .initial(.g),
            .letterK: .initial(.k),
            .letterH: .initial(.h),
            .letterG: .initial(.j),
            .digit7: .initial(.q),
            .letterC: .initial(.x),
            .comma: .initial(.zh),
            .period: .initial(.ch),
            .slash: .initial(.sh),
            .letterJ: .initial(.r),
            .semicolon: .initial(.z),
            .quote: .initial(.c),
            .letterS: .initial(.s),
            .letterE: .medial(.i),
            .letterX: .medial(.u),
            .letterU: .medial(.yu),
            .letterA: .final(.a),
            .letterO: .final(.o),
            .letterR: .final(.e),
            .letterW: .final(.eh),
            .letterI: .final(.ai),
            .letterQ: .final(.ei),
            .letterZ: .final(.ao),
            .letterY: .final(.ou),
            .digit8: .final(.an),
            .digit9: .final(.en),
            .digit0: .final(.ang),
            .minus: .final(.eng),
            .equal: .final(.er),
            .space: .tone(.first),
            .digit2: .tone(.second),
            .digit3: .tone(.third),
            .digit4: .tone(.fourth),
            .digit1: .tone(.neutral),
        ]
    )

    func component(for key: KeyboardKey) -> BopomofoComponent? {
        Self.table.component(for: key)
    }
}

/// IBM: the 37 symbols run in Bopomofo order straight across the keyboard.
///
/// ```text
/// 1 ㄅ  2 ㄆ  3 ㄇ  4 ㄈ  5 ㄉ  6 ㄊ  7 ㄋ  8 ㄌ  9 ㄍ  0 ㄎ  - ㄏ
/// q ㄐ  w ㄑ  e ㄒ  r ㄓ  t ㄔ  y ㄕ  u ㄖ  i ㄗ  o ㄘ  p ㄙ
/// a ㄧ  s ㄨ  d ㄩ  f ㄚ  g ㄛ  h ㄜ  j ㄝ  k ㄞ  l ㄟ  ; ㄠ
/// z ㄡ  x ㄢ  c ㄣ  v ㄤ  b ㄥ  n ㄦ  m ˊ   , ˇ   . ˋ   / ˙
/// Space 一聲
/// ```
struct IBMZhuyinLayout: KeyboardLayout {
    private static let table = TableZhuyinLayout(
        components: [
            .digit1: .initial(.b),
            .digit2: .initial(.p),
            .digit3: .initial(.m),
            .digit4: .initial(.f),
            .digit5: .initial(.d),
            .digit6: .initial(.t),
            .digit7: .initial(.n),
            .digit8: .initial(.l),
            .digit9: .initial(.g),
            .digit0: .initial(.k),
            .minus: .initial(.h),
            .letterQ: .initial(.j),
            .letterW: .initial(.q),
            .letterE: .initial(.x),
            .letterR: .initial(.zh),
            .letterT: .initial(.ch),
            .letterY: .initial(.sh),
            .letterU: .initial(.r),
            .letterI: .initial(.z),
            .letterO: .initial(.c),
            .letterP: .initial(.s),
            .letterA: .medial(.i),
            .letterS: .medial(.u),
            .letterD: .medial(.yu),
            .letterF: .final(.a),
            .letterG: .final(.o),
            .letterH: .final(.e),
            .letterJ: .final(.eh),
            .letterK: .final(.ai),
            .letterL: .final(.ei),
            .semicolon: .final(.ao),
            .letterZ: .final(.ou),
            .letterX: .final(.an),
            .letterC: .final(.en),
            .letterV: .final(.ang),
            .letterB: .final(.eng),
            .letterN: .final(.er),
            .space: .tone(.first),
            .letterM: .tone(.second),
            .comma: .tone(.third),
            .period: .tone(.fourth),
            .slash: .tone(.neutral),
        ]
    )

    func component(for key: KeyboardKey) -> BopomofoComponent? {
        Self.table.component(for: key)
    }
}
