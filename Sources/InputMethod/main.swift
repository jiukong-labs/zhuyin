import AppKit
import Darwin
import InputMethodKit

private enum InputMethodApplicationError: LocalizedError {
    case missingInfoDictionary
    case serverInitializationFailed

    var errorDescription: String? {
        switch self {
        case .missingInfoDictionary:
            return "The input method bundle does not contain an Info.plist dictionary."
        case .serverInitializationFailed:
            return "InputMethodKit could not initialize the input method server."
        }
    }
}

private func runApplication() throws {
    guard let infoDictionary = Bundle.main.infoDictionary else {
        throw InputMethodApplicationError.missingInfoDictionary
    }

    let configuration = try InputMethodConfiguration(infoDictionary: infoDictionary)
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments == ["--register"] {
        let source = try InputSourceRegistrar.register(
            bundleURL: Bundle.main.bundleURL,
            bundleIdentifier: configuration.bundleIdentifier
        )
        print("macOS registered input source: \(source.localizedName)")
        print("  ID: \(source.identifier)")
        print("  Type: \(source.type)")
        print("  URL: \(Bundle.main.bundleURL.standardizedFileURL.path)")
        print("  Enable request: accepted")
        return
    }

    if arguments == ["--disable"] {
        if let source = try InputSourceRegistrar.disable(
            bundleIdentifier: configuration.bundleIdentifier
        ) {
            print("macOS disabled input source: \(source.localizedName)")
            print("  ID: \(source.identifier)")
        } else {
            print("macOS did not return an installed input source to disable.")
        }
        return
    }

    // Maintainer verification path: the settings window is normally opened from
    // the macOS input menu, which requires an installed and selected input
    // source. This shows the same window without starting an input session.
    if arguments == ["--settings"] {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        UserLearningService.shared.startCloudSync()
        CloudPreferencesSyncService.shared.start()
        UpdateController.shared.startAutomaticChecks()
        DispatchQueue.main.async {
            SettingsWindowController.shared.show()
        }
        application.run()
        return
    }

    guard let server = IMKServer(
        name: configuration.connectionName,
        bundleIdentifier: configuration.bundleIdentifier
    ) else {
        throw InputMethodApplicationError.serverInitializationFailed
    }

    jiukongDebugLog("main.swift about to start SystemInputSourceObserver")
    // Owns the cursor indicator's visibility for as long as this process
    // runs, independent of any particular client's text-field focus.
    SystemInputSourceObserver.shared.start()
    UserLearningService.shared.startCloudSync()
    CloudPreferencesSyncService.shared.start()
    UpdateController.shared.startAutomaticChecks()
    jiukongDebugLog("main.swift finished starting SystemInputSourceObserver")

    withExtendedLifetime(server) {
        NSApplication.shared.run()
    }
}

do {
    try runApplication()
} catch {
    let message = "Jiukong Zhuyin failed: \(error.localizedDescription)\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(EXIT_FAILURE)
}
