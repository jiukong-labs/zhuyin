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

private let jiukongShiftTraceLogger = Logger(
    subsystem: "tw.idv.jiukong.inputmethod.zhuyin",
    category: "ShiftTrace"
)

/// Temporary instrumentation for the intermittent Shift language toggle.
///
/// Logged at the default level with public privacy on purpose: default-level
/// messages reach the unified log's on-disk store, so a failure that happens
/// minutes or hours from now can still be read back with `log show` instead of
/// requiring a live stream to have been running when it happened.
func jiukongShiftTrace(_ message: String) {
    jiukongShiftTraceLogger.log("\(message, privacy: .public)")
}
