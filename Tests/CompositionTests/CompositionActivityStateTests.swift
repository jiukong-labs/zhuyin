import XCTest

final class CompositionActivityStateTests: XCTestCase {
    func testEmptyStateIsInactive() {
        XCTAssertFalse(activity())
    }

    func testBopomofoInputIsActive() {
        XCTAssertTrue(activity(inputSession: true))
    }

    func testCandidateSessionIsActive() {
        XCTAssertTrue(activity(candidate: true))
    }

    func testNonEmptyCompositionBufferIsActive() {
        XCTAssertTrue(activity(bufferIsEmpty: false))
    }

    func testCommitAndCancelStatesAreInactiveAfterAllSourcesClear() {
        XCTAssertFalse(activity())
        XCTAssertFalse(activity())
    }

    private func activity(
        candidate: Bool = false,
        inputSession: Bool = false,
        bufferIsEmpty: Bool = true
    ) -> Bool {
        CompositionActivityState.isActive(
            hasCandidateSession: candidate,
            inputSessionHasComposition: inputSession,
            compositionBufferIsEmpty: bufferIsEmpty
        )
    }
}
