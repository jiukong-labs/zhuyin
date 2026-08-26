import Foundation
import XCTest

final class PreferencesStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "tw.idv.jiukong.tests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testFreshDomainLoadsDefaults() {
        let store = UserDefaultsPreferencesStore(defaults: defaults)

        XCTAssertEqual(store.load(), .default)
    }

    func testSavedPreferencesSurviveANewStore() {
        let saved = Preferences(
            shiftKeyPreference: .right,
            automaticLearningEnabled: false,
            iCloudSyncEnabled: false,
            showsRareCandidates: true
        )
        UserDefaultsPreferencesStore(defaults: defaults).save(saved)

        XCTAssertEqual(
            UserDefaultsPreferencesStore(defaults: defaults).load(),
            saved
        )
        XCTAssertEqual(
            defaults.integer(forKey: PreferenceKey.version.rawValue),
            Preferences.currentVersion
        )
        XCTAssertTrue(
            defaults.bool(forKey: PreferenceKey.showsRareCandidates.rawValue)
        )
        XCTAssertFalse(
            defaults.bool(forKey: PreferenceKey.iCloudSyncEnabled.rawValue)
        )
    }

    func testSavingDoesNotDisturbUnrelatedKeysInTheSameDomain() {
        defaults.set("kept", forKey: "UnrelatedProcessKey")

        UserDefaultsPreferencesStore(defaults: defaults).save(
            Preferences(shiftKeyPreference: .left)
        )

        XCTAssertEqual(defaults.string(forKey: "UnrelatedProcessKey"), "kept")
    }

    func testUnrelatedKeysCannotBeMistakenForSettings() {
        defaults.set("left", forKey: "ShiftLanguageToggle")

        XCTAssertEqual(
            UserDefaultsPreferencesStore(defaults: defaults).load()
                .shiftKeyPreference,
            .both
        )
    }

    func testManuallyWrittenDefaultsAreHonored() {
        defaults.set("left", forKey: PreferenceKey.shiftLanguageToggle.rawValue)
        defaults.set(
            false,
            forKey: PreferenceKey.automaticLearningEnabled.rawValue
        )

        let loaded = UserDefaultsPreferencesStore(defaults: defaults).load()

        XCTAssertEqual(loaded.shiftKeyPreference, .left)
        XCTAssertFalse(loaded.automaticLearningEnabled)
    }
}
