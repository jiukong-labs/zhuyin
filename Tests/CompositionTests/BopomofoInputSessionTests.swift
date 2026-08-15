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
            handled(.completeSyllable(syllable([
                .medial(.u),
                .final(.o),
                .tone(.third)
            ])))
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
            handled(.completeSyllable(syllable([
                .initial(.j),
                .medial(.i),
                .final(.an),
                .tone(.fourth)
            ])))
        )
    }

    func testSpaceCompletesAnActiveFirstToneSyllable() {
        var session = BopomofoInputSession()
        _ = session.handle(.digit1)

        XCTAssertEqual(
            session.handle(.space),
            handled(.completeSyllable(syllable([
                .initial(.b),
                .tone(.first)
            ])))
        )
    }

    func testNeutralToneIsCommittedBeforeTheSyllableBody() {
        var session = BopomofoInputSession()
        _ = session.handle(.digit2)
        _ = session.handle(.letterK)

        XCTAssertEqual(
            session.handle(.digit7),
            handled(.completeSyllable(syllable([
                .initial(.d),
                .final(.e),
                .tone(.neutral)
            ])))
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

    func testCandidateBackspaceRestoresSyllableAndDeletesEveryTone() {
        for tone in BopomofoTone.allCases {
            var session = BopomofoInputSession()
            let completedSyllable = syllable([
                .initial(.b),
                .tone(tone)
            ])

            XCTAssertEqual(
                session.resumeEditingAndDeleteBackward(completedSyllable),
                handled(.updateMarkedText("ㄅ")),
                "Failed to delete restored tone \(tone)"
            )
            XCTAssertEqual(
                session.handle(.deleteBackward),
                handled(.clearMarkedText)
            )
        }
    }

    func testCandidateBackspaceRestoresAndDeletesTheWholeSyllableInOrder() {
        var session = BopomofoInputSession()
        let completedSyllable = syllable([
            .initial(.j),
            .medial(.i),
            .final(.an),
            .tone(.fourth)
        ])

        XCTAssertEqual(
            session.resumeEditingAndDeleteBackward(completedSyllable),
            handled(.updateMarkedText("ㄐㄧㄢ"))
        )
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
    }

    private func handled(_ action: CompositionTextAction) -> InputSessionResult {
        InputSessionResult(textAction: action, handled: true)
    }

    private func syllable(
        _ components: [BopomofoComponent]
    ) -> BopomofoSyllable {
        var syllable = BopomofoSyllable()
        for component in components {
            syllable.apply(component)
        }
        return syllable
    }
}
