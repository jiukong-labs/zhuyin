import os

private let jiukongDiagnosticLogger = Logger(
    subsystem: "tw.idv.jiukong.inputmethod.zhuyin",
    category: "Diagnostics"
)

/// Diagnostic breadcrumbs for input-method lifecycle and overlay behavior.
/// Message contents stay private in the unified log by default.
func jiukongDebugLog(_ message: String) {
    jiukongDiagnosticLogger.debug("\(message, privacy: .private)")
}
