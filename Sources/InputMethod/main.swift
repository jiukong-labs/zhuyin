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

    guard let server = IMKServer(
        name: configuration.connectionName,
        bundleIdentifier: configuration.bundleIdentifier
    ) else {
        throw InputMethodApplicationError.serverInitializationFailed
    }

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
