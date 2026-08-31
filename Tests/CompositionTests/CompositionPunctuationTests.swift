import Foundation
import XCTest

final class CompositionPunctuationTests: XCTestCase {
    func testPunctuationJoinsTheBufferTextWithoutAReading() throws {
        var buffer = CompositionBuffer()
        buffer.append(text: "我", pronunciation: "ㄨㄛˇ")

        let unit = try XCTUnwrap(buffer.appendPunctuation("，"))

        XCTAssertEqual(unit.kind, .punctuation)
        XCTAssertEqual(buffer.text, "我，")
        XCTAssertEqual(buffer.units.map(\.kind), [.reading, .punctuation])
    }

    func testPhraseLookupCarriesPunctuationContext() throws {
        var buffer = CompositionBuffer()
        buffer.append(text: "久", pronunciation: "ㄐㄧㄡˇ")
        buffer.appendPunctuation("，")

        let punctuatedQuery = try XCTUnwrap(
            buffer.phraseLookupQueries(appending: "ㄎㄨㄥ").first
        )
        XCTAssertEqual(
            punctuatedQuery.pronunciationSequence,
            ["ㄐㄧㄡˇ", "ㄎㄨㄥ"]
        )
        XCTAssertEqual(punctuatedQuery.existingOutputPattern?.rawValue, "RP")
        XCTAssertEqual(punctuatedQuery.existingPunctuationText, "，")

        buffer.append(text: "空", pronunciation: "ㄎㄨㄥ")
        let queries = buffer.phraseLookupQueries(appending: "ㄕㄨ")

        XCTAssertEqual(
            queries.map(\.pronunciationSequence),
            [["ㄐㄧㄡˇ", "ㄎㄨㄥ", "ㄕㄨ"], ["ㄎㄨㄥ", "ㄕㄨ"]]
        )
    }

    func testPhraseCandidateCannotReplaceASuffixContainingPunctuation() {
        var buffer = CompositionBuffer()
        buffer.append(text: "久", pronunciation: "ㄐㄧㄡˇ")
        buffer.appendPunctuation("，")

        XCTAssertFalse(
            buffer.containsExactSuffix(
                pronunciationSequence: ["ㄐㄧㄡˇ", "，"]
            )
        )
        XCTAssertFalse(
            buffer.acceptCandidate(
                Candidate(
                    text: "久空",
                    pronunciationSequence: ["ㄐㄧㄡˇ", "ㄎㄨㄥ"],
                    type: .phrase
                ),
                reason: .returnKey
            )
        )
        XCTAssertEqual(buffer.text, "久，")
    }

    func testSelectedRangeCoveringPunctuationIsAPhrase() throws {
        var buffer = CompositionBuffer()
        buffer.append(text: "久", pronunciation: "ㄐㄧㄡˇ")
        buffer.append(text: "空", pronunciation: "ㄎㄨㄥ")
        buffer.appendPunctuation("，")

        buffer.expandSelectionBackward()
        buffer.expandSelectionBackward()

        XCTAssertTrue(buffer.hasSelection)
        let shortPhrase = try XCTUnwrap(buffer.selectedPhrase)
        XCTAssertEqual(shortPhrase.text, "空，")
        XCTAssertEqual(shortPhrase.pronunciationSequence, ["ㄎㄨㄥ"])
        XCTAssertEqual(shortPhrase.outputPattern.rawValue, "RP")

        buffer.expandSelectionBackward()
        let longPhrase = try XCTUnwrap(buffer.selectedPhrase)
        XCTAssertEqual(longPhrase.text, "久空，")
        XCTAssertEqual(longPhrase.outputPattern.rawValue, "RRP")
    }

    func testPhraseStillWorksForReadingsBeforePunctuation() throws {
        var buffer = CompositionBuffer()
        buffer.appendPunctuation("「")
        buffer.append(text: "久", pronunciation: "ㄐㄧㄡˇ")
        buffer.append(text: "空", pronunciation: "ㄎㄨㄥ")

        buffer.expandSelectionBackward()
        buffer.expandSelectionBackward()
        let phrase = try XCTUnwrap(buffer.selectedPhrase)

        XCTAssertEqual(phrase.text, "久空")
        XCTAssertEqual(phrase.pronunciationSequence, ["ㄐㄧㄡˇ", "ㄎㄨㄥ"])
    }

    func testBackspaceRemovesPunctuationLikeAnyOtherUnit() {
        var buffer = CompositionBuffer()
        buffer.append(text: "我", pronunciation: "ㄨㄛˇ")
        buffer.appendPunctuation("。")

        let deleted = buffer.deleteBackward()

        XCTAssertEqual(deleted.map(\.text), ["。"])
        XCTAssertEqual(buffer.text, "我")
    }

    func testPunctuationIsCommittedWithTheRestOfTheComposition() throws {
        var buffer = CompositionBuffer()
        buffer.append(text: "我", pronunciation: "ㄨㄛˇ")
        buffer.appendPunctuation("，")
        buffer.append(text: "你", pronunciation: "ㄋㄧˇ")

        let snapshot = try XCTUnwrap(buffer.takeCommitSnapshot())

        XCTAssertEqual(snapshot.text, "我，你")
        XCTAssertTrue(buffer.isEmpty)
    }

    func testMarkedCaretFollowsPunctuationInUTF16() {
        var buffer = CompositionBuffer()
        buffer.append(text: "我", pronunciation: "ㄨㄛˇ")
        buffer.appendPunctuation("，")

        XCTAssertEqual(
            buffer.markedSelectionRange,
            NSRange(location: 2, length: 0)
        )
        XCTAssertEqual(
            CompositionPresentation.make(buffer: buffer, activeSuffix: "ㄋㄧ")?
                .text,
            "我，ㄋㄧ"
        )
    }
}
