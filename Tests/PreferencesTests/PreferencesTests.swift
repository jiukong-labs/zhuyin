import AppKit
import Carbon
import Foundation
import XCTest

final class PreferencesTests: XCTestCase {
    func testEmptyStorageUsesShippedDefaults() {
        let preferences = Preferences.decoded(from: [:])

        XCTAssertEqual(preferences, .default)
        XCTAssertEqual(preferences.shiftKeyPreference, .both)
        XCTAssertTrue(preferences.automaticLearningEnabled)
        XCTAssertFalse(preferences.cloudSyncEnabled)
        XCTAssertFalse(preferences.showsRareCandidates)
    }

    func testCloudSyncPreferenceRoundTripsAndDefaultsOff() {
        let stored = Preferences(cloudSyncEnabled: true).encoded()

        XCTAssertTrue(Preferences.decoded(from: stored).cloudSyncEnabled)
        XCTAssertFalse(
            Preferences.decoded(
                from: [PreferenceKey.cloudSyncEnabled.rawValue: "invalid"]
            ).cloudSyncEnabled
        )
    }

    func testVersionTwoCloudPreferenceRequiresFreshConsent() {
        let decoded = Preferences.decoded(
            from: [
                PreferenceKey.version.rawValue: 2,
                PreferenceKey.cloudSyncEnabled.rawValue: true,
            ]
        )

        XCTAssertFalse(decoded.cloudSyncEnabled)
    }

    func testRareCandidatePreferenceRoundTripsAndDefaultsOff() {
        let stored = Preferences(showsRareCandidates: true).encoded()

        XCTAssertTrue(Preferences.decoded(from: stored).showsRareCandidates)
        XCTAssertFalse(
            Preferences.decoded(
                from: [PreferenceKey.showsRareCandidates.rawValue: "invalid"]
            ).showsRareCandidates
        )
    }

    func testEveryShiftPreferenceRoundTrips() {
        for preference in ShiftKeyPreference.allCases {
            let stored = Preferences(
                shiftKeyPreference: preference,
                automaticLearningEnabled: false
            ).encoded()

            XCTAssertEqual(
                Preferences.decoded(from: stored),
                Preferences(
                    shiftKeyPreference: preference,
                    automaticLearningEnabled: false
                )
            )
        }
    }

    func testEveryKeyboardArrangementRoundTrips() {
        for arrangement in ZhuyinKeyboardArrangement.allCases {
            let stored = Preferences(keyboardArrangement: arrangement).encoded()

            XCTAssertEqual(
                Preferences.decoded(from: stored).keyboardArrangement,
                arrangement
            )
        }
    }

    func testUnknownKeyboardArrangementFallsBackToStandard() {
        let preferences = Preferences.decoded(
            from: [
                PreferenceKey.version.rawValue: 1,
                PreferenceKey.keyboardArrangement.rawValue: "dvorak",
                PreferenceKey.automaticLearningEnabled.rawValue: false,
            ]
        )

        XCTAssertEqual(preferences.keyboardArrangement, .standard)
        XCTAssertFalse(preferences.automaticLearningEnabled)
    }

    func testCursorIndicatorIsOffByDefault() {
        let indicator = Preferences.default.cursorIndicator

        XCTAssertFalse(indicator.isEnabled)
        XCTAssertEqual(indicator.placement, .lowerRight)
        XCTAssertEqual(indicator.tracking, .fixedDistance)
        XCTAssertEqual(indicator.textSize, .small)
        XCTAssertTrue(indicator.showsCapsLockIndicator)
        XCTAssertEqual(indicator.appearance, CursorIndicatorAppearance())
    }

    func testCursorIndicatorSettingsRoundTrip() {
        let stored = Preferences(
            cursorIndicator: CursorIndicatorPreferences(
                isEnabled: true,
                placement: .upperRight,
                tracking: .followCursor,
                textSize: .huge,
                showsCapsLockIndicator: false,
                capsLockIndicatorSize: .small,
                appearance: CursorIndicatorAppearance(
                    chineseText: "漢",
                    englishText: "EN",
                    chineseColorHex: "#112233",
                    englishColorHex: "#445566"
                )
            )
        ).encoded()

        let decoded = Preferences.decoded(from: stored).cursorIndicator

        XCTAssertTrue(decoded.isEnabled)
        XCTAssertEqual(decoded.placement, .upperRight)
        XCTAssertEqual(decoded.tracking, .followCursor)
        XCTAssertEqual(decoded.textSize, .huge)
        XCTAssertFalse(decoded.showsCapsLockIndicator)
        XCTAssertEqual(decoded.capsLockIndicatorSize, .small)
        XCTAssertEqual(decoded.appearance.chineseText, "漢")
        XCTAssertEqual(decoded.appearance.englishText, "EN")
        XCTAssertEqual(decoded.appearance.chineseColorHex, "#112233")
        XCTAssertEqual(decoded.appearance.englishColorHex, "#445566")
    }

    func testClearedOverridesDecodeAsNoOverride() {
        let stored = Preferences(
            cursorIndicator: CursorIndicatorPreferences(
                appearance: CursorIndicatorAppearance()
            )
        ).encoded()

        let decoded = Preferences.decoded(from: stored).cursorIndicator

        XCTAssertNil(decoded.appearance.chineseText)
        XCTAssertNil(decoded.appearance.englishColorHex)
        XCTAssertEqual(decoded.appearance.text(for: .chinese), "中")
    }

    func testUnknownCursorIndicatorValuesFallBackPerField() {
        let preferences = Preferences.decoded(
            from: [
                PreferenceKey.version.rawValue: 1,
                PreferenceKey.cursorIndicatorEnabled.rawValue: true,
                PreferenceKey.cursorIndicatorPlacement.rawValue: "sideways",
                PreferenceKey.cursorIndicatorTracking.rawValue: 7,
                PreferenceKey.cursorIndicatorTextSize.rawValue: "gigantic",
                PreferenceKey.cursorIndicatorCapsLockSize.rawValue: "tiny",
                PreferenceKey.cursorIndicatorChineseColor.rawValue: "not-a-color",
            ]
        )

        XCTAssertTrue(preferences.cursorIndicator.isEnabled)
        XCTAssertEqual(preferences.cursorIndicator.placement, .lowerRight)
        XCTAssertEqual(preferences.cursorIndicator.tracking, .fixedDistance)
        XCTAssertEqual(preferences.cursorIndicator.textSize, .small)
        XCTAssertEqual(preferences.cursorIndicator.capsLockIndicatorSize, .extraLarge)
        XCTAssertNil(preferences.cursorIndicator.appearance.chineseColorHex)
    }

    func testEncodingStampsTheCurrentVersion() {
        let stored = Preferences.default.encoded()

        XCTAssertEqual(
            stored[PreferenceKey.version.rawValue] as? Int,
            Preferences.currentVersion
        )
    }

    func testUnknownOrMalformedValuesFallBackPerField() {
        let preferences = Preferences.decoded(
            from: [
                PreferenceKey.version.rawValue: 1,
                PreferenceKey.shiftLanguageToggle.rawValue: "sideways",
                PreferenceKey.automaticLearningEnabled.rawValue: "maybe",
            ]
        )

        XCTAssertEqual(preferences, .default)
    }

    func testWrongValueTypeDoesNotOverrideTheOtherSetting() {
        let preferences = Preferences.decoded(
            from: [
                PreferenceKey.version.rawValue: 1,
                PreferenceKey.shiftLanguageToggle.rawValue: 7,
                PreferenceKey.automaticLearningEnabled.rawValue: false,
            ]
        )

        XCTAssertEqual(preferences.shiftKeyPreference, .both)
        XCTAssertFalse(preferences.automaticLearningEnabled)
    }

    func testBooleanAcceptsPropertyListAndCommandLineSpellings() {
        let values: [(Any, Bool)] = [
            (false, false),
            (NSNumber(value: 0), false),
            (NSNumber(value: 1), true),
            ("NO", false),
            ("yes", true),
            ("0", false),
        ]

        for (stored, expected) in values {
            let preferences = Preferences.decoded(
                from: [PreferenceKey.automaticLearningEnabled.rawValue: stored]
            )
            XCTAssertEqual(
                preferences.automaticLearningEnabled,
                expected,
                "stored value \(stored)"
            )
        }
    }

    func testMissingVersionStillReadsKnownFields() {
        let preferences = Preferences.decoded(
            from: [
                PreferenceKey.shiftLanguageToggle.rawValue: "right",
                PreferenceKey.automaticLearningEnabled.rawValue: false,
            ]
        )

        XCTAssertEqual(preferences.shiftKeyPreference, .right)
        XCTAssertFalse(preferences.automaticLearningEnabled)
    }

    func testFutureOrInvalidVersionIsNotGuessed() {
        for version in [0, -1, Preferences.currentVersion + 1] {
            let preferences = Preferences.decoded(
                from: [
                    PreferenceKey.version.rawValue: version,
                    PreferenceKey.shiftLanguageToggle.rawValue: "disabled",
                    PreferenceKey.automaticLearningEnabled.rawValue: false,
                ]
            )

            XCTAssertEqual(preferences, .default, "version \(version)")
        }
    }

    func testDisabledPreferenceStopsBothShiftKeys() {
        var controller = ShiftToggleController()
        let preference = Preferences.decoded(
            from: [
                PreferenceKey.version.rawValue: 1,
                PreferenceKey.shiftLanguageToggle.rawValue: "disabled",
            ]
        ).shiftKeyPreference

        XCTAssertFalse(
            controller.handleFlagsChanged(
                keyCode: UInt16(kVK_Shift),
                modifierFlags: [.shift],
                preference: preference
            )
        )
        XCTAssertFalse(
            controller.handleFlagsChanged(
                keyCode: UInt16(kVK_Shift),
                modifierFlags: [],
                preference: preference
            )
        )
    }
}
