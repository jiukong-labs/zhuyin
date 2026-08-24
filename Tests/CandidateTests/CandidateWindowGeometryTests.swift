import CoreGraphics
import CoreText
import XCTest

final class CandidateWindowGeometryTests: XCTestCase {
    func testLastResortFontIsRecognizedAsMissingGlyphFallback() {
        let lastResort = CTFontCreateWithName(
            "LastResort" as CFString,
            18,
            nil
        )
        let ordinaryFont = CTFontCreateWithName(
            "Helvetica" as CFString,
            18,
            nil
        )

        XCTAssertTrue(CandidateTextDisplayability.isLastResort(lastResort))
        XCTAssertFalse(CandidateTextDisplayability.isLastResort(ordinaryFont))
    }

    func testRejectsCaretRectPinnedToScreenOrigin() {
        XCTAssertFalse(
            CandidateAnchorValidation.isPlausibleCaretAnchor(
                CGRect(x: 0, y: 0, width: 0, height: 16)
            )
        )
        XCTAssertFalse(
            CandidateAnchorValidation.isPlausibleCaretAnchor(
                CGRect(x: 1, y: -1, width: 40, height: 16)
            )
        )
    }

    func testRejectsNonFiniteOrEmptyCaretRects() {
        XCTAssertFalse(
            CandidateAnchorValidation.isPlausibleCaretAnchor(
                CGRect(x: CGFloat.nan, y: 500, width: 40, height: 16)
            )
        )
        XCTAssertFalse(
            CandidateAnchorValidation.isPlausibleCaretAnchor(
                CGRect(x: 100, y: 500, width: 40, height: 0)
            )
        )
    }

    func testAcceptsOrdinaryAndNegativeOriginCaretRects() {
        XCTAssertTrue(
            CandidateAnchorValidation.isPlausibleCaretAnchor(
                CGRect(x: 100, y: 500, width: 1, height: 20)
            )
        )
        // Negative-origin displays are supported, so a caret on a monitor
        // placed to the left of or below the primary display must not be
        // mistaken for the near-origin stub rect.
        XCTAssertTrue(
            CandidateAnchorValidation.isPlausibleCaretAnchor(
                CGRect(x: -1_500, y: -300, width: 1, height: 20)
            )
        )
    }

    func testQueriesEditedGlyphBeforeItsTrailingCaret() {
        XCTAssertEqual(
            CandidateAnchorRanges.requestedRanges(
                markedRange: NSRange(location: 100, length: 11),
                localAnchorRange: NSRange(location: 8, length: 1)
            ),
            [
                NSRange(location: 108, length: 1),
                NSRange(location: 109, length: 0)
            ]
        )
    }

    func testRejectsAnchorRangeOutsideMarkedComposition() {
        XCTAssertTrue(
            CandidateAnchorRanges.requestedRanges(
                markedRange: NSRange(location: 100, length: 11),
                localAnchorRange: NSRange(location: 11, length: 1)
            ).isEmpty
        )
    }

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

    func testShrinksConstrainedWindowInsteadOfCoveringEditedText() {
        let anchor = CGRect(x: 100, y: 140, width: 20, height: 20)
        let frame = CandidateWindowPlacement.frame(
            anchor: anchor,
            desiredSize: CGSize(width: 300, height: 200),
            visibleFrames: [CGRect(x: 0, y: 0, width: 1_000, height: 300)]
        )

        XCTAssertEqual(frame, CGRect(x: 100, y: 8, width: 300, height: 126))
        XCTAssertLessThanOrEqual(frame.maxY, anchor.minY - 6)
        XCTAssertFalse(frame.intersects(anchor))
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

    func testCapsOversizedWindowWithoutCoveringCaret() {
        let anchor = CGRect(x: 500, y: 400, width: 1, height: 20)
        let frame = CandidateWindowPlacement.frame(
            anchor: anchor,
            desiredSize: CGSize(width: 2_000, height: 2_000),
            visibleFrames: [CGRect(x: 0, y: 0, width: 1_000, height: 800)]
        )

        XCTAssertEqual(frame, CGRect(x: 8, y: 8, width: 984, height: 386))
        XCTAssertLessThanOrEqual(frame.maxY, anchor.minY - 6)
        XCTAssertFalse(frame.intersects(anchor))
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

    func testLongPhraseGetsAWiderNonOverlappingCandidateCell() {
        let metrics = CandidateWindowSizing.gridMetrics(
            candidateTexts: ["測試中請稍後", "后"],
            mode: .compact
        )

        XCTAssertEqual(metrics.cellFrames.count, 2)
        XCTAssertGreaterThan(
            metrics.cellFrames[0].width,
            metrics.cellFrames[1].width
        )
        XCTAssertEqual(
            metrics.cellFrames[1].minX,
            metrics.cellFrames[0].maxX + CandidateWindowSizing.cellSpacing
        )
        XCTAssertGreaterThanOrEqual(
            metrics.cellFrames[0].width,
            CandidateWindowSizing.cellWidth(for: "測試中請稍後")
        )
    }

    func testTextAwareViewportIncludesTheLongPhraseWidth() {
        let short = CandidateWindowSizing.viewportSize(
            candidateTexts: ["后", "厚"],
            mode: .compact
        )
        let long = CandidateWindowSizing.viewportSize(
            candidateTexts: ["測試中請稍後", "厚"],
            mode: .compact
        )

        XCTAssertGreaterThan(long.width, short.width)
        XCTAssertEqual(long.height, short.height)
    }

    func testRevisionHeaderExpandsPanelAndLeavesCandidateViewportSeparate() {
        let candidateSize = CGSize(width: 300, height: 54)
        let panelSize = CandidateWindowSizing.panelSize(
            candidateViewportSize: candidateSize,
            revisionHeaderContentWidth: 340
        )

        XCTAssertEqual(panelSize.width, 356)
        XCTAssertEqual(
            panelSize.height,
            candidateSize.height + CandidateWindowSizing.revisionHeaderHeight
        )
        XCTAssertEqual(
            CandidateWindowSizing.candidateViewportSize(
                panelSize: panelSize,
                showsRevisionHeader: true
            ),
            CGSize(width: 356, height: 54)
        )
        XCTAssertEqual(
            CandidateWindowSizing.panelSize(
                candidateViewportSize: candidateSize,
                revisionHeaderContentWidth: nil
            ),
            candidateSize
        )
    }

    func testPhraseStatusPanelHasOneHeaderRowAndExpandsForItsText() {
        XCTAssertEqual(
            CandidateWindowSizing.phraseStatusPanelSize(contentWidth: 100),
            CGSize(
                width: CandidateWindowSizing.phraseStatusMinimumWidth,
                height: CandidateWindowSizing.revisionHeaderHeight
            )
        )
        XCTAssertEqual(
            CandidateWindowSizing.phraseStatusPanelSize(contentWidth: 400),
            CGSize(
                width: 400 + (2 * CandidateWindowSizing.contentInset),
                height: CandidateWindowSizing.revisionHeaderHeight
            )
        )
    }

    func testSavedPhraseConfirmationReservesDeleteButton() {
        XCTAssertEqual(
            CandidateWindowSizing.savedPhraseConfirmationPanelSize(
                contentWidth: 400
            ),
            CGSize(
                width: 400
                    + CandidateWindowSizing.savedPhraseActionGap
                    + CandidateWindowSizing.savedPhraseActionButtonWidth
                    + (2 * CandidateWindowSizing.contentInset),
                height: CandidateWindowSizing.revisionHeaderHeight
            )
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
