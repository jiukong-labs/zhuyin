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

    /// Each language state is declared as a Text Input Sources mode so both
    /// direct menu selection and standalone Shift switching can update the
    /// macOS input-menu icon.
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

final class LanguageModeController {
    static let shared = LanguageModeController()

    private(set) var mode: LanguageMode

    init(initialMode: LanguageMode = .chinese) {
        mode = initialMode
    }

    @discardableResult
    func synchronize(withSystemMode mode: LanguageMode) -> LanguageMode {
        self.mode = mode
        return mode
    }
}
