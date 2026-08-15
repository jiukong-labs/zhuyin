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
