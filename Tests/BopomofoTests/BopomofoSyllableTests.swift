import XCTest

final class BopomofoSyllableTests: XCTestCase {
    func testDefinesAllRequiredComponentGroups() {
        XCTAssertEqual(BopomofoInitial.allCases.map(\.rawValue).joined(), "ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙ")
        XCTAssertEqual(BopomofoMedial.allCases.map(\.rawValue).joined(), "ㄧㄨㄩ")
        XCTAssertEqual(BopomofoFinal.allCases.map(\.rawValue).joined(), "ㄚㄛㄜㄝㄞㄟㄠㄡㄢㄣㄤㄥㄦ")
        XCTAssertEqual(BopomofoTone.allCases.map(\.rawValue), ["", "ˊ", "ˇ", "ˋ", "˙"])
    }

    func testRendersComponentsInCanonicalOrder() {
        var syllable = BopomofoSyllable()

        syllable.apply(.final(.an))
        syllable.apply(.initial(.j))
        syllable.apply(.tone(.fourth))
        syllable.apply(.medial(.i))

        XCTAssertEqual(syllable.text, "ㄐㄧㄢˋ")
    }

    func testReplacesAComponentInTheSameGroup() {
        var syllable = BopomofoSyllable()

        syllable.apply(.initial(.b))
        syllable.apply(.initial(.p))
        syllable.apply(.final(.a))
        syllable.apply(.final(.o))

        XCTAssertEqual(syllable.text, "ㄆㄛ")
    }

    func testPlacesTheNeutralToneBeforeAHorizontalSyllable() {
        var syllable = BopomofoSyllable()
        syllable.apply(.initial(.d))
        syllable.apply(.final(.e))
        syllable.apply(.tone(.neutral))

        XCTAssertEqual(syllable.text, "˙ㄉㄜ")
    }

    func testBackspaceRemovesComponentsInReverseInputOrder() {
        var syllable = BopomofoSyllable()
        syllable.apply(.initial(.j))
        syllable.apply(.medial(.i))
        syllable.apply(.final(.an))
        syllable.apply(.tone(.fourth))

        XCTAssertTrue(syllable.removeLastComponent())
        XCTAssertEqual(syllable.text, "ㄐㄧㄢ")
        XCTAssertTrue(syllable.removeLastComponent())
        XCTAssertEqual(syllable.text, "ㄐㄧ")
        XCTAssertTrue(syllable.removeLastComponent())
        XCTAssertEqual(syllable.text, "ㄐ")
        XCTAssertTrue(syllable.removeLastComponent())
        XCTAssertTrue(syllable.isEmpty)
        XCTAssertFalse(syllable.removeLastComponent())
    }

    func testBackspaceUsesInputOrderWhenComponentsArriveOutOfOrder() {
        var syllable = BopomofoSyllable()
        syllable.apply(.final(.an))
        syllable.apply(.initial(.j))

        XCTAssertEqual(syllable.text, "ㄐㄢ")
        XCTAssertTrue(syllable.removeLastComponent())
        XCTAssertEqual(syllable.text, "ㄢ")
        XCTAssertTrue(syllable.removeLastComponent())
        XCTAssertTrue(syllable.isEmpty)
    }
}
