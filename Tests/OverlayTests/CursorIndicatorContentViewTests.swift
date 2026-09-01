import AppKit
import XCTest

final class CursorIndicatorContentViewTests: XCTestCase {
    func testCompositionDotVisibilityAndAnimation() {
        let view = makeView(showsComposition: false)
        XCTAssertFalse(view.isCompositionDotVisible)
        XCTAssertFalse(view.isCompositionDotAnimating)

        update(view, showsComposition: true, animates: true)
        XCTAssertTrue(view.isCompositionDotVisible)
        XCTAssertTrue(view.isCompositionDotAnimating)

        update(view, showsComposition: true, animates: false)
        XCTAssertTrue(view.isCompositionDotVisible)
        XCTAssertFalse(view.isCompositionDotAnimating)
    }

    func testCompositionAndCapsLockDoNotOverlap() {
        let style = CursorIndicatorTextSize.large.style
        let size = style.panelSize(
            showsCompositionIndicator: true,
            capsLockSize: .huge
        )
        let view = CursorIndicatorContentView(
            frame: NSRect(origin: .zero, size: size)
        )
        view.apply(style: style, capsLockSize: .huge)
        update(
            view,
            showsComposition: true,
            animates: false,
            showsCapsLock: true
        )
        view.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(view.compositionDotFrame.width, 0)
        XCTAssertGreaterThan(view.capsLockFrame.width, 0)
        XCTAssertLessThanOrEqual(
            view.compositionDotFrame.maxX,
            view.capsLockFrame.minX
        )
        XCTAssertLessThanOrEqual(
            view.capsLockFrame.maxX,
            view.bounds.maxX + 0.001
        )
    }

    func testChangingCompositionColorUpdatesTheLayerImmediately() {
        let view = makeView(showsComposition: true)
        let purple = NSColor(
            srgbRed: 0.4,
            green: 0.2,
            blue: 0.6,
            alpha: 1
        )

        update(
            view,
            showsComposition: true,
            animates: false,
            compositionColor: purple
        )

        XCTAssertEqual(
            view.compositionDotColorHex,
            CursorIndicatorAppearance.hex(from: purple)
        )
    }

    private func makeView(showsComposition: Bool) -> CursorIndicatorContentView {
        let style = CursorIndicatorTextSize.large.style
        let view = CursorIndicatorContentView(
            frame: NSRect(
                origin: .zero,
                size: style.panelSize(
                    showsCompositionIndicator: showsComposition,
                    capsLockSize: nil
                )
            )
        )
        view.apply(style: style, capsLockSize: .extraLarge)
        update(view, showsComposition: showsComposition, animates: false)
        view.layoutSubtreeIfNeeded()
        return view
    }

    private func update(
        _ view: CursorIndicatorContentView,
        showsComposition: Bool,
        animates: Bool,
        showsCapsLock: Bool = false,
        compositionColor: NSColor = .systemGreen
    ) {
        view.update(
            text: "中",
            color: .systemRed,
            showsComposition: showsComposition,
            compositionColor: compositionColor,
            animatesComposition: animates,
            showsCapsLock: showsCapsLock
        )
    }
}
