import Foundation

enum LanguageMode: String, Codable, Equatable {
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
}
