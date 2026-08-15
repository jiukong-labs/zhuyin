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
}
