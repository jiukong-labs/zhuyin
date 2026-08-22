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

    /// Each language state is also declared as a Text Input Sources mode so it
    /// can be chosen explicitly from the macOS input menu. A standalone Shift
    /// toggle is kept inside Jiukong instead, avoiding macOS's separate ABC
    /// overlay while the cursor indicator presents the active state.
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
    private(set) var isInternallyManaged = false

    init(initialMode: LanguageMode = .chinese) {
        mode = initialMode
    }

    @discardableResult
    func toggleInternally() -> LanguageMode {
        mode = mode == .chinese ? .english : .chinese
        isInternallyManaged = true
        return mode
    }

    @discardableResult
    func synchronize(withSystemMode mode: LanguageMode) -> LanguageMode {
        self.mode = mode
        isInternallyManaged = false
        return mode
    }
}
