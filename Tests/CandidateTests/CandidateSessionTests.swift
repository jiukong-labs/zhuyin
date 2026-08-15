import XCTest

final class CandidateSessionTests: XCTestCase {
    func testRejectsEmptyPronunciationAndCandidateList() {
        XCTAssertNil(
            CandidateSession(
                pronunciation: "",
                candidates: [makeCandidate("我", pronunciation: "ㄨㄛˇ")]
            )
        )
        XCTAssertNil(CandidateSession(pronunciation: "ㄨㄛˇ", candidates: []))
    }

    func testDeduplicatesCandidateIDsWithoutChangingOrder() throws {
        let first = makeCandidate(
            "我",
            pronunciation: "ㄨㄛˇ",
            rank: 0
        )
        let duplicateWithUpdatedLearning = makeCandidate(
            "我",
            pronunciation: "ㄨㄛˇ",
            rank: 99,
            userFrequency: 20
        )
        let second = makeCandidate(
            "倭",
            pronunciation: "ㄨㄛˇ",
            rank: 1
        )
        let session = try XCTUnwrap(
            CandidateSession(
                pronunciation: "ㄨㄛˇ",
                candidates: [
                    first,
                    second,
                    duplicateWithUpdatedLearning
                ]
            )
        )

        XCTAssertEqual(session.candidates, [first, second])
        XCTAssertEqual(session.preferredCandidate, first)
        XCTAssertEqual(session.highlightedIndex, 0)
        XCTAssertEqual(session.presentationMode, .compact)
    }

    func testRetainsSameVisibleTextWhenTypedCandidateIDsDiffer() throws {
        let character = makeCandidate("行", pronunciation: "ㄒㄧㄥˊ")
        let phrase = Candidate(
            text: "行",
            pronunciation: "ㄒㄧㄥˊ",
            type: .phrase
        )
        let session = try XCTUnwrap(
            CandidateSession(
                pronunciation: "ㄒㄧㄥˊ",
                candidates: [character, phrase]
            )
        )

        XCTAssertNotEqual(character.id, phrase.id)
        XCTAssertEqual(session.candidates, [character, phrase])
    }

    func testOnlyKnownCandidateIDCanChangePreferredCandidate() throws {
        let first = makeCandidate("我", pronunciation: "ㄨㄛˇ")
        let second = makeCandidate("倭", pronunciation: "ㄨㄛˇ", rank: 1)
        let unknown = makeCandidate("未知", pronunciation: "ㄨㄛˇ")
        var session = try XCTUnwrap(
            CandidateSession(
                pronunciation: "ㄨㄛˇ",
                candidates: [first, second]
            )
        )

        session.updateHighlightedCandidate(unknown.id)
        XCTAssertEqual(session.preferredCandidate, first)

        session.updateHighlightedCandidate(second.id)
        XCTAssertEqual(session.preferredCandidate, second)
    }

    func testValidatesFinalSelectionAgainstCurrentSnapshotByID() throws {
        let first = makeCandidate("我", pronunciation: "ㄨㄛˇ")
        let second = makeCandidate("倭", pronunciation: "ㄨㄛˇ", rank: 1)
        let unknown = makeCandidate("窩", pronunciation: "ㄨㄛˇ")
        let session = try XCTUnwrap(
            CandidateSession(
                pronunciation: "ㄨㄛˇ",
                candidates: [first, second]
            )
        )

        XCTAssertEqual(session.validatedSelection(first.id), first)
        XCTAssertNil(session.validatedSelection(unknown.id))
    }

    func testActiveSessionRetainsItsImmutableRankedSnapshot() throws {
        let first = makeCandidate("我", rank: 0)
        let second = makeCandidate("倭", rank: 1)
        let session = try XCTUnwrap(
            CandidateSession(
                pronunciation: "test",
                candidates: [first, second]
            )
        )

        let newlyLearnedSecond = makeCandidate(
            "倭",
            rank: 1,
            userFrequency: 50
        )
        let nextSession = try XCTUnwrap(
            CandidateSession(
                pronunciation: "test",
                candidates: [newlyLearnedSecond, first]
            )
        )

        XCTAssertEqual(session.candidates, [first, second])
        XCTAssertEqual(session.preferredCandidate, first)
        XCTAssertEqual(nextSession.preferredCandidate, newlyLearnedSecond)
    }

    func testNavigatesCandidatesFromTheCurrentHighlight() throws {
        var session = try makeSession(count: 3)

        XCTAssertEqual(session.navigate(.next).text, "1")
        XCTAssertEqual(session.navigate(.previous).text, "0")

        session.updateHighlightedCandidate(session.candidates[1].id)
        XCTAssertEqual(session.navigate(.next).text, "2")
        XCTAssertEqual(session.navigate(.previous).text, "1")
        XCTAssertEqual(session.navigate(.first).text, "0")
        XCTAssertEqual(session.navigate(.last).text, "2")
    }

    func testClampsCandidateNavigationAtListAndPageBoundaries() throws {
        var session = try makeSession(count: 20)

        XCTAssertEqual(session.navigate(.previous).text, "0")
        XCTAssertEqual(session.navigate(.previousPage).text, "0")
        XCTAssertEqual(session.navigate(.nextPage).text, "9")

        session.updateHighlightedCandidate(session.candidates[15].id)
        XCTAssertEqual(session.navigate(.previousPage).text, "6")
        XCTAssertEqual(session.navigate(.nextPage).text, "15")

        session.updateHighlightedCandidate(session.candidates[19].id)
        XCTAssertEqual(session.navigate(.next).text, "19")
        XCTAssertEqual(session.navigate(.nextPage).text, "19")
    }

    func testExpandedNavigationUsesNineColumnsAndTwentySevenItemPages() throws {
        var session = try makeSession(count: 100)

        XCTAssertTrue(session.expand())
        XCTAssertFalse(session.expand())
        XCTAssertEqual(session.highlightedIndex, 0)
        XCTAssertEqual(session.navigate(.down).text, "9")
        XCTAssertEqual(session.navigate(.down).text, "18")
        XCTAssertEqual(session.navigate(.up).text, "9")
        XCTAssertEqual(session.navigate(.nextPage).text, "36")
        XCTAssertEqual(session.navigate(.previousPage).text, "9")

        session.updateHighlightedCandidate(session.candidates[98].id)
        XCTAssertEqual(session.navigate(.down).text, "98")
        XCTAssertEqual(session.navigate(.nextPage).text, "99")
    }

    func testExpandedVerticalNavigationStaysInTheSameColumn() throws {
        var session = try makeSession(count: 28)
        _ = session.expand()

        session.updateHighlightedCandidate(session.candidates[8].id)
        XCTAssertEqual(session.navigate(.up).text, "8")

        session.updateHighlightedCandidate(session.candidates[18].id)
        XCTAssertEqual(session.navigate(.down).text, "27")

        session.updateHighlightedCandidate(session.candidates[26].id)
        XCTAssertEqual(session.navigate(.down).text, "26")
    }

    func testNumberSelectionUsesTheHighlightedNineCandidatePage() throws {
        var session = try makeSession(count: 20)

        XCTAssertEqual(session.candidate(atSelectionKeyIndex: 0)?.text, "0")
        XCTAssertEqual(session.candidate(atSelectionKeyIndex: 8)?.text, "8")

        session.updateHighlightedCandidate(session.candidates[10].id)
        XCTAssertEqual(session.candidate(atSelectionKeyIndex: 0)?.text, "9")
        XCTAssertEqual(session.candidate(atSelectionKeyIndex: 8)?.text, "17")

        session.updateHighlightedCandidate(session.candidates[19].id)
        XCTAssertEqual(session.candidate(atSelectionKeyIndex: 0)?.text, "18")
        XCTAssertEqual(session.candidate(atSelectionKeyIndex: 1)?.text, "19")
        XCTAssertNil(session.candidate(atSelectionKeyIndex: 2))
        XCTAssertNil(session.candidate(atSelectionKeyIndex: -1))
        XCTAssertNil(session.candidate(atSelectionKeyIndex: 9))
    }

    private func makeSession(count: Int) throws -> CandidateSession {
        try XCTUnwrap(
            CandidateSession(
                pronunciation: "test",
                candidates: (0 ..< count).map {
                    makeCandidate(String($0), rank: $0)
                }
            )
        )
    }

    private func makeCandidate(
        _ text: String,
        pronunciation: String = "test",
        rank: Int = 0,
        userFrequency: Int64 = 0
    ) -> Candidate {
        Candidate(
            text: text,
            pronunciation: pronunciation,
            baseRank: rank,
            userFrequency: userFrequency
        )
    }
}
