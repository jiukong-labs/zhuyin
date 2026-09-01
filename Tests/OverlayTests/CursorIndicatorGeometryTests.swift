import AppKit
import XCTest

final class CursorIndicatorGeometryTests: XCTestCase {
    private let screen = NSRect(x: 0, y: 0, width: 1_000, height: 800)

    func testEveryPlacementSitsToTheRightOfTheCursor() {
        let mouse = NSPoint(x: 400, y: 400)
        let size = NSSize(width: 20, height: 14)

        for placement in CursorIndicatorPlacement.allCases {
            let origin = CursorIndicatorGeometry.origin(
                placement: placement,
                mouseLocation: mouse,
                panelSize: size
            )
            XCTAssertEqual(
                origin.x,
                mouse.x + CursorIndicatorGeometry.horizontalGap,
                "\(placement)"
            )
        }
    }

    func testPlacementsAreOrderedFromUpperToLower() {
        let mouse = NSPoint(x: 400, y: 400)
        let size = NSSize(width: 20, height: 14)
        let heights = CursorIndicatorPlacement.allCases.map { placement in
            CursorIndicatorGeometry.origin(
                placement: placement,
                mouseLocation: mouse,
                panelSize: size
            ).y
        }

        XCTAssertEqual(heights, heights.sorted(by: >))
    }

    func testLowerRightKeepsThePanelBelowTheCursor() {
        let mouse = NSPoint(x: 100, y: 500)
        let size = NSSize(width: 20, height: 14)

        let origin = CursorIndicatorGeometry.origin(
            placement: .lowerRight,
            mouseLocation: mouse,
            panelSize: size
        )

        XCTAssertEqual(origin.y + size.height, mouse.y - CursorIndicatorGeometry.verticalGap)
    }

    func testPanelIsClampedInsideTheDisplayHoldingTheCursor() {
        let size = NSSize(width: 40, height: 30)

        let atRightEdge = CursorIndicatorGeometry.frame(
            placement: .right,
            mouseLocation: NSPoint(x: 995, y: 400),
            panelSize: size,
            visibleFrames: [screen]
        )
        let atBottomEdge = CursorIndicatorGeometry.frame(
            placement: .lowerRight,
            mouseLocation: NSPoint(x: 400, y: 4),
            panelSize: size,
            visibleFrames: [screen]
        )

        XCTAssertEqual(atRightEdge.maxX, screen.maxX)
        XCTAssertEqual(atBottomEdge.minY, screen.minY)
        XCTAssertTrue(screen.contains(atRightEdge))
        XCTAssertTrue(screen.contains(atBottomEdge))
    }

    func testNegativeOriginDisplaysAreSupported() {
        let secondary = NSRect(x: -1_600, y: -200, width: 1_600, height: 1_000)
        let size = NSSize(width: 40, height: 30)

        let frame = CursorIndicatorGeometry.frame(
            placement: .lowerRight,
            mouseLocation: NSPoint(x: -1_598, y: -195),
            panelSize: size,
            visibleFrames: [screen, secondary]
        )

        XCTAssertTrue(secondary.contains(frame))
        XCTAssertEqual(frame.minY, secondary.minY)
    }

    func testCursorOutsideEveryDisplayFallsBackWithoutCrashing() {
        let frame = CursorIndicatorGeometry.frame(
            placement: .right,
            mouseLocation: NSPoint(x: 5_000, y: 5_000),
            panelSize: NSSize(width: 40, height: 30),
            visibleFrames: [screen]
        )

        XCTAssertTrue(screen.contains(frame))
    }

    func testNoDisplaysLeavesTheOriginUntouched() {
        let mouse = NSPoint(x: 10, y: 10)
        let size = NSSize(width: 40, height: 30)

        let frame = CursorIndicatorGeometry.frame(
            placement: .right,
            mouseLocation: mouse,
            panelSize: size,
            visibleFrames: []
        )

        XCTAssertEqual(
            frame.origin,
            CursorIndicatorGeometry.origin(
                placement: .right,
                mouseLocation: mouse,
                panelSize: size
            )
        )
    }

    func testEasingMovesTowardTheTargetWithoutOvershooting() {
        let current = NSPoint(x: 0, y: 0)
        let target = NSPoint(x: 100, y: 200)

        let stepped = CursorIndicatorGeometry.easedOrigin(
            from: current,
            toward: target
        )

        XCTAssertGreaterThan(stepped.x, current.x)
        XCTAssertLessThan(stepped.x, target.x)
        XCTAssertEqual(
            stepped.x,
            target.x * CursorIndicatorGeometry.followSmoothingFactor,
            accuracy: 0.0001
        )
    }

    func testRepeatedEasingConvergesOnTheTarget() {
        var origin = NSPoint(x: 0, y: 0)
        let target = NSPoint(x: 300, y: 300)

        for _ in 0 ..< 100 {
            origin = CursorIndicatorGeometry.easedOrigin(
                from: origin,
                toward: target
            )
        }

        XCTAssertEqual(origin.x, target.x, accuracy: 0.5)
        XCTAssertEqual(origin.y, target.y, accuracy: 0.5)
    }

    func testTextSizesGrowMonotonically() {
        let sizes = CursorIndicatorTextSize.allCases.map(\.style)

        XCTAssertEqual(sizes.map(\.fontSize), sizes.map(\.fontSize).sorted())
        XCTAssertEqual(
            sizes.map(\.panelSize.width),
            sizes.map(\.panelSize.width).sorted()
        )
    }

    func testCapsLockBadgeWidensThePanelAndNeverShrinksIt() {
        for textSize in CursorIndicatorTextSize.allCases {
            let style = textSize.style
            for capsSize in CapsLockIndicatorSize.allCases {
                let widened = style.panelSize(withCapsLockBadge: capsSize)

                XCTAssertGreaterThan(
                    widened.width,
                    style.panelSize.width,
                    "\(textSize) \(capsSize)"
                )
                XCTAssertGreaterThanOrEqual(
                    widened.height,
                    style.panelSize.height,
                    "\(textSize) \(capsSize)"
                )
                XCTAssertGreaterThanOrEqual(
                    style.capsLockFontSize(for: capsSize),
                    6
                )
            }
        }
    }

    func testCapsLockSizesScaleInOrder() {
        let style = CursorIndicatorTextSize.large.style
        let fontSizes = CapsLockIndicatorSize.allCases.map {
            style.capsLockFontSize(for: $0)
        }

        XCTAssertEqual(fontSizes, fontSizes.sorted())
    }

    func testCompositionDotAndCapsLockReserveIndependentSpace() {
        for textSize in CursorIndicatorTextSize.allCases {
            let style = textSize.style
            let dotOnly = style.panelSize(
                showsCompositionIndicator: true,
                capsLockSize: nil
            )
            let both = style.panelSize(
                showsCompositionIndicator: true,
                capsLockSize: .extraLarge
            )

            XCTAssertGreaterThan(dotOnly.width, style.panelSize.width)
            XCTAssertGreaterThan(both.width, dotOnly.width)
            XCTAssertGreaterThanOrEqual(dotOnly.height, style.panelSize.height)
            XCTAssertGreaterThanOrEqual(style.compositionDotDiameter, 3)
        }
    }

    func testReduceMotionAndDisabledPreferenceUseStaticDot() {
        XCTAssertTrue(
            CompositionIndicatorAnimationPolicy.shouldAnimate(
                preferenceEnabled: true,
                reduceMotionEnabled: false
            )
        )
        XCTAssertFalse(
            CompositionIndicatorAnimationPolicy.shouldAnimate(
                preferenceEnabled: false,
                reduceMotionEnabled: false
            )
        )
        XCTAssertFalse(
            CompositionIndicatorAnimationPolicy.shouldAnimate(
                preferenceEnabled: true,
                reduceMotionEnabled: true
            )
        )
    }
}
