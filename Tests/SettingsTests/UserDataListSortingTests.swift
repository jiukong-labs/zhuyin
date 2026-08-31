import XCTest

final class UserDataListSortingTests: XCTestCase {
    func testNoSortPreservesStoreOrder() {
        let rows = [
            row(text: "B", reading: "2", count: 1, pinned: false),
            row(text: "A", reading: "1", count: 2, pinned: true),
        ]

        XCTAssertEqual(
            UserDataListSorter.sorted(rows, by: nil).map(\.text),
            ["B", "A"]
        )
    }

    func testTextAndReadingSortInBothDirections() {
        let rows = [
            row(text: "B", reading: "1", count: 1, pinned: false),
            row(text: "A", reading: "2", count: 1, pinned: false),
        ]

        XCTAssertEqual(
            sortedTexts(rows, column: .text, ascending: true),
            ["A", "B"]
        )
        XCTAssertEqual(
            sortedTexts(rows, column: .text, ascending: false),
            ["B", "A"]
        )
        XCTAssertEqual(
            sortedTexts(rows, column: .reading, ascending: true),
            ["B", "A"]
        )
        XCTAssertEqual(
            sortedTexts(rows, column: .reading, ascending: false),
            ["A", "B"]
        )
    }

    func testCountSortsNumericallyAndKeepsTiesStable() {
        let rows = [
            row(text: "first", reading: "", count: 5, pinned: false),
            row(text: "highest", reading: "", count: 12, pinned: false),
            row(text: "second", reading: "", count: 5, pinned: false),
        ]

        XCTAssertEqual(
            sortedTexts(rows, column: .count, ascending: false),
            ["highest", "first", "second"]
        )
        XCTAssertEqual(
            sortedTexts(rows, column: .count, ascending: true),
            ["first", "second", "highest"]
        )
    }

    func testPinnedSortPlacesPinnedRowsFirstByDefaultDirection() {
        let rows = [
            row(text: "normal", reading: "", count: 1, pinned: false),
            row(text: "pinned", reading: "", count: 1, pinned: true),
        ]

        XCTAssertFalse(UserDataListSortColumn.pinned.initialAscending)
        XCTAssertEqual(
            sortedTexts(rows, column: .pinned, ascending: false),
            ["pinned", "normal"]
        )
        XCTAssertEqual(
            sortedTexts(rows, column: .pinned, ascending: true),
            ["normal", "pinned"]
        )
    }

    private func sortedTexts(
        _ rows: [UserDataListRow],
        column: UserDataListSortColumn,
        ascending: Bool
    ) -> [String] {
        UserDataListSorter.sorted(
            rows,
            by: UserDataListSort(column: column, ascending: ascending)
        ).map(\.text)
    }

    private func row(
        text: String,
        reading: String,
        count: Int64,
        pinned: Bool
    ) -> UserDataListRow {
        UserDataListRow(
            identity: .character(text: text, pronunciation: reading),
            text: text,
            reading: reading,
            selectionCount: count,
            pinned: pinned
        )
    }
}
