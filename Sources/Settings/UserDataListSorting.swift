import Foundation

/// One row of the settings list, shared by the character and phrase tabs.
struct UserDataListRow: Equatable {
    enum Identity: Equatable {
        case character(text: String, pronunciation: String)
        case phrase(text: String, readings: [String])
    }

    let identity: Identity
    let text: String
    let reading: String
    let selectionCount: Int64
    let pinned: Bool

    var searchText: String {
        text + " " + reading
    }
}

enum UserDataListSortColumn: String {
    case text
    case reading
    case count
    case pinned

    var initialAscending: Bool {
        switch self {
        case .text, .reading:
            return true
        case .count, .pinned:
            return false
        }
    }
}

struct UserDataListSort: Equatable {
    let column: UserDataListSortColumn
    let ascending: Bool
}

enum UserDataListSorter {
    static func sorted(
        _ rows: [UserDataListRow],
        by sort: UserDataListSort?
    ) -> [UserDataListRow] {
        guard let sort else {
            return rows
        }

        return rows.enumerated().sorted { left, right in
            let comparison = compare(
                left.element,
                right.element,
                column: sort.column
            )
            if comparison == .orderedSame {
                // Preserve the store's existing order for equal values.
                return left.offset < right.offset
            }
            return sort.ascending
                ? comparison == .orderedAscending
                : comparison == .orderedDescending
        }.map(\.element)
    }

    private static func compare(
        _ left: UserDataListRow,
        _ right: UserDataListRow,
        column: UserDataListSortColumn
    ) -> ComparisonResult {
        switch column {
        case .text:
            return left.text.localizedStandardCompare(right.text)
        case .reading:
            return left.reading.localizedStandardCompare(right.reading)
        case .count:
            return compare(left.selectionCount, right.selectionCount)
        case .pinned:
            if left.pinned == right.pinned {
                return .orderedSame
            }
            return left.pinned ? .orderedDescending : .orderedAscending
        }
    }

    private static func compare<T: Comparable>(
        _ left: T,
        _ right: T
    ) -> ComparisonResult {
        if left < right {
            return .orderedAscending
        }
        if left > right {
            return .orderedDescending
        }
        return .orderedSame
    }
}
