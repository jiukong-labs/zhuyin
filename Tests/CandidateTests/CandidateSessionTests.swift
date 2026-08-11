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

        XCTAssertEqual(session.candidate(after: .next), "倭")
        XCTAssertEqual(session.candidate(after: .previous), "我")

        session.updateHighlightedCandidate("倭")
        XCTAssertEqual(session.candidate(after: .next), "婑")
        XCTAssertEqual(session.candidate(after: .previous), "我")
        XCTAssertEqual(session.candidate(after: .first), "我")
        XCTAssertEqual(session.candidate(after: .last), "婑")
    }

    func testClampsCandidateNavigationAtListAndPageBoundaries() throws {
        let candidates = (0 ..< 20).map(String.init)
        var session = try XCTUnwrap(
            CandidateSession(pronunciation: "test", candidates: candidates)
        )

        XCTAssertEqual(session.candidate(after: .previous), "0")
        XCTAssertEqual(session.candidate(after: .previousPage), "0")
        XCTAssertEqual(session.candidate(after: .nextPage), "9")

        session.updateHighlightedCandidate("15")
        XCTAssertEqual(session.candidate(after: .previousPage), "6")
        XCTAssertEqual(session.candidate(after: .nextPage), "19")

        session.updateHighlightedCandidate("19")
        XCTAssertEqual(session.candidate(after: .next), "19")
        XCTAssertEqual(session.candidate(after: .nextPage), "19")
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

    func testResolvesAVisibleIdentifierAgainstTheCurrentSnapshot() throws {
        let session = try XCTUnwrap(
            CandidateSession(
                pronunciation: "ㄨㄛˇ",
                candidates: ["我", "倭", "婑"]
            )
        )
        let identifiers = ["我": 10, "倭": 11, "婑": 12]

        XCTAssertEqual(
            session.candidate(
                matchingIdentifier: 11,
                using: { identifiers[$0] ?? -1 }
            ),
            "倭"
        )
        XCTAssertNil(
            session.candidate(
                matchingIdentifier: 99,
                using: { identifiers[$0] ?? -1 }
            )
        )
    }

}
