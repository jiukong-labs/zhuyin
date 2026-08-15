import CoreGraphics
import XCTest

final class CandidateWindowGeometryTests: XCTestCase {
    func testPlacesWindowBelowCaretWhenThereIsRoom() {
        let frame = CandidateWindowPlacement.frame(
            anchor: CGRect(x: 100, y: 500, width: 1, height: 20),
            desiredSize: CGSize(width: 300, height: 100),
            visibleFrames: [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
        )

        XCTAssertEqual(frame, CGRect(x: 100, y: 394, width: 300, height: 100))
    }

    func testFlipsAboveCaretNearBottomEdge() {
        let frame = CandidateWindowPlacement.frame(
            anchor: CGRect(x: 100, y: 20, width: 1, height: 20),
            desiredSize: CGSize(width: 300, height: 100),
            visibleFrames: [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
        )

        XCTAssertEqual(frame.origin.y, 46)
    }

    func testClampsAwayFromRightAndLeftEdges() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let rightFrame = CandidateWindowPlacement.frame(
            anchor: CGRect(x: 950, y: 500, width: 1, height: 20),
            desiredSize: CGSize(width: 300, height: 100),
            visibleFrames: [visibleFrame]
        )
        let leftFrame = CandidateWindowPlacement.frame(
            anchor: CGRect(x: -50, y: 500, width: 1, height: 20),
            desiredSize: CGSize(width: 300, height: 100),
            visibleFrames: [visibleFrame]
        )

        XCTAssertEqual(rightFrame.maxX, 992)
        XCTAssertEqual(leftFrame.minX, 8)
    }

    func testUsesTheNegativeOriginDisplayContainingTheCaret() {
        let leftDisplay = CGRect(x: -1_280, y: -200, width: 1_280, height: 900)
        let mainDisplay = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
        let target = CandidateWindowPlacement.targetVisibleFrame(
            anchor: CGRect(x: -1_000, y: 100, width: 1, height: 20),
            visibleFrames: [mainDisplay, leftDisplay]
        )

        XCTAssertEqual(target, leftDisplay)
    }

    func testKeepsTheFinalWindowInsideANegativeOriginDisplay() {
        let visibleFrame = CGRect(
            x: -1_280,
            y: -200,
            width: 1_280,
            height: 900
        )
        let frame = CandidateWindowPlacement.frame(
            anchor: CGRect(x: -20, y: -180, width: 1, height: 20),
            desiredSize: CGSize(width: 600, height: 140),
            visibleFrames: [visibleFrame]
        )

        XCTAssertGreaterThanOrEqual(frame.minX, visibleFrame.minX + 8)
        XCTAssertLessThanOrEqual(frame.maxX, visibleFrame.maxX - 8)
        XCTAssertGreaterThanOrEqual(frame.minY, visibleFrame.minY + 8)
        XCTAssertLessThanOrEqual(frame.maxY, visibleFrame.maxY - 8)
        XCTAssertGreaterThan(frame.minY, -160)
    }

    func testCapsOversizedWindowInsideVisibleFrame() {
        let frame = CandidateWindowPlacement.frame(
            anchor: CGRect(x: 500, y: 400, width: 1, height: 20),
            desiredSize: CGSize(width: 2_000, height: 2_000),
            visibleFrames: [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
        )

        XCTAssertEqual(frame, CGRect(x: 8, y: 8, width: 984, height: 784))
    }

    func testChoosesNearestDisplayForOffscreenCaret() {
        let left = CGRect(x: -1_000, y: 0, width: 1_000, height: 800)
        let right = CGRect(x: 100, y: 0, width: 1_000, height: 800)
        let target = CandidateWindowPlacement.targetVisibleFrame(
            anchor: CGRect(x: 60, y: 300, width: 0, height: 20),
            visibleFrames: [left, right]
        )

        XCTAssertEqual(target, right)
    }

    func testExpandedWindowShowsUpToTwentySevenBeforeScrolling() {
        let twenty = CandidateWindowSizing.viewportSize(
            candidateCount: 20,
            mode: .expanded
        )
        let twentySeven = CandidateWindowSizing.viewportSize(
            candidateCount: 27,
            mode: .expanded
        )
        let twentyEight = CandidateWindowSizing.viewportSize(
            candidateCount: 28,
            mode: .expanded
        )

        XCTAssertEqual(twenty.height, twentySeven.height)
        XCTAssertEqual(twentyEight.height, twentySeven.height)
        XCTAssertEqual(
            twentyEight.width - twentySeven.width,
            CandidateWindowSizing.defaultScrollerThickness
        )
        let twentySevenDocument = CandidateWindowSizing.documentSize(
            candidateCount: 27,
            mode: .expanded
        )
        let twentyEightDocument = CandidateWindowSizing.documentSize(
            candidateCount: 28,
            mode: .expanded
        )
        XCTAssertEqual(
            CandidateWindowSizing.scrollAxes(
                documentSize: twentySevenDocument,
                viewportSize: twentySeven
            ),
            CandidateScrollAxes(horizontal: false, vertical: false)
        )
        XCTAssertEqual(
            CandidateWindowSizing.scrollAxes(
                documentSize: twentyEightDocument,
                viewportSize: twentyEight
            ),
            CandidateScrollAxes(horizontal: false, vertical: true)
        )
    }

    func testSmallScreenViewportEnablesEveryRequiredScrollAxis() {
        let document = CandidateWindowSizing.documentSize(
            candidateCount: 27,
            mode: .expanded
        )

        XCTAssertEqual(
            CandidateWindowSizing.scrollAxes(
                documentSize: document,
                viewportSize: CGSize(width: 300, height: 80)
            ),
            CandidateScrollAxes(horizontal: true, vertical: true)
        )
    }

    func testHorizontalScrollerCanRequireAVerticalScroller() {
        let document = CandidateWindowSizing.documentSize(
            candidateCount: 27,
            mode: .expanded
        )

        XCTAssertEqual(
            CandidateWindowSizing.scrollAxes(
                documentSize: document,
                viewportSize: CGSize(
                    width: document.width - 1,
                    height: document.height
                )
            ),
            CandidateScrollAxes(horizontal: true, vertical: true)
        )
    }

    func testVerticalScrollerCanRequireAHorizontalScroller() {
        let document = CandidateWindowSizing.documentSize(
            candidateCount: 27,
            mode: .expanded
        )

        XCTAssertEqual(
            CandidateWindowSizing.scrollAxes(
                documentSize: document,
                viewportSize: CGSize(
                    width: document.width,
                    height: document.height - 1
                )
            ),
            CandidateScrollAxes(horizontal: true, vertical: true)
        )
    }
}
