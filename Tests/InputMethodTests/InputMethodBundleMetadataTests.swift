import Foundation
import XCTest

final class InputMethodBundleMetadataTests: XCTestCase {
    private enum MetadataTestError: Error {
        case invalidPropertyList
    }

    func testDeclaresRequiredInputMethodMetadata() throws {
        let info = try loadSourceInfoDictionary()

        XCTAssertEqual(info["CFBundlePackageType"] as? String, "APPL")
        XCTAssertEqual(info["CFBundleDisplayName"] as? String, "久空輸入法")
        XCTAssertEqual(info["CFBundleIconFile"] as? String, "JiukongZhuyin.icns")
        XCTAssertEqual(info["LSUIElement"] as? Bool, true)
        XCTAssertNil(info["LSBackgroundOnly"])
        XCTAssertEqual(info["NSPrincipalClass"] as? String, "NSApplication")
        XCTAssertEqual(
            info["InputMethodConnectionName"] as? String,
            "tw_idv_jiukong_inputmethod_zhuyin_Connection"
        )
        XCTAssertEqual(
            info["InputMethodServerControllerClass"] as? String,
            "JiukongInputController"
        )
        XCTAssertEqual(
            info["TISInputSourceID"] as? String,
            "tw.idv.jiukong.inputmethod.zhuyin"
        )
        XCTAssertEqual(info["TISIntendedLanguage"] as? String, "zh-Hant")
        XCTAssertEqual(info["TISIconIsTemplate"] as? Bool, true)
        XCTAssertEqual(
            info["tsInputMethodCharacterRepertoireKey"] as? [String],
            ["Hant"]
        )
        XCTAssertEqual(
            info["tsInputMethodIconFileKey"] as? String,
            "JiukongZhuyin.tiff"
        )

        let modeContainer = try XCTUnwrap(
            info["ComponentInputModeDict"] as? [String: Any]
        )
        let modes = try XCTUnwrap(
            modeContainer["tsInputModeListKey"] as? [String: Any]
        )
        let orderedModeIDs = try XCTUnwrap(
            modeContainer["tsVisibleInputModeOrderedArrayKey"] as? [String]
        )
        let expectedModes = [
            (
                "tw.idv.jiukong.inputmethod.zhuyin.Chinese",
                "中",
                "JiukongChinese.tiff"
            ),
            (
                "tw.idv.jiukong.inputmethod.zhuyin.English",
                "英",
                "JiukongEnglish.tiff"
            )
        ]

        XCTAssertEqual(orderedModeIDs, expectedModes.map(\.0))
        for (identifier, label, iconName) in expectedModes {
            let mode = try XCTUnwrap(modes[identifier] as? [String: Any])
            let labels = try XCTUnwrap(mode["TISIconLabels"] as? [String: String])
            XCTAssertEqual(mode["TISInputSourceID"] as? String, identifier)
            XCTAssertEqual(labels["Primary"], label)
            XCTAssertEqual(mode["tsInputModeDefaultStateKey"] as? Bool, true)
            XCTAssertEqual(mode["tsInputModeIsVisibleKey"] as? Bool, true)
            XCTAssertEqual(mode["tsInputModeMenuIconFileKey"] as? String, iconName)
        }
    }

    func testDeclaredIconExists() throws {
        let resourcesDirectory = repositoryRoot.appendingPathComponent(
            "Resources",
            isDirectory: true
        )
        let info = try loadSourceInfoDictionary()
        var assetNames = [
            try XCTUnwrap(info["CFBundleIconFile"] as? String),
            try XCTUnwrap(info["tsInputMethodIconFileKey"] as? String)
        ]
        let modeContainer = try XCTUnwrap(
            info["ComponentInputModeDict"] as? [String: Any]
        )
        let modes = try XCTUnwrap(
            modeContainer["tsInputModeListKey"] as? [String: Any]
        )
        assetNames += try modes.values.map { rawMode in
            let mode = try XCTUnwrap(rawMode as? [String: Any])
            return try XCTUnwrap(mode["tsInputModeMenuIconFileKey"] as? String)
        }

        for assetName in assetNames {
            let assetURL = resourcesDirectory
                .appendingPathComponent("Assets", isDirectory: true)
                .appendingPathComponent(assetName)
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: assetURL.path),
                "Missing declared icon asset: \(assetName)"
            )
        }
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func loadSourceInfoDictionary() throws -> [String: Any] {
        let infoURL = repositoryRoot
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("Info.plist")
        let data = try Data(contentsOf: infoURL)
        let propertyList = try PropertyListSerialization.propertyList(
            from: data,
            format: nil
        )

        guard let info = propertyList as? [String: Any] else {
            throw MetadataTestError.invalidPropertyList
        }

        return info
    }
}
