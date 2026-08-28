import Foundation

/// A release version made only of dot-separated non-negative integers.
///
/// Public releases use tags such as `v0.1.0`. Pre-release suffixes are
/// intentionally rejected because automatic checks only follow stable GitHub
/// releases.
struct AppVersion: Comparable, CustomStringConvertible, Equatable {
    let description: String
    private let components: [Int]

    init?(_ value: String) {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.first == "v" || normalized.first == "V" {
            normalized.removeFirst()
        }

        let pieces = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(pieces.count) else {
            return nil
        }

        var parsed: [Int] = []
        parsed.reserveCapacity(pieces.count)
        for piece in pieces {
            guard !piece.isEmpty,
                  piece.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let component = Int(piece) else {
                return nil
            }
            parsed.append(component)
        }

        description = parsed.map(String.init).joined(separator: ".")
        components = parsed
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}
