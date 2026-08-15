import XCTest

final class CandidateCommandReducerTests: XCTestCase {
    func testFirstDownOnlyExpandsWithoutCommittingOrMoving() throws {
        var session = try makeSession(count: 40)
        session.updateHighlightedCandidate("10")

        guard case let .update(updated) = CandidateCommandReducer.reduce(
            .expand,
            session: session
        ) else {
            return XCTFail("Expected a presentation update")
        }

        XCTAssertTrue(updated.isExpanded)
        XCTAssertEqual(updated.highlightedIndex, 10)
    }

    func testNavigationOnlyUpdatesTheCandidateSnapshot() throws {
        var session = try makeSession(count: 40)
        _ = session.expand()

        guard case let .update(updated) = CandidateCommandReducer.reduce(
            .navigate(.down),
            session: session
        ) else {
            return XCTFail("Expected a presentation update")
        }

        XCTAssertEqual(updated.highlightedIndex, 9)
    }

    func testInvalidNumberSlotIsConsumedWithoutACommit() throws {
        var session = try makeSession(count: 10)
        session.updateHighlightedCandidate("9")

        XCTAssertEqual(
            CandidateCommandReducer.reduce(.select(1), session: session),
            .handledWithoutChange
        )
    }

    func testSpaceCommitsFirstAndReturnCommitsHighlight() throws {
        var session = try makeSession(count: 4)
        session.updateHighlightedCandidate("2")

        XCTAssertEqual(
            CandidateCommandReducer.reduce(.commitFirst, session: session),
            .commit("0")
        )
        XCTAssertEqual(
            CandidateCommandReducer.reduce(
                .commitHighlighted,
                session: session
            ),
            .commit("2")
        )
    }

    func testCancelAndBackspaceRemainSideEffectsForTheController() throws {
        let session = try makeSession(count: 1)

        XCTAssertEqual(
            CandidateCommandReducer.reduce(.cancel, session: session),
            .cancel
        )
        XCTAssertEqual(
            CandidateCommandReducer.reduce(.deleteBackward, session: session),
            .deleteBackward
        )
    }

    private func makeSession(count: Int) throws -> CandidateSession {
        try XCTUnwrap(
            CandidateSession(
                pronunciation: "test",
                candidates: (0 ..< count).map(String.init)
            )
        )
    }
}
