import XCTest

final class SecureFieldSourceRestorerTests: XCTestCase {
    private typealias SecureInput = SecureFieldSourceRestorer.SecureInput

    private let abc = "com.apple.keylayout.ABC"
    private let delay = SecureFieldSourceRestorer.restoreDelay

    private let chrome: pid_t = 101
    private let vscode: pid_t = 202
    private let terminal: pid_t = 303
    private let loginwindow: pid_t = 404

    private let off = SecureInput.off

    private func held(by holder: pid_t?, front: pid_t?) -> SecureInput {
        SecureInput(enabled: true, holderPID: holder, frontmostPID: front)
    }

    private var chromeField: SecureInput {
        held(by: chrome, front: chrome)
    }

    private func displacedByPasswordField(
        from mode: LanguageMode = .chinese
    ) -> SecureFieldSourceRestorer {
        var restorer = SecureFieldSourceRestorer(selectedMode: mode)
        restorer.noteJiukongTyping(off)
        XCTAssertEqual(
            restorer.sourceChanged(to: nil, sourceID: abc, secureInput: chromeField, at: 100),
            .none
        )
        XCTAssertTrue(restorer.isWaiting)
        return restorer
    }

    func testPasswordFieldEndingRestoresJiukong() {
        var restorer = displacedByPasswordField()

        XCTAssertEqual(restorer.poll(secureInput: chromeField, currentSourceID: abc, at: 110), .none)
        XCTAssertEqual(restorer.poll(secureInput: off, currentSourceID: abc, at: 124), .none)
        XCTAssertEqual(
            restorer.poll(secureInput: off, currentSourceID: abc, at: 124 + delay - 0.01),
            .none
        )
        XCTAssertEqual(
            restorer.poll(secureInput: off, currentSourceID: abc, at: 124 + delay + 0.01),
            .restore(.chinese)
        )
        XCTAssertFalse(restorer.isWaiting)
    }

    func testLeavingThePasswordFieldsAppRestoresWhileItKeepsSecureInput() {
        // Chrome kept secure input on after the user moved to VS Code, which
        // then stayed on ABC until the user chose Jiukong again.
        var restorer = displacedByPasswordField()
        let inVSCode = held(by: chrome, front: vscode)

        XCTAssertEqual(restorer.poll(secureInput: chromeField, currentSourceID: abc, at: 105), .none)
        XCTAssertEqual(restorer.poll(secureInput: inVSCode, currentSourceID: abc, at: 106), .none)
        XCTAssertEqual(
            restorer.poll(secureInput: inVSCode, currentSourceID: abc, at: 106 + delay - 0.01),
            .none
        )
        XCTAssertEqual(
            restorer.poll(secureInput: inVSCode, currentSourceID: abc, at: 106 + delay + 0.01),
            .restore(.chinese)
        )
    }

    func testReturningToThePasswordFieldsAppBeforeTheDelayKeepsWaiting() {
        var restorer = displacedByPasswordField()

        _ = restorer.poll(secureInput: held(by: chrome, front: vscode), currentSourceID: abc, at: 106)
        XCTAssertEqual(restorer.poll(secureInput: chromeField, currentSourceID: abc, at: 106.1), .none)
        XCTAssertEqual(
            restorer.poll(secureInput: chromeField, currentSourceID: abc, at: 106.1 + delay + 0.01),
            .none
        )
        XCTAssertTrue(restorer.isWaiting)
    }

    func testFieldAppIsTakenOnceTheFrontAppCatchesUp() {
        // Clicking from VS Code straight into a focused Chrome password field
        // can switch the source before the workspace reports Chrome in front.
        var restorer = SecureFieldSourceRestorer(selectedMode: .chinese)
        restorer.noteJiukongTyping(off)
        _ = restorer.sourceChanged(
            to: nil,
            sourceID: abc,
            secureInput: held(by: chrome, front: vscode),
            at: 100
        )

        XCTAssertEqual(
            restorer.poll(secureInput: held(by: chrome, front: vscode), currentSourceID: abc, at: 100 + delay + 0.01),
            .none
        )
        XCTAssertEqual(restorer.poll(secureInput: chromeField, currentSourceID: abc, at: 100.5), .none)
        _ = restorer.poll(secureInput: held(by: chrome, front: vscode), currentSourceID: abc, at: 110)
        XCTAssertEqual(
            restorer.poll(secureInput: held(by: chrome, front: vscode), currentSourceID: abc, at: 110 + delay + 0.01),
            .restore(.chinese)
        )
    }

    func testLockedScreenWaitsForSecureInputToEnd() {
        var restorer = SecureFieldSourceRestorer(selectedMode: .chinese)
        restorer.noteJiukongTyping(off)
        let locked = held(by: loginwindow, front: vscode)
        _ = restorer.sourceChanged(to: nil, sourceID: abc, secureInput: locked, at: 100)

        XCTAssertEqual(restorer.poll(secureInput: locked, currentSourceID: abc, at: 400), .none)
        _ = restorer.poll(secureInput: off, currentSourceID: abc, at: 500)
        XCTAssertEqual(
            restorer.poll(secureInput: off, currentSourceID: abc, at: 500 + delay + 0.01),
            .restore(.chinese)
        )
    }

    func testLockingTheScreenOverThePasswordFieldKeepsWaiting() {
        var restorer = displacedByPasswordField()

        _ = restorer.poll(secureInput: held(by: loginwindow, front: loginwindow), currentSourceID: abc, at: 110)
        XCTAssertEqual(
            restorer.poll(
                secureInput: held(by: loginwindow, front: loginwindow),
                currentSourceID: abc,
                at: 110 + delay + 0.01
            ),
            .none
        )
        XCTAssertTrue(restorer.isWaiting)
    }

    func testUnknownHolderWaitsForSecureInputToEnd() {
        var restorer = SecureFieldSourceRestorer(selectedMode: .chinese)
        restorer.noteJiukongTyping(off)
        _ = restorer.sourceChanged(
            to: nil,
            sourceID: abc,
            secureInput: held(by: nil, front: chrome),
            at: 100
        )

        XCTAssertEqual(
            restorer.poll(secureInput: held(by: nil, front: vscode), currentSourceID: abc, at: 200),
            .none
        )
        XCTAssertTrue(restorer.isWaiting)
    }

    func testRestoresTheJiukongModeThatWasSelected() {
        var restorer = displacedByPasswordField(from: .english)

        _ = restorer.poll(secureInput: off, currentSourceID: abc, at: 101)
        XCTAssertEqual(
            restorer.poll(secureInput: off, currentSourceID: abc, at: 101 + delay + 0.01),
            .restore(.english)
        )
    }

    func testMacOSRestoringTheSourceItselfEndsTheWait() {
        var restorer = displacedByPasswordField()

        _ = restorer.poll(secureInput: off, currentSourceID: abc, at: 105)
        XCTAssertEqual(
            restorer.sourceChanged(
                to: .chinese,
                sourceID: "jiukong.Chinese",
                secureInput: off,
                at: 105.1
            ),
            .superseded
        )
        XCTAssertFalse(restorer.isWaiting)
    }

    func testMovingBetweenPasswordFieldsDoesNotRestoreInBetween() {
        var restorer = displacedByPasswordField()

        _ = restorer.poll(secureInput: off, currentSourceID: abc, at: 105)
        XCTAssertEqual(restorer.poll(secureInput: chromeField, currentSourceID: abc, at: 105.1), .none)
        XCTAssertEqual(
            restorer.poll(secureInput: off, currentSourceID: abc, at: 105.2),
            .none
        )
        XCTAssertEqual(
            restorer.poll(secureInput: off, currentSourceID: abc, at: 105.2 + delay + 0.01),
            .restore(.chinese)
        )
    }

    func testRepeatedNotificationForTheSameSourceKeepsWaiting() {
        var restorer = displacedByPasswordField()

        XCTAssertEqual(
            restorer.sourceChanged(to: nil, sourceID: abc, secureInput: chromeField, at: 100.1),
            .none
        )
        XCTAssertTrue(restorer.isWaiting)
    }

    func testChoosingAnotherSourceWhileWaitingIsLeftAlone() {
        var restorer = displacedByPasswordField()

        XCTAssertEqual(
            restorer.sourceChanged(
                to: nil,
                sourceID: "com.apple.keylayout.US",
                secureInput: off,
                at: 102
            ),
            .superseded
        )
        XCTAssertFalse(restorer.isWaiting)
    }

    func testSourceChangedWithoutNotificationIsLeftAlone() {
        var restorer = displacedByPasswordField()

        XCTAssertEqual(
            restorer.poll(
                secureInput: off,
                currentSourceID: "com.apple.keylayout.US",
                at: 102
            ),
            .superseded
        )
    }

    func testUserSwitchingToABCOutsideAPasswordFieldIsLeftAlone() {
        var restorer = SecureFieldSourceRestorer(selectedMode: .chinese)
        restorer.noteJiukongTyping(off)
        _ = restorer.sourceChanged(to: nil, sourceID: abc, secureInput: off, at: 100)

        let window = SecureFieldSourceRestorer.confirmationWindow
        XCTAssertEqual(
            restorer.poll(secureInput: off, currentSourceID: abc, at: 100 + window),
            .none
        )
        XCTAssertEqual(
            restorer.poll(secureInput: off, currentSourceID: abc, at: 100 + window + 0.1),
            .dismissed
        )

        // A password field entered later does not turn the choice into one.
        XCTAssertEqual(restorer.poll(secureInput: chromeField, currentSourceID: abc, at: 110), .none)
        XCTAssertEqual(restorer.poll(secureInput: off, currentSourceID: abc, at: 120), .none)
        XCTAssertFalse(restorer.isWaiting)
    }

    func testSecureInputStartingJustAfterTheSwitchCounts() {
        var restorer = SecureFieldSourceRestorer(selectedMode: .chinese)
        restorer.noteJiukongTyping(off)
        _ = restorer.sourceChanged(to: nil, sourceID: abc, secureInput: off, at: 100)

        XCTAssertEqual(restorer.poll(secureInput: chromeField, currentSourceID: abc, at: 100.2), .none)
        _ = restorer.poll(secureInput: off, currentSourceID: abc, at: 108)
        XCTAssertEqual(
            restorer.poll(secureInput: off, currentSourceID: abc, at: 108 + delay + 0.01),
            .restore(.chinese)
        )
    }

    func testSwitchUnderSecureKeyboardEntryIsTheUsers() {
        // Terminal's Secure Keyboard Entry keeps secure input on while typing
        // with Jiukong, so a switch to ABC there is a deliberate choice.
        var restorer = SecureFieldSourceRestorer(selectedMode: .chinese)
        let secureKeyboardEntry = held(by: terminal, front: terminal)
        restorer.noteJiukongTyping(secureKeyboardEntry)
        restorer.noteJiukongActivated(secureKeyboardEntry)

        XCTAssertEqual(
            restorer.sourceChanged(to: nil, sourceID: abc, secureInput: secureKeyboardEntry, at: 100),
            .notWatched
        )
        XCTAssertFalse(restorer.isWaiting)
    }

    func testSecureInputOfUnknownOriginWhileTypingIsTheUsers() {
        var restorer = SecureFieldSourceRestorer(selectedMode: .chinese)
        restorer.noteJiukongTyping(held(by: nil, front: nil))

        XCTAssertEqual(
            restorer.sourceChanged(to: nil, sourceID: abc, secureInput: held(by: nil, front: nil), at: 100),
            .notWatched
        )
    }

    func testPasswordFieldThatActivatesJiukongIsStillWatched() {
        // A Chrome page whose password field already had focus activated
        // Jiukong with secure input already on, just before macOS selected
        // ABC, and Jiukong then took the switch for the user's.
        for front in [chrome, vscode] {
            var restorer = SecureFieldSourceRestorer(selectedMode: .chinese)
            restorer.noteJiukongTyping(off)
            restorer.noteJiukongActivated(held(by: chrome, front: front))

            XCTAssertEqual(
                restorer.sourceChanged(
                    to: nil,
                    sourceID: abc,
                    secureInput: held(by: chrome, front: front),
                    at: 100
                ),
                .none
            )
            XCTAssertTrue(restorer.isWaiting)
        }
    }

    func testTypingWhileAnotherAppHoldsSecureInputStillWatchesTheNextPasswordField() {
        // After a restore in VS Code while Chrome still held secure input,
        // returning to Chrome's password field must be watched again.
        var restorer = SecureFieldSourceRestorer(selectedMode: .chinese)
        restorer.noteJiukongTyping(held(by: chrome, front: vscode))

        _ = restorer.sourceChanged(to: nil, sourceID: abc, secureInput: chromeField, at: 100)
        XCTAssertTrue(restorer.isWaiting)
    }

    func testActivationWithoutSecureInputInFrontClearsTheTypingSample() {
        var restorer = SecureFieldSourceRestorer(selectedMode: .chinese)
        restorer.noteJiukongTyping(held(by: terminal, front: terminal))
        restorer.noteJiukongActivated(off)

        _ = restorer.sourceChanged(to: nil, sourceID: abc, secureInput: chromeField, at: 100)
        XCTAssertTrue(restorer.isWaiting)
    }

    func testSwitchFromAnotherSourceIsNotWatched() {
        var restorer = SecureFieldSourceRestorer(selectedMode: nil)
        restorer.noteJiukongTyping(off)

        _ = restorer.sourceChanged(to: nil, sourceID: abc, secureInput: chromeField, at: 100)
        XCTAssertFalse(restorer.isWaiting)
    }

    func testSecureInputLeftOnTooLongGivesUp() {
        var restorer = displacedByPasswordField()
        let limit = SecureFieldSourceRestorer.maximumWait

        XCTAssertEqual(restorer.poll(secureInput: chromeField, currentSourceID: abc, at: 100 + limit), .none)
        XCTAssertEqual(
            restorer.poll(secureInput: chromeField, currentSourceID: abc, at: 100 + limit + 0.1),
            .gaveUp
        )
        XCTAssertFalse(restorer.isWaiting)
    }
}
