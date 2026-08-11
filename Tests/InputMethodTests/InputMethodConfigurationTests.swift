import XCTest

final class InputMethodConfigurationTests: XCTestCase {
    func testLoadsRequiredValues() throws {
        let configuration = try InputMethodConfiguration(infoDictionary: [
            "InputMethodConnectionName": "example.connection",
            "CFBundleIdentifier": "example.bundle"
        ])

        XCTAssertEqual(configuration.connectionName, "example.connection")
        XCTAssertEqual(configuration.bundleIdentifier, "example.bundle")
    }

    func testRejectsMissingConnectionName() {
        XCTAssertThrowsError(
            try InputMethodConfiguration(infoDictionary: [
                "CFBundleIdentifier": "example.bundle"
            ])
        ) { error in
            XCTAssertEqual(
                error as? InputMethodConfigurationError,
                .missingValue("InputMethodConnectionName")
            )
        }
    }

    func testRejectsBlankBundleIdentifier() {
        XCTAssertThrowsError(
            try InputMethodConfiguration(infoDictionary: [
                "InputMethodConnectionName": "example.connection",
                "CFBundleIdentifier": "  \n"
            ])
        ) { error in
            XCTAssertEqual(
                error as? InputMethodConfigurationError,
                .missingValue("CFBundleIdentifier")
            )
        }
    }
}
