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

    func testPhraseLookupStopsAtPunctuation() {
        var buffer = CompositionBuffer()
        buffer.append(text: "久", pronunciation: "ㄐㄧㄡˇ")
        buffer.appendPunctuation("，")

        XCTAssertEqual(buffer.phraseLookupQueries(appending: "ㄎㄨㄥ"), [])

        buffer.append(text: "空", pronunciation: "ㄎㄨㄥ")
        let queries = buffer.phraseLookupQueries(appending: "ㄕㄨ")

        XCTAssertEqual(
            queries.map(\.pronunciationSequence),
            [["ㄎㄨㄥ", "ㄕㄨ"]]
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

    func testSelectedRangeCoveringPunctuationIsNotAPhrase() {
        var buffer = CompositionBuffer()
        buffer.append(text: "久", pronunciation: "ㄐㄧㄡˇ")
        buffer.append(text: "空", pronunciation: "ㄎㄨㄥ")
        buffer.appendPunctuation("，")

        buffer.expandSelectionBackward()
        buffer.expandSelectionBackward()

        XCTAssertTrue(buffer.hasSelection)
        XCTAssertNil(buffer.selectedPhrase)

        buffer.expandSelectionBackward()
        XCTAssertNil(buffer.selectedPhrase)
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
