import XCTest

final class CandidateInputSourcePolicyTests: XCTestCase {
    func testKeepsPresentationForTheOwningInputSource() {
        XCTAssertFalse(
            CandidateInputSourcePolicy.shouldFinishPresentation(
                currentInputSourceID: "tw.org.example.input-method",
                ownInputSourceID: "tw.org.example.input-method"
            )
        )
    }

    func testFinishesPresentationAfterSwitchingInputSources() {
        XCTAssertTrue(
            CandidateInputSourcePolicy.shouldFinishPresentation(
                currentInputSourceID: "com.apple.inputmethod.TCIM.Zhuyin",
                ownInputSourceID: "tw.org.example.input-method"
            )
        )
    }

    func testKeepsPresentationWhenEitherIdentifierIsUnavailable() {
        XCTAssertFalse(
            CandidateInputSourcePolicy.shouldFinishPresentation(
                currentInputSourceID: nil,
                ownInputSourceID: "tw.org.example.input-method"
            )
        )
        XCTAssertFalse(
            CandidateInputSourcePolicy.shouldFinishPresentation(
                currentInputSourceID: "com.apple.inputmethod.TCIM.Zhuyin",
                ownInputSourceID: nil
            )
        )
        XCTAssertFalse(
            CandidateInputSourcePolicy.shouldFinishPresentation(
                currentInputSourceID: "com.apple.inputmethod.TCIM.Zhuyin",
                ownInputSourceID: ""
            )
        )
    }
}
