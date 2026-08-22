import AppKit
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
        XCTAssertEqual(info["TISIconIsTemplate"] as? Bool, false)
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
        let serverModeContainer = try XCTUnwrap(
            info["InputMethodServerModeDictionary"] as? [String: Any]
        )
        XCTAssertEqual(
            serverModeContainer as NSDictionary,
            modeContainer as NSDictionary
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
                "JiukongChineseColor.tiff"
            ),
            (
                "tw.idv.jiukong.inputmethod.zhuyin.English",
                "A",
                "JiukongEnglishAColor.tiff"
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

    func testModeIconsContainMenuBarScaleRepresentations() throws {
        for assetName in [
            "JiukongChineseColor.tiff",
            "JiukongEnglishAColor.tiff",
        ] {
            let assetURL = repositoryRoot
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent("Assets", isDirectory: true)
                .appendingPathComponent(assetName)
            let data = try Data(contentsOf: assetURL)
            let representations = NSBitmapImageRep.imageReps(with: data)
            let pixelSizes = representations.map {
                NSSize(width: $0.pixelsWide, height: $0.pixelsHigh)
            }.sorted {
                $0.width < $1.width
            }

            XCTAssertEqual(
                pixelSizes,
                [
                    NSSize(width: 16, height: 16),
                    NSSize(width: 32, height: 32),
                ],
                assetName
            )
            XCTAssertEqual(
                representations.map(\.size),
                [
                    NSSize(width: 16, height: 16),
                    NSSize(width: 16, height: 16),
                ],
                assetName
            )
        }
    }

    func testModeIconColorsMatchCursorIndicatorDefaults() throws {
        let cases: [(String, LanguageMode)] = [
            ("JiukongChineseColor.tiff", .chinese),
            ("JiukongEnglishAColor.tiff", .english),
        ]

        for (assetName, mode) in cases {
            let assetURL = repositoryRoot
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent("Assets", isDirectory: true)
                .appendingPathComponent(assetName)
            let data = try Data(contentsOf: assetURL)
            let representation = try XCTUnwrap(
                NSBitmapImageRep.imageReps(with: data).first
                    as? NSBitmapImageRep
            )
            let actual = try XCTUnwrap(mostOpaqueColor(in: representation))
                .usingColorSpace(.sRGB)
            let expected = try XCTUnwrap(
                CursorIndicatorAppearance.defaultColor(for: mode)
                    .usingColorSpace(.sRGB)
            )

            XCTAssertEqual(
                try XCTUnwrap(actual).redComponent,
                expected.redComponent,
                accuracy: 0.02,
                assetName
            )
            XCTAssertEqual(
                try XCTUnwrap(actual).greenComponent,
                expected.greenComponent,
                accuracy: 0.02,
                assetName
            )
            XCTAssertEqual(
                try XCTUnwrap(actual).blueComponent,
                expected.blueComponent,
                accuracy: 0.02,
                assetName
            )
        }
    }

    private func mostOpaqueColor(
        in representation: NSBitmapImageRep
    ) -> NSColor? {
        var result: NSColor?
        var highestAlpha: CGFloat = 0
        for y in 0 ..< representation.pixelsHigh {
            for x in 0 ..< representation.pixelsWide {
                guard let color = representation.colorAt(x: x, y: y),
                      color.alphaComponent > highestAlpha else {
                    continue
                }
                result = color
                highestAlpha = color.alphaComponent
            }
        }
        return result
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
