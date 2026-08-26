import Security

/// Reads the running process's own code-signing entitlements.
///
/// The repository's ad-hoc local build deliberately ships without the
/// CloudKit container entitlement (see `JIUKONG_CLOUDKIT_ENTITLEMENTS` in
/// `project.yml`) — only a Developer Team build carries it. Constructing a
/// `CKContainer` without that entitlement traps the process instead of
/// throwing a Swift error, so callers must check first and skip CloudKit
/// entirely when it is absent.
enum ProcessEntitlements {
    static func isEntitledForICloudContainer(_ identifier: String) -> Bool {
        guard let task = SecTaskCreateFromSelf(nil) else {
            return false
        }
        guard let value = SecTaskCopyValueForEntitlement(
            task,
            "com.apple.developer.icloud-container-identifiers" as CFString,
            nil
        ) else {
            return false
        }
        guard let identifiers = value as? [String] else {
            return false
        }
        return identifiers.contains(identifier)
    }
}
