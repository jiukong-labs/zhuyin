import XCTest

final class BopomofoParserTests: XCTestCase {
    func testComposesMedialFinalAndThirdTone() {
        var parser = BopomofoParser()

        XCTAssertEqual(
            parser.input(.medial(.u)),
            .composing(syllable(medial: .u))
        )
        XCTAssertEqual(
            parser.input(.final(.o)),
            .composing(syllable(medial: .u, final: .o))
        )
        XCTAssertEqual(
            parser.input(.tone(.third)),
            .completed(syllable(medial: .u, final: .o, tone: .third))
        )
        XCTAssertFalse(parser.hasComposition)
    }

    func testComposesInitialMedialFinalAndFourthTone() {
        var parser = BopomofoParser()

        _ = parser.input(.initial(.j))
        _ = parser.input(.medial(.i))
        _ = parser.input(.final(.an))

        XCTAssertEqual(
            parser.input(.tone(.fourth)),
            .completed(
                syllable(initial: .j, medial: .i, final: .an, tone: .fourth)
            )
        )
    }

    func testSupportsEveryToneIncludingUnmarkedFirstTone() {
        for tone in BopomofoTone.allCases {
            var parser = BopomofoParser()
            _ = parser.input(.initial(.b))

            XCTAssertEqual(
                parser.input(.tone(tone)),
                .completed(syllable(initial: .b, tone: tone))
            )
        }
    }

    func testRejectsToneWithoutSyllableBody() {
        var parser = BopomofoParser()

        XCTAssertEqual(parser.input(.tone(.third)), .rejected)
        XCTAssertFalse(parser.hasComposition)
    }

    private func syllable(
        initial: BopomofoInitial? = nil,
        medial: BopomofoMedial? = nil,
        final: BopomofoFinal? = nil,
        tone: BopomofoTone? = nil
    ) -> BopomofoSyllable {
        var value = BopomofoSyllable()
        if let initial { value.apply(.initial(initial)) }
        if let medial { value.apply(.medial(medial)) }
        if let final { value.apply(.final(final)) }
        if let tone { value.apply(.tone(tone)) }
        return value
    }
}
