import XCTest

final class CandidateSessionTests: XCTestCase {
    func testRejectsEmptyPronunciationAndCandidateList() {
        XCTAssertNil(CandidateSession(pronunciation: "", candidates: ["我"]))
        XCTAssertNil(CandidateSession(pronunciation: "ㄨㄛˇ", candidates: []))
    }

    func testDeduplicatesCandidatesWithoutChangingOrder() throws {
        let session = try XCTUnwrap(
            CandidateSession(
                pronunciation: "ㄨㄛˇ",
                candidates: ["我", "倭", "我", "婑"]
            )
        )

        XCTAssertEqual(session.candidates, ["我", "倭", "婑"])
        XCTAssertEqual(session.preferredCandidate, "我")
        XCTAssertEqual(session.highlightedIndex, 0)
        XCTAssertEqual(session.presentationMode, .compact)
    }

    func testOnlyKnownHighlightCanChangePreferredCandidate() throws {
        var session = try XCTUnwrap(
            CandidateSession(pronunciation: "ㄨㄛˇ", candidates: ["我", "倭"])
        )

        session.updateHighlightedCandidate("未知")
        XCTAssertEqual(session.preferredCandidate, "我")

        session.updateHighlightedCandidate("倭")
        XCTAssertEqual(session.preferredCandidate, "倭")
    }

    func testValidatesFinalSelectionAgainstCurrentSnapshot() throws {
        let session = try XCTUnwrap(
            CandidateSession(pronunciation: "ㄨㄛˇ", candidates: ["我", "倭"])
        )

        XCTAssertEqual(session.validatedSelection("我"), "我")
        XCTAssertNil(session.validatedSelection("窩"))
    }

    func testNavigatesCandidatesFromTheCurrentHighlight() throws {
        var session = try XCTUnwrap(
            CandidateSession(
                pronunciation: "ㄨㄛˇ",
                candidates: ["我", "倭", "婑"]
            )
        )

        XCTAssertEqual(session.navigate(.next), "倭")
        XCTAssertEqual(session.navigate(.previous), "我")

        session.updateHighlightedCandidate("倭")
        XCTAssertEqual(session.navigate(.next), "婑")
        XCTAssertEqual(session.navigate(.previous), "倭")
        XCTAssertEqual(session.navigate(.first), "我")
        XCTAssertEqual(session.navigate(.last), "婑")
    }

    func testClampsCandidateNavigationAtListAndPageBoundaries() throws {
        let candidates = (0 ..< 20).map(String.init)
        var session = try XCTUnwrap(
            CandidateSession(pronunciation: "test", candidates: candidates)
        )

        XCTAssertEqual(session.navigate(.previous), "0")
        XCTAssertEqual(session.navigate(.previousPage), "0")
        XCTAssertEqual(session.navigate(.nextPage), "9")

        session.updateHighlightedCandidate("15")
        XCTAssertEqual(session.navigate(.previousPage), "6")
        XCTAssertEqual(session.navigate(.nextPage), "15")

        session.updateHighlightedCandidate("19")
        XCTAssertEqual(session.navigate(.next), "19")
        XCTAssertEqual(session.navigate(.nextPage), "19")
    }

    func testExpandedNavigationUsesNineColumnsAndTwentySevenItemPages() throws {
        let candidates = (0 ..< 100).map(String.init)
        var session = try XCTUnwrap(
            CandidateSession(pronunciation: "test", candidates: candidates)
        )

        XCTAssertTrue(session.expand())
        XCTAssertFalse(session.expand())
        XCTAssertEqual(session.highlightedIndex, 0)
        XCTAssertEqual(session.navigate(.down), "9")
        XCTAssertEqual(session.navigate(.down), "18")
        XCTAssertEqual(session.navigate(.up), "9")
        XCTAssertEqual(session.navigate(.nextPage), "36")
        XCTAssertEqual(session.navigate(.previousPage), "9")

        session.updateHighlightedCandidate("98")
        XCTAssertEqual(session.navigate(.down), "98")
        XCTAssertEqual(session.navigate(.nextPage), "99")
    }

    func testExpandedVerticalNavigationStaysInTheSameColumn() throws {
        var session = try XCTUnwrap(
            CandidateSession(
                pronunciation: "test",
                candidates: (0 ..< 28).map(String.init)
            )
        )
        _ = session.expand()

        session.updateHighlightedCandidate("8")
        XCTAssertEqual(session.navigate(.up), "8")

        session.updateHighlightedCandidate("18")
        XCTAssertEqual(session.navigate(.down), "27")

        session.updateHighlightedCandidate("26")
        XCTAssertEqual(session.navigate(.down), "26")
    }

    func testNumberSelectionUsesTheHighlightedNineCandidatePage() throws {
        let candidates = (0 ..< 20).map(String.init)
        var session = try XCTUnwrap(
            CandidateSession(pronunciation: "test", candidates: candidates)
        )

        XCTAssertEqual(session.candidate(atSelectionKeyIndex: 0), "0")
        XCTAssertEqual(session.candidate(atSelectionKeyIndex: 8), "8")

        session.updateHighlightedCandidate("10")
        XCTAssertEqual(session.candidate(atSelectionKeyIndex: 0), "9")
        XCTAssertEqual(session.candidate(atSelectionKeyIndex: 8), "17")

        session.updateHighlightedCandidate("19")
        XCTAssertEqual(session.candidate(atSelectionKeyIndex: 0), "18")
        XCTAssertEqual(session.candidate(atSelectionKeyIndex: 1), "19")
        XCTAssertNil(session.candidate(atSelectionKeyIndex: 2))
        XCTAssertNil(session.candidate(atSelectionKeyIndex: -1))
        XCTAssertNil(session.candidate(atSelectionKeyIndex: 9))
    }

}
