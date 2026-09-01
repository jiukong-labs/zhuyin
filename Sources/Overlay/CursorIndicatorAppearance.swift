import AppKit

/// The text and color the indicator shows for one language mode.
///
/// Both are overridable per mode. An override is stored only when it is
/// meaningful: blank text and unparsable colors fall back to the defaults
/// rather than producing an invisible indicator.
struct CursorIndicatorAppearance: Equatable {
    static let maximumTextLength = 4

    var chineseText: String?
    var englishText: String?
    var chineseColorHex: String?
    var englishColorHex: String?
    var compositionIndicatorColorHex: String?

    init(
        chineseText: String? = nil,
        englishText: String? = nil,
        chineseColorHex: String? = nil,
        englishColorHex: String? = nil,
        compositionIndicatorColorHex: String? = nil
    ) {
        self.chineseText = Self.sanitizedText(chineseText)
        self.englishText = Self.sanitizedText(englishText)
        self.chineseColorHex = Self.sanitizedHex(chineseColorHex)
        self.englishColorHex = Self.sanitizedHex(englishColorHex)
        self.compositionIndicatorColorHex = Self.sanitizedHex(
            compositionIndicatorColorHex
        )
    }

    func text(for mode: LanguageMode) -> String {
        switch mode {
        case .chinese:
            return chineseText ?? mode.indicator
        case .english:
            return englishText ?? mode.indicator
        }
    }

    func color(for mode: LanguageMode) -> NSColor {
        let hex: String?
        switch mode {
        case .chinese:
            hex = chineseColorHex
        case .english:
            hex = englishColorHex
        }
        return hex.flatMap(Self.color(fromHex:)) ?? Self.defaultColor(for: mode)
    }

    static func defaultColor(for mode: LanguageMode) -> NSColor {
        switch mode {
        case .chinese:
            return .systemRed
        case .english:
            return .systemBlue
        }
    }

    static let capsLockColor = NSColor.systemOrange
    static let capsLockIndicator = "⇪"

    var compositionIndicatorColor: NSColor {
        compositionIndicatorColorHex.flatMap(Self.color(fromHex:))
            ?? .systemGreen
    }

    /// Trims whitespace, drops empty text, and caps the length so the panel
    /// cannot be pushed to an unusable width.
    static func sanitizedText(_ text: String?) -> String? {
        guard let text else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return String(trimmed.prefix(maximumTextLength))
    }

    /// Accepts `#RRGGBB` or `RRGGBB` in any case and normalizes it.
    static func sanitizedHex(_ hex: String?) -> String? {
        guard let hex else {
            return nil
        }
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard digits.count == 6,
              digits.allSatisfy(\.isHexDigit) else {
            return nil
        }
        return "#" + digits.uppercased()
    }

    static func color(fromHex hex: String) -> NSColor? {
        guard let sanitized = sanitizedHex(hex) else {
            return nil
        }
        var value: UInt64 = 0
        guard Scanner(string: String(sanitized.dropFirst()))
            .scanHexInt64(&value) else {
            return nil
        }

        return NSColor(
            srgbRed: CGFloat((value & 0xFF0000) >> 16) / 255,
            green: CGFloat((value & 0x00FF00) >> 8) / 255,
            blue: CGFloat(value & 0x0000FF) / 255,
            alpha: 1
        )
    }

    static func hex(from color: NSColor) -> String? {
        guard let rgb = color.usingColorSpace(.sRGB) else {
            return nil
        }
        return String(
            format: "#%02X%02X%02X",
            Int((rgb.redComponent * 255).rounded()),
            Int((rgb.greenComponent * 255).rounded()),
            Int((rgb.blueComponent * 255).rounded())
        )
    }
}
