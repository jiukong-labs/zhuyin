import Foundation

/// TEMPORARY diagnostic helper — writes plain text to /tmp so log lines are
/// visible even if this process's NSLog output isn't reaching the unified
/// log. Remove once the cursor-indicator visibility investigation is done.
func jiukongDebugLog(_ message: String) {
    let line = "\(Date()) \(message)\n"
    guard let data = line.data(using: .utf8) else { return }
    let path = "/tmp/jiukong_debug.log"
    if let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        handle.write(data)
        handle.closeFile()
    } else {
        try? data.write(to: URL(fileURLWithPath: path))
    }
}
