import XCTest

final class LanguageModeControllerTests: XCTestCase {
    func testToggleWithinInputMethodFlipsLanguageAndMarksItInternal() {
        let controller = LanguageModeController(initialMode: .chinese)

        XCTAssertEqual(controller.toggleWithinInputMethod(), .english)
        XCTAssertTrue(controller.isInternallyManaged)
        XCTAssertEqual(controller.toggleWithinInputMethod(), .chinese)
        XCTAssertTrue(controller.isInternallyManaged)
    }

    func testSystemSelectionOverridesAnInternalToggle() {
        let controller = LanguageModeController(initialMode: .chinese)
        controller.toggleWithinInputMethod()

        // Choosing a mode from the input menu is the user's latest choice.
        XCTAssertEqual(controller.synchronize(withSystemMode: .chinese), .chinese)
        XCTAssertFalse(controller.isInternallyManaged)
    }

    func testActivationKeepsAnInternalToggleAcrossClients() {
        let controller = LanguageModeController(initialMode: .chinese)
        controller.toggleWithinInputMethod()

        // The selected source still says Chinese; moving to another client
        // must not undo the English the user toggled to.
        XCTAssertEqual(
            controller.activate(withSystemMode: .chinese, style: .withinInputMethod),
            .english
        )
        XCTAssertEqual(controller.mode, .english)
        XCTAssertTrue(controller.isInternallyManaged)
    }

    func testActivationAdoptsTheSelectedModeUntilSomethingIsToggled() {
        // A new process starts in Chinese, but the user may have left the
        // English mode selected.
        let controller = LanguageModeController(initialMode: .chinese)

        XCTAssertEqual(
            controller.activate(withSystemMode: .english, style: .withinInputMethod),
            .english
        )
        XCTAssertFalse(controller.isInternallyManaged)
    }

    func testOnlyTheSelectedChineseModeTogglesWithinInputMethod() {
        XCTAssertTrue(
            ShiftSwitchStyle.withinInputMethod
                .togglesWithinInputMethod(selectedMode: .chinese)
        )
        // English is also what macOS selects for a password field; Shift
        // there must ask macOS for Chinese rather than compose into it.
        XCTAssertFalse(
            ShiftSwitchStyle.withinInputMethod
                .togglesWithinInputMethod(selectedMode: .english)
        )
        for mode in LanguageMode.allCases {
            XCTAssertFalse(
                ShiftSwitchStyle.inputSource
                    .togglesWithinInputMethod(selectedMode: mode)
            )
        }
    }

    func testInputSourceStyleActivationAlwaysFollowsTheSelectedMode() {
        let controller = LanguageModeController(initialMode: .chinese)
        controller.toggleWithinInputMethod()

        XCTAssertEqual(
            controller.activate(withSystemMode: .chinese, style: .inputSource),
            .chinese
        )
        XCTAssertFalse(controller.isInternallyManaged)
    }
}
