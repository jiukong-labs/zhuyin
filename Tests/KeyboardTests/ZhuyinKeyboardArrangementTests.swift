import XCTest

final class ZhuyinKeyboardArrangementTests: XCTestCase {
    func testEveryArrangementCoversAllThirtySevenSymbolsAndFiveTones() {
        for arrangement in ZhuyinKeyboardArrangement.allCases {
            let produced = Self.componentsByKey(of: arrangement.layout)

            XCTAssertEqual(
                Set(produced.values.compactMap(Self.initial(of:))),
                Set(BopomofoInitial.allCases),
                "\(arrangement) initials"
            )
            XCTAssertEqual(
                Set(produced.values.compactMap(Self.medial(of:))),
                Set(BopomofoMedial.allCases),
                "\(arrangement) medials"
            )
            XCTAssertEqual(
                Set(produced.values.compactMap(Self.final(of:))),
                Set(BopomofoFinal.allCases),
                "\(arrangement) finals"
            )
            XCTAssertEqual(
                Set(produced.values.compactMap(Self.tone(of:))),
                Set(BopomofoTone.allCases),
                "\(arrangement) tones"
            )
            XCTAssertEqual(produced.count, 42, "\(arrangement) key count")
        }
    }

    func testNoArrangementMapsTwoKeysToTheSameComponent() {
        for arrangement in ZhuyinKeyboardArrangement.allCases {
            let texts = Self.componentsByKey(of: arrangement.layout)
                .values
                .map(\.text)

            XCTAssertEqual(
                texts.count,
                Set(texts).count,
                "\(arrangement) has a duplicated component"
            )
        }
    }

    func testControlKeysNeverCarryComponents() {
        let reserved: [KeyboardKey] = [
            .deleteBackward, .escape, .returnKey, .keypadEnter,
            .leftBracket, .rightBracket, .backslash,
        ]

        for arrangement in ZhuyinKeyboardArrangement.allCases {
            let layout = arrangement.layout
            for key in reserved {
                XCTAssertNil(
                    layout.component(for: key),
                    "\(arrangement) \(key)"
                )
            }
        }
    }

    func testPunctuationKeysStayAvailableOnEveryArrangement() {
        // Milestone 9 places punctuation on Shift or on keys no arrangement
        // uses, so adding an arrangement must not shadow a mark.
        let punctuation = PunctuationLayout.standard

        for arrangement in ZhuyinKeyboardArrangement.allCases {
            let layout = arrangement.layout
            for key in [KeyboardKey.leftBracket, .rightBracket, .backslash] {
                XCTAssertNotNil(
                    punctuation.punctuation(for: key, shifted: false),
                    "\(key)"
                )
                XCTAssertNil(layout.component(for: key), "\(arrangement) \(key)")
            }
        }
    }

    func testEachArrangementComposesTheSameSyllableFromItsOwnKeys() {
        let cases: [(ZhuyinKeyboardArrangement, [KeyboardKey])] = [
            (.standard, [.letterJ, .letterI, .digit3]),
            (.eten, [.letterX, .letterO, .digit3]),
            (.ibm, [.letterS, .letterG, .comma]),
        ]

        for (arrangement, keys) in cases {
            var session = BopomofoInputSession(
                keyboardLayout: arrangement.layout
            )
            var completed: BopomofoSyllable?
            for key in keys {
                if case let .completeSyllable(syllable) =
                    session.handle(key).textAction {
                    completed = syllable
                }
            }

            XCTAssertEqual(completed?.text, "ㄨㄛˇ", "\(arrangement)")
        }
    }

    func testEtenUsesEveryLetterKeyExactlyOnce() {
        let letters: Set<KeyboardKey> = [
            .letterA, .letterB, .letterC, .letterD, .letterE, .letterF,
            .letterG, .letterH, .letterI, .letterJ, .letterK, .letterL,
            .letterM, .letterN, .letterO, .letterP, .letterQ, .letterR,
            .letterS, .letterT, .letterU, .letterV, .letterW, .letterX,
            .letterY, .letterZ,
        ]
        let layout = EtenZhuyinLayout()

        for letter in letters {
            XCTAssertNotNil(layout.component(for: letter), "\(letter)")
        }
    }

    func testIBMRunsTheSymbolsInBopomofoOrder() {
        let layout = IBMZhuyinLayout()
        let ordered: [KeyboardKey] = [
            .digit1, .digit2, .digit3, .digit4, .digit5, .digit6,
            .digit7, .digit8, .digit9, .digit0, .minus,
            .letterQ, .letterW, .letterE, .letterR, .letterT,
            .letterY, .letterU, .letterI, .letterO, .letterP,
        ]

        XCTAssertEqual(
            ordered.compactMap { layout.component(for: $0)?.text },
            BopomofoInitial.allCases.map(\.rawValue)
        )
    }

    func testArrangementRawValuesArePersistable() {
        for arrangement in ZhuyinKeyboardArrangement.allCases {
            XCTAssertEqual(
                ZhuyinKeyboardArrangement(rawValue: arrangement.rawValue),
                arrangement
            )
            XCTAssertFalse(arrangement.localizedName.isEmpty)
        }
    }

    private static func componentsByKey(
        of layout: any KeyboardLayout
    ) -> [KeyboardKey: BopomofoComponent] {
        var result: [KeyboardKey: BopomofoComponent] = [:]
        for key in allKeys {
            if let component = layout.component(for: key) {
                result[key] = component
            }
        }
        return result
    }

    private static let allKeys: [KeyboardKey] = [
        .digit0, .digit1, .digit2, .digit3, .digit4,
        .digit5, .digit6, .digit7, .digit8, .digit9,
        .letterA, .letterB, .letterC, .letterD, .letterE, .letterF,
        .letterG, .letterH, .letterI, .letterJ, .letterK, .letterL,
        .letterM, .letterN, .letterO, .letterP, .letterQ, .letterR,
        .letterS, .letterT, .letterU, .letterV, .letterW, .letterX,
        .letterY, .letterZ,
        .comma, .period, .semicolon, .slash, .minus, .quote, .equal,
        .leftBracket, .rightBracket, .backslash,
        .space, .deleteBackward, .escape, .returnKey, .keypadEnter,
    ]

    private static func initial(
        of component: BopomofoComponent
    ) -> BopomofoInitial? {
        if case let .initial(value) = component {
            return value
        }
        return nil
    }

    private static func medial(
        of component: BopomofoComponent
    ) -> BopomofoMedial? {
        if case let .medial(value) = component {
            return value
        }
        return nil
    }

    private static func final(
        of component: BopomofoComponent
    ) -> BopomofoFinal? {
        if case let .final(value) = component {
            return value
        }
        return nil
    }

    private static func tone(
        of component: BopomofoComponent
    ) -> BopomofoTone? {
        if case let .tone(value) = component {
            return value
        }
        return nil
    }
}
