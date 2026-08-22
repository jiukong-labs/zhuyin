import Foundation

enum LanguageMode: String, CaseIterable, Codable, Equatable {
    case chinese
    case english

    var indicator: String {
        switch self {
        case .chinese:
            return "中"
        case .english:
            return "英"
        }
    }

    /// Each language state is a real Text Input Sources mode. macOS can then
    /// update the existing input-menu icon when the state changes instead of
    /// requiring a second status item owned by the input method.
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
    func toggle() -> LanguageMode {
        mode = mode == .chinese ? .english : .chinese
        return mode
    }

    @discardableResult
    func setMode(_ mode: LanguageMode) -> LanguageMode {
        self.mode = mode
        return mode
    }
}
