import XCTest

final class BopomofoInputSessionTests: XCTestCase {
    func testStandardKeysProduceWuOThirdTone() {
        var session = BopomofoInputSession()

        XCTAssertEqual(
            session.handle(.letterJ),
            handled(.updateMarkedText("ㄨ"))
        )
        XCTAssertEqual(
            session.handle(.letterI),
            handled(.updateMarkedText("ㄨㄛ"))
        )
        XCTAssertEqual(
            session.handle(.digit3),
            handled(.commitText("ㄨㄛˇ"))
        )
        XCTAssertFalse(session.hasComposition)
    }

    func testStandardKeysProduceJianFourthTone() {
        var session = BopomofoInputSession()

        _ = session.handle(.letterR)
        _ = session.handle(.letterU)
        _ = session.handle(.digit0)

        XCTAssertEqual(
            session.handle(.digit4),
            handled(.commitText("ㄐㄧㄢˋ"))
        )
    }

    func testSpaceCompletesAnActiveFirstToneSyllable() {
        var session = BopomofoInputSession()
        _ = session.handle(.digit1)

        XCTAssertEqual(
            session.handle(.space),
            handled(.commitText("ㄅ"))
        )
    }

    func testNeutralToneIsCommittedBeforeTheSyllableBody() {
        var session = BopomofoInputSession()
        _ = session.handle(.digit2)
        _ = session.handle(.letterK)

        XCTAssertEqual(
            session.handle(.digit7),
            handled(.commitText("˙ㄉㄜ"))
        )
    }

    func testBackspaceRemovesOneComponentAndClearsTheLast() {
        var session = BopomofoInputSession()
        _ = session.handle(.letterR)
        _ = session.handle(.letterU)
        _ = session.handle(.digit0)

        XCTAssertEqual(
            session.handle(.deleteBackward),
            handled(.updateMarkedText("ㄐㄧ"))
        )
        XCTAssertEqual(
            session.handle(.deleteBackward),
            handled(.updateMarkedText("ㄐ"))
        )
        XCTAssertEqual(
            session.handle(.deleteBackward),
            handled(.clearMarkedText)
        )
        XCTAssertEqual(session.handle(.deleteBackward), .passThrough)
    }

    func testEscapeDiscardsOnlyAnActiveComposition() {
        var session = BopomofoInputSession()

        XCTAssertEqual(session.handle(.escape), .passThrough)
        _ = session.handle(.letterJ)
        XCTAssertEqual(
            session.handle(.escape),
            handled(.clearMarkedText)
        )
        XCTAssertFalse(session.hasComposition)
    }

    func testReturnAndKeypadEnterCommitAnIncompleteSyllable() {
        var returnSession = BopomofoInputSession()
        _ = returnSession.handle(.digit1)
        XCTAssertEqual(
            returnSession.handle(.returnKey),
            handled(.commitText("ㄅ"))
        )

        var keypadSession = BopomofoInputSession()
        _ = keypadSession.handle(.letterQ)
        XCTAssertEqual(
            keypadSession.handle(.keypadEnter),
            handled(.commitText("ㄆ"))
        )
    }

    func testEmptyToneAndControlKeysPassThrough() {
        for key in [
            KeyboardKey.space,
            .digit3,
            .digit4,
            .digit6,
            .digit7,
            .returnKey,
            .keypadEnter
        ] {
            var session = BopomofoInputSession()
            XCTAssertEqual(session.handle(key), .passThrough)
        }
    }

    func testUnhandledInputCommitsMarkedTextBeforePassingThrough() {
        var session = BopomofoInputSession()
        _ = session.handle(.letterJ)
        _ = session.handle(.letterI)

        XCTAssertEqual(
            session.finishBeforePassThrough(),
            InputSessionResult(
                textAction: .commitText("ㄨㄛ"),
                handled: false
            )
        )
        XCTAssertFalse(session.hasComposition)
    }

    private func handled(_ action: CompositionTextAction) -> InputSessionResult {
        InputSessionResult(textAction: action, handled: true)
    }
}
