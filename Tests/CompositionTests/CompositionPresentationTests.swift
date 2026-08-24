import AppKit
import Carbon
import XCTest

final class CompositionPresentationTests: XCTestCase {
    func testEmptyCompositionHasNoPresentation() {
        XCTAssertNil(
            CompositionPresentation.make(
                buffer: CompositionBuffer(),
                activeSuffix: nil
            )
        )
    }

    func testBufferCaretUsesUTF16TextEnd() {
        var buffer = CompositionBuffer()
        buffer.append(text: "𠮷", pronunciation: "ㄐㄧˊ")

        XCTAssertEqual(
            CompositionPresentation.make(
                buffer: buffer,
                activeSuffix: nil
            ),
            CompositionPresentation(
                text: "𠮷",
                selectionRange: NSRange(location: 2, length: 0)
            )
        )
    }

    func testBufferSelectionUsesItsUTF16Range() {
        var buffer = CompositionBuffer()
        buffer.append(text: "甲", pronunciation: "ㄐㄧㄚˇ")
        buffer.append(text: "𠮷", pronunciation: "ㄐㄧˊ")
        buffer.expandSelectionBackward()

        XCTAssertEqual(
            CompositionPresentation.make(
                buffer: buffer,
                activeSuffix: nil
            ),
            CompositionPresentation(
                text: "甲𠮷",
                selectionRange: NSRange(location: 1, length: 2)
            )
        )
    }

    func testActiveSuffixMovesCaretToWholeMarkedTextEnd() {
        var buffer = CompositionBuffer()
        buffer.append(text: "𠮷", pronunciation: "ㄐㄧˊ")
        buffer.expandSelectionBackward()

        XCTAssertEqual(
            CompositionPresentation.make(
                buffer: buffer,
                activeSuffix: "ㄨㄛˇ"
            ),
            CompositionPresentation(
                text: "𠮷ㄨㄛˇ",
                selectionRange: NSRange(location: 5, length: 0)
            )
        )
    }

    func testActiveReadingStaysBeforeItsOriginalInsertionAnchor() throws {
        var buffer = CompositionBuffer()
        let anchor = try XCTUnwrap(
            buffer.append(text: "鏡", pronunciation: "ㄐㄧㄥˋ")
        )

        XCTAssertEqual(
            CompositionPresentation.make(
                buffer: buffer,
                activeSuffix: "ㄌㄨ",
                insertionAnchorUnitID: anchor.id
            ),
            CompositionPresentation(
                text: "ㄌㄨ鏡",
                selectionRange: NSRange(location: 2, length: 0)
            )
        )
    }

    func testEmptyEditedReadingKeepsCaretAtItsOriginalAnchor() throws {
        var buffer = CompositionBuffer()
        let anchor = try XCTUnwrap(
            buffer.append(text: "鏡", pronunciation: "ㄐㄧㄥˋ")
        )

        XCTAssertEqual(
            CompositionPresentation.make(
                buffer: buffer,
                activeSuffix: nil,
                insertionAnchorUnitID: anchor.id
            ),
            CompositionPresentation(
                text: "鏡",
                selectionRange: NSRange(location: 0, length: 0)
            )
        )
    }

    func testRevisionFocusPlacesCaretBeforeExistingUnit() throws {
        var buffer = CompositionBuffer()
        buffer.append(text: "測", pronunciation: "ㄘㄜˋ")
        buffer.append(text: "𐍈", pronunciation: "ㄐㄧˊ")
        let focusedID = try XCTUnwrap(buffer.units.last?.id)

        XCTAssertEqual(
            CompositionPresentation.make(
                buffer: buffer,
                activeSuffix: nil,
                focusedUnitID: focusedID
            ),
            CompositionPresentation(
                text: "測𐍈",
                selectionRange: NSRange(location: 1, length: 0)
            )
        )
    }

    func testActiveSuffixTakesPriorityOverRevisionFocus() throws {
        var buffer = CompositionBuffer()
        buffer.append(text: "測", pronunciation: "ㄘㄜˋ")
        let focusedID = try XCTUnwrap(buffer.units.first?.id)

        XCTAssertEqual(
            CompositionPresentation.make(
                buffer: buffer,
                activeSuffix: "ㄕˋ",
                focusedUnitID: focusedID
            ),
            CompositionPresentation(
                text: "測ㄕˋ",
                selectionRange: NSRange(location: 3, length: 0)
            )
        )
    }

    func testEmptySuffixIsEquivalentToNoSuffix() {
        var buffer = CompositionBuffer()
        buffer.append(text: "我", pronunciation: "ㄨㄛˇ")
        buffer.expandSelectionBackward()

        XCTAssertEqual(
            CompositionPresentation.make(
                buffer: buffer,
                activeSuffix: ""
            ),
            CompositionPresentation.make(
                buffer: buffer,
                activeSuffix: nil
            )
        )
    }

    func testInlineCharacterCandidatePreviewDoesNotMutateBuffer() {
        let buffer = CompositionBuffer()
        let candidate = Candidate(text: "我", pronunciation: "ㄨㄛˇ")

        XCTAssertEqual(
            CompositionPresentation.make(
                buffer: buffer,
                previewing: candidate
            ),
            CompositionPresentation(
                text: "我",
                selectionRange: NSRange(location: 1, length: 0)
            )
        )
        XCTAssertTrue(buffer.isEmpty)
    }

    func testInlinePhraseCandidatePreviewReplacesOnlyCopiedSuffix() {
        var buffer = CompositionBuffer()
        XCTAssertNotNil(buffer.append(text: "冊", pronunciation: "ㄘㄜˋ"))
        let phrase = Candidate(
            text: "測試",
            pronunciationSequence: ["ㄘㄜˋ", "ㄕˋ"],
            type: .phrase
        )

        XCTAssertEqual(
            CompositionPresentation.make(
                buffer: buffer,
                previewing: phrase
            )?.text,
            "測試"
        )
        XCTAssertEqual(buffer.text, "冊")
    }

    func testMarkedTextRendererStylesOnlyThePhraseUTF16Range() throws {
        let presentation = CompositionPresentation(
            text: "A𐍈測",
            selectionRange: NSRange(location: 1, length: 2)
        )

        let rendered = CompositionMarkedTextRenderer.make(
            presentation: presentation,
            highlightedRange: presentation.selectionRange
        )

        XCTAssertNil(rendered.attribute(.backgroundColor, at: 0, effectiveRange: nil))
        XCTAssertNotNil(rendered.attribute(.backgroundColor, at: 1, effectiveRange: nil))
        XCTAssertEqual(
            rendered.attribute(.underlineStyle, at: 1, effectiveRange: nil) as? Int,
            NSUnderlineStyle.thick.rawValue
        )
        XCTAssertNil(rendered.attribute(.backgroundColor, at: 3, effectiveRange: nil))
    }

    func testRevisionMarkedTextSuppressesDefaultFillAndUnderline() {
        let presentation = CompositionPresentation(
            text: "路鏡",
            selectionRange: NSRange(location: 1, length: 0)
        )

        let rendered = CompositionMarkedTextRenderer.makeUnhighlighted(
            presentation: presentation
        )

        for index in 0 ..< rendered.length {
            XCTAssertEqual(
                rendered.attribute(
                    .backgroundColor,
                    at: index,
                    effectiveRange: nil
                ) as? NSColor,
                NSColor.clear
            )
            XCTAssertEqual(
                rendered.attribute(
                    .underlineStyle,
                    at: index,
                    effectiveRange: nil
                ) as? Int,
                0
            )
            XCTAssertEqual(
                rendered.attribute(
                    .markedClauseSegment,
                    at: index,
                    effectiveRange: nil
                ) as? Int,
                Int(kTSMHiliteNoHilite)
            )
        }
        XCTAssertEqual(
            presentation.selectionRange,
            NSRange(location: 1, length: 0)
        )
    }

    func testMarkedTextRendererIgnoresInvalidOrMissingFocus() {
        let presentation = CompositionPresentation(
            text: "測試",
            selectionRange: NSRange(location: 2, length: 0)
        )

        for focusedRange in [
            nil,
            NSRange(location: 2, length: 0),
            NSRange(location: 2, length: 1),
        ] {
            let rendered = CompositionMarkedTextRenderer.make(
                presentation: presentation,
                highlightedRange: focusedRange
            )
            XCTAssertEqual(rendered.string, "測試")
            XCTAssertEqual(rendered.length, 2)
            XCTAssertTrue(rendered.attributes(at: 0, effectiveRange: nil).isEmpty)
        }
    }

    func testPhraseRendererStylesRangeAndKeepsClientCaretCollapsed() {
        let presentation = CompositionPresentation(
            text: "一載入",
            selectionRange: NSRange(location: 1, length: 2)
        )

        let rendered = CompositionMarkedTextRenderer.make(
            presentation: presentation,
            highlightedRange: presentation.selectionRange
        )

        XCTAssertNil(
            rendered.attribute(.backgroundColor, at: 0, effectiveRange: nil)
        )
        XCTAssertEqual(
            rendered.attribute(.backgroundColor, at: 1, effectiveRange: nil)
                as? NSColor,
            NSColor.selectedTextBackgroundColor
        )
        XCTAssertNotNil(
            rendered.attribute(.foregroundColor, at: 2, effectiveRange: nil)
        )
        XCTAssertEqual(
            rendered.attribute(.underlineStyle, at: 2, effectiveRange: nil)
                as? Int,
            NSUnderlineStyle.thick.rawValue
        )
        XCTAssertEqual(
            presentation.caretAfterSelectionRange,
            NSRange(location: 3, length: 0)
        )
    }
}
