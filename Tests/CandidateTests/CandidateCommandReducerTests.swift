import XCTest

final class CandidateCommandReducerTests: XCTestCase {
    func testFirstDownOnlyExpandsWithoutCommittingOrMoving() throws {
        var session = try makeSession(count: 40)
        session.updateHighlightedCandidate(session.candidates[10].id)

        guard case let .update(updated) = CandidateCommandReducer.reduce(
            .expand,
            session: session
        ) else {
            return XCTFail("Expected a presentation update")
        }

        XCTAssertTrue(updated.isExpanded)
        XCTAssertEqual(updated.highlightedIndex, 10)
        XCTAssertFalse(session.isExpanded)
        XCTAssertEqual(session.highlightedIndex, 10)
    }

    func testNavigationOnlyUpdatesTheCandidateSnapshotCopy() throws {
        var session = try makeSession(count: 40)
        _ = session.expand()

        guard case let .update(updated) = CandidateCommandReducer.reduce(
            .navigate(.down),
            session: session
        ) else {
            return XCTFail("Expected a presentation update")
        }

        XCTAssertEqual(updated.highlightedIndex, 9)
        XCTAssertEqual(session.highlightedIndex, 0)
        XCTAssertEqual(updated.candidates, session.candidates)
    }

    func testInvalidNumberSlotIsConsumedWithoutACommit() throws {
        var session = try makeSession(count: 10)
        session.updateHighlightedCandidate(session.candidates[9].id)

        XCTAssertEqual(
            CandidateCommandReducer.reduce(.select(1), session: session),
            .handledWithoutChange
        )
    }

    func testNumberSelectionCommitsTypedCandidateWithItsZeroBasedSlot() throws {
        let session = try makeSession(count: 4)

        XCTAssertEqual(
            CandidateCommandReducer.reduce(.select(1), session: session),
            .commit(session.candidates[1], reason: .number(1))
        )
    }

    func testSpaceCommitsFirstAndReturnCommitsHighlightWithReasons() throws {
        var session = try makeSession(count: 4)
        session.updateHighlightedCandidate(session.candidates[2].id)

        XCTAssertEqual(
            CandidateCommandReducer.reduce(.commitFirst, session: session),
            .commit(session.candidates[0], reason: .space)
        )
        XCTAssertEqual(
            CandidateCommandReducer.reduce(
                .commitHighlighted,
                session: session
            ),
            .commit(session.candidates[2], reason: .returnKey)
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
                candidates: (0 ..< count).map {
                    Candidate(
                        text: String($0),
                        pronunciation: "test",
                        baseRank: $0
                    )
                }
            )
        )
    }
}
