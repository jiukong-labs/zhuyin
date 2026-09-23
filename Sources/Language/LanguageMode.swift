import Foundation

enum LanguageMode: String, CaseIterable, Codable, Equatable {
    case chinese
    case english

    var indicator: String {
        switch self {
        case .chinese:
            return "中"
        case .english:
            return "A"
        }
    }

    var toggled: LanguageMode {
        self == .chinese ? .english : .chinese
    }

    /// Each language state is declared as a Text Input Sources mode so it can
    /// be selected from the macOS input menu, and so the input-source Shift
    /// style can update the menu icon.
    var inputSourceIDSuffix: String {
        switch self {
        case .chinese:
            return ".Chinese"
        case .english:
            return ".English"
        }
    }

    func inputSourceID(parentID: String) -> String {
        parentID + inputSourceIDSuffix
    }

    static func mode(
        forInputSourceID inputSourceID: String?,
        parentID: String?
    ) -> LanguageMode? {
        guard let inputSourceID,
              let parentID,
              !parentID.isEmpty else {
            return nil
        }

        return allCases.first {
            $0.inputSourceID(parentID: parentID) == inputSourceID
        }
    }
}

/// How a standalone Shift changes language.
enum ShiftSwitchStyle: String, CaseIterable, Codable, Equatable {
    /// Selects Jiukong's other Text Input Sources mode, so the macOS input
    /// menu icon follows the language.
    case inputSource
    /// Changes the language inside Jiukong and leaves the selected input
    /// source alone. Some web-backed clients stop handing keys to the input
    /// method right after an input source change; this style never makes
    /// one, at the cost of an input menu icon that no longer follows Shift.
    case withinInputMethod

    /// Whether a toggle from `selectedMode` stays inside Jiukong. Only the
    /// selected Chinese mode can: with English selected, which macOS also
    /// forces for a password field, the toggle must ask macOS for Chinese.
    /// Changing only Jiukong's language there would compose Bopomofo into a
    /// field that accepts ASCII input sources only.
    func togglesWithinInputMethod(selectedMode: LanguageMode) -> Bool {
        self == .withinInputMethod && selectedMode == .chinese
    }
}

final class LanguageModeController {
    static let shared = LanguageModeController()

    private(set) var mode: LanguageMode
    /// True after a Shift toggle that left the selected input source alone,
    /// until the user selects a Jiukong mode from the system again.
    private(set) var isInternallyManaged = false

    init(initialMode: LanguageMode = .chinese) {
        mode = initialMode
    }

    /// Adopts the Jiukong mode selected through Text Input Sources, which is
    /// the user's latest explicit choice whichever switch style is in use.
    @discardableResult
    func synchronize(withSystemMode mode: LanguageMode) -> LanguageMode {
        self.mode = mode
        isInternallyManaged = false
        return mode
    }

    @discardableResult
    func toggleWithinInputMethod() -> LanguageMode {
        mode = mode.toggled
        isInternallyManaged = true
        return mode
    }

    /// A client activation reports the selected mode but is not a new user
    /// choice, so a language toggled inside Jiukong survives moving between
    /// clients.
    @discardableResult
    func activate(
        withSystemMode mode: LanguageMode,
        style: ShiftSwitchStyle
    ) -> LanguageMode {
        guard style == .inputSource || !isInternallyManaged else {
            return self.mode
        }
        return synchronize(withSystemMode: mode)
    }
}
