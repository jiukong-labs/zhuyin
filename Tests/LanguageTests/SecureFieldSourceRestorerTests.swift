import XCTest

final class SecureFieldSourceRestorerTests: XCTestCase {
    private let abc = "com.apple.keylayout.ABC"
    private let delay = SecureFieldSourceRestorer.restoreDelay

    private func displacedByPasswordField(
        from mode: LanguageMode = .chinese
    ) -> SecureFieldSourceRestorer {
        var restorer = SecureFieldSourceRestorer(selectedMode: mode)
        restorer.noteJiukongInUse(secureInputEnabled: false)
        XCTAssertEqual(
            restorer.sourceChanged(to: nil, sourceID: abc, secureInputEnabled: true, at: 100),
            .none
        )
        XCTAssertTrue(restorer.isWaiting)
        return restorer
    }

    func testPasswordFieldLeftForAnotherAppRestoresJiukong() {
        // Chrome's password field switched to ABC; Outlook then kept ABC.
        var restorer = displacedByPasswordField()

        XCTAssertEqual(restorer.poll(secureInputEnabled: true, currentSourceID: abc, at: 110), .none)
        XCTAssertEqual(restorer.poll(secureInputEnabled: false, currentSourceID: abc, at: 124), .none)
        XCTAssertEqual(
            restorer.poll(secureInputEnabled: false, currentSourceID: abc, at: 124 + delay - 0.01),
            .none
        )
        XCTAssertEqual(
            restorer.poll(secureInputEnabled: false, currentSourceID: abc, at: 124 + delay + 0.01),
            .restore(.chinese)
        )
        XCTAssertFalse(restorer.isWaiting)
    }

    func testRestoresTheJiukongModeThatWasSelected() {
        var restorer = displacedByPasswordField(from: .english)

        _ = restorer.poll(secureInputEnabled: false, currentSourceID: abc, at: 101)
        XCTAssertEqual(
            restorer.poll(secureInputEnabled: false, currentSourceID: abc, at: 101 + delay + 0.01),
            .restore(.english)
        )
    }

    func testMacOSRestoringTheSourceItselfEndsTheWait() {
        var restorer = displacedByPasswordField()

        _ = restorer.poll(secureInputEnabled: false, currentSourceID: abc, at: 105)
        XCTAssertEqual(
            restorer.sourceChanged(
                to: .chinese,
                sourceID: "jiukong.Chinese",
                secureInputEnabled: false,
                at: 105.1
            ),
            .superseded
        )
        XCTAssertFalse(restorer.isWaiting)
    }

    func testMovingBetweenPasswordFieldsDoesNotRestoreInBetween() {
        var restorer = displacedByPasswordField()

        _ = restorer.poll(secureInputEnabled: false, currentSourceID: abc, at: 105)
        XCTAssertEqual(restorer.poll(secureInputEnabled: true, currentSourceID: abc, at: 105.1), .none)
        XCTAssertEqual(
            restorer.poll(secureInputEnabled: false, currentSourceID: abc, at: 105.2),
            .none
        )
        XCTAssertEqual(
            restorer.poll(secureInputEnabled: false, currentSourceID: abc, at: 105.2 + delay + 0.01),
            .restore(.chinese)
        )
    }

    func testRepeatedNotificationForTheSameSourceKeepsWaiting() {
        var restorer = displacedByPasswordField()

        XCTAssertEqual(
            restorer.sourceChanged(to: nil, sourceID: abc, secureInputEnabled: true, at: 100.1),
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
                secureInputEnabled: false,
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
                secureInputEnabled: false,
                currentSourceID: "com.apple.keylayout.US",
                at: 102
            ),
            .superseded
        )
    }

    func testUserSwitchingToABCOutsideAPasswordFieldIsLeftAlone() {
        var restorer = SecureFieldSourceRestorer(selectedMode: .chinese)
        restorer.noteJiukongInUse(secureInputEnabled: false)
        _ = restorer.sourceChanged(to: nil, sourceID: abc, secureInputEnabled: false, at: 100)

        let window = SecureFieldSourceRestorer.confirmationWindow
        XCTAssertEqual(
            restorer.poll(secureInputEnabled: false, currentSourceID: abc, at: 100 + window),
            .none
        )
        XCTAssertEqual(
            restorer.poll(secureInputEnabled: false, currentSourceID: abc, at: 100 + window + 0.1),
            .dismissed
        )

        // A password field entered later does not turn the choice into one.
        XCTAssertEqual(restorer.poll(secureInputEnabled: true, currentSourceID: abc, at: 110), .none)
        XCTAssertEqual(restorer.poll(secureInputEnabled: false, currentSourceID: abc, at: 120), .none)
        XCTAssertFalse(restorer.isWaiting)
    }

    func testSecureInputStartingJustAfterTheSwitchCounts() {
        var restorer = SecureFieldSourceRestorer(selectedMode: .chinese)
        restorer.noteJiukongInUse(secureInputEnabled: false)
        _ = restorer.sourceChanged(to: nil, sourceID: abc, secureInputEnabled: false, at: 100)

        XCTAssertEqual(restorer.poll(secureInputEnabled: true, currentSourceID: abc, at: 100.2), .none)
        _ = restorer.poll(secureInputEnabled: false, currentSourceID: abc, at: 108)
        XCTAssertEqual(
            restorer.poll(secureInputEnabled: false, currentSourceID: abc, at: 108 + delay + 0.01),
            .restore(.chinese)
        )
    }

    func testSwitchUnderSecureKeyboardEntryIsTheUsers() {
        // Terminal's Secure Keyboard Entry keeps secure input on while typing
        // with Jiukong, so a switch to ABC there is a deliberate choice.
        var restorer = SecureFieldSourceRestorer(selectedMode: .chinese)
        restorer.noteJiukongInUse(secureInputEnabled: true)

        _ = restorer.sourceChanged(to: nil, sourceID: abc, secureInputEnabled: true, at: 100)
        XCTAssertFalse(restorer.isWaiting)
    }

    func testSwitchFromAnotherSourceIsNotWatched() {
        var restorer = SecureFieldSourceRestorer(selectedMode: nil)
        restorer.noteJiukongInUse(secureInputEnabled: false)

        _ = restorer.sourceChanged(to: nil, sourceID: abc, secureInputEnabled: true, at: 100)
        XCTAssertFalse(restorer.isWaiting)
    }

    func testSecureInputLeftOnTooLongGivesUp() {
        var restorer = displacedByPasswordField()
        let limit = SecureFieldSourceRestorer.maximumWait

        XCTAssertEqual(restorer.poll(secureInputEnabled: true, currentSourceID: abc, at: 100 + limit), .none)
        XCTAssertEqual(
            restorer.poll(secureInputEnabled: true, currentSourceID: abc, at: 100 + limit + 0.1),
            .gaveUp
        )
        XCTAssertFalse(restorer.isWaiting)
    }
}
