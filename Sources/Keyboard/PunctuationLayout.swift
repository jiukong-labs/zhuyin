/// Full-width Chinese punctuation reachable from the Zhuyin arrangement.
///
/// Every Zhuyin key keeps its Bopomofo meaning unshifted; punctuation that
/// shares such a key is placed on Shift. The three keys the arrangement never
/// uses carry the bracket-style marks directly. Anything not listed here is
/// still returned to the client application, so the macOS keyboard layout keeps
/// producing ordinary ASCII.
struct PunctuationLayout {
    static let standard = PunctuationLayout()

    /// Keys the Zhuyin arrangement does not use.
    private let unshifted: [KeyboardKey: String] = [
        .leftBracket: "「",
        .rightBracket: "」",
        .backslash: "、",
    ]

    /// Shift plus a physical key reserved for Chinese punctuation.
    private let shifted: [KeyboardKey: String] = [
        .comma: "，",
        .period: "。",
        .slash: "？",
        .semicolon: "：",
        .digit1: "！",
        .digit6: "…",
        .digit9: "（",
        .digit0: "）",
        .minus: "—",
        .leftBracket: "『",
        .rightBracket: "』",
        .backslash: "／",
    ]

    func punctuation(for key: KeyboardKey, shifted isShifted: Bool) -> String? {
        isShifted ? shifted[key] : unshifted[key]
    }
}
