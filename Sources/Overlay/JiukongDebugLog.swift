import OSLog

private let jiukongDiagnosticLogger = Logger(
    subsystem: "tw.idv.jiukong.inputmethod.zhuyin",
    category: "CursorIndicator"
)

/// Keeps cursor-indicator diagnostics in macOS's protected unified log instead
/// of following a predictable path in the shared `/tmp` directory.
func jiukongDebugLog(_ message: String) {
    jiukongDiagnosticLogger.debug("\(message, privacy: .private)")
}
