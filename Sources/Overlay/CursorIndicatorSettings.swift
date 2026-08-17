import AppKit

/// Where the indicator sits relative to the mouse cursor.
enum CursorIndicatorPlacement: String, CaseIterable, Codable {
    case upperRight
    case right
    case lowerRight

    var localizedName: String {
        switch self {
        case .upperRight:
            return "游標右上"
        case .right:
            return "游標右側"
        case .lowerRight:
            return "游標右下"
        }
    }
}

/// How the indicator keeps up with the cursor.
enum CursorIndicatorTracking: String, CaseIterable, Codable {
    /// Snap to the cursor on every sample.
    case fixedDistance
    /// Ease toward the cursor, which reads as a lighter, trailing follow.
    case followCursor

    var localizedName: String {
        switch self {
        case .fixedDistance:
            return "固定距離"
        case .followCursor:
            return "跟隨游標"
        }
    }
}

enum CursorIndicatorTextSize: String, CaseIterable, Codable {
    case small
    case medium
    case large
    case extraLarge
    case huge

    var localizedName: String {
        switch self {
        case .small:
            return "小"
        case .medium:
            return "中"
        case .large:
            return "大"
        case .extraLarge:
            return "特大"
        case .huge:
            return "極大"
        }
    }

    var style: CursorIndicatorStyle {
        switch self {
        case .small:
            return CursorIndicatorStyle(
                panelSize: NSSize(width: 18, height: 12),
                fontSize: 8
            )
        case .medium:
            return CursorIndicatorStyle(
                panelSize: NSSize(width: 24, height: 16),
                fontSize: 11
            )
        case .large:
            return CursorIndicatorStyle(
                panelSize: NSSize(width: 30, height: 20),
                fontSize: 14
            )
        case .extraLarge:
            return CursorIndicatorStyle(
                panelSize: NSSize(width: 42, height: 28),
                fontSize: 18
            )
        case .huge:
            return CursorIndicatorStyle(
                panelSize: NSSize(width: 56, height: 38),
                fontSize: 24
            )
        }
    }
}

enum CapsLockIndicatorSize: String, CaseIterable, Codable {
    case small
    case medium
    case large
    case extraLarge
    case huge

    var localizedName: String {
        switch self {
        case .small:
            return "小"
        case .medium:
            return "中"
        case .large:
            return "大"
        case .extraLarge:
            return "特大"
        case .huge:
            return "極大"
        }
    }

    var scale: CGFloat {
        switch self {
        case .small:
            return 0.55
        case .medium:
            return 0.7
        case .large:
            return 0.85
        case .extraLarge:
            return 1
        case .huge:
            return 1.25
        }
    }
}

/// The measured sizes one text size implies, including the Caps Lock badge.
struct CursorIndicatorStyle: Equatable {
    let panelSize: NSSize
    let fontSize: CGFloat

    func capsLockFontSize(for size: CapsLockIndicatorSize) -> CGFloat {
        max(6, fontSize * size.scale)
    }

    func capsLockBadgeGap(for size: CapsLockIndicatorSize) -> CGFloat {
        max(2, capsLockFontSize(for: size) * 0.25)
    }

    func capsLockBadgeWidth(for size: CapsLockIndicatorSize) -> CGFloat {
        max(8, capsLockFontSize(for: size))
    }

    func panelSize(withCapsLockBadge size: CapsLockIndicatorSize) -> NSSize {
        NSSize(
            width: panelSize.width
                + capsLockBadgeGap(for: size)
                + capsLockBadgeWidth(for: size),
            height: max(panelSize.height, ceil(capsLockFontSize(for: size) * 1.4))
        )
    }
}

/// Pure placement arithmetic, kept out of the panel so it can be tested
/// without a window server.
enum CursorIndicatorGeometry {
    static let horizontalGap: CGFloat = 8
    static let verticalGap: CGFloat = 2
    static let upperRightCenterOffset: CGFloat = 6
    static let rightVerticalAdjustment: CGFloat = -7
    static let trackingInterval: TimeInterval = 1.0 / 30.0
    static let followSmoothingFactor: CGFloat = 0.24

    static func origin(
        placement: CursorIndicatorPlacement,
        mouseLocation: NSPoint,
        panelSize: NSSize
    ) -> NSPoint {
        let x = mouseLocation.x + horizontalGap

        switch placement {
        case .upperRight:
            return NSPoint(
                x: x,
                y: mouseLocation.y - panelSize.height / 2 + upperRightCenterOffset
            )
        case .right:
            return NSPoint(
                x: x,
                y: mouseLocation.y - panelSize.height / 2 + rightVerticalAdjustment
            )
        case .lowerRight:
            return NSPoint(
                x: x,
                y: mouseLocation.y - panelSize.height - verticalGap
            )
        }
    }

    /// Keeps the panel inside the display holding the cursor. Coordinates are
    /// never assumed to start at zero, so negative-origin displays work.
    static func clampedOrigin(
        _ origin: NSPoint,
        panelSize: NSSize,
        mouseLocation: NSPoint,
        visibleFrames: [NSRect]
    ) -> NSPoint {
        let frame = visibleFrames.first { $0.contains(mouseLocation) }
            ?? visibleFrames.first
        guard let frame else {
            return origin
        }

        return NSPoint(
            x: min(max(origin.x, frame.minX), max(frame.minX, frame.maxX - panelSize.width)),
            y: min(max(origin.y, frame.minY), max(frame.minY, frame.maxY - panelSize.height))
        )
    }

    static func frame(
        placement: CursorIndicatorPlacement,
        mouseLocation: NSPoint,
        panelSize: NSSize,
        visibleFrames: [NSRect]
    ) -> NSRect {
        let unclamped = origin(
            placement: placement,
            mouseLocation: mouseLocation,
            panelSize: panelSize
        )
        return NSRect(
            origin: clampedOrigin(
                unclamped,
                panelSize: panelSize,
                mouseLocation: mouseLocation,
                visibleFrames: visibleFrames
            ),
            size: panelSize
        )
    }

    /// One easing step toward the target, used by the follow-cursor style.
    static func easedOrigin(
        from current: NSPoint,
        toward target: NSPoint,
        factor: CGFloat = followSmoothingFactor
    ) -> NSPoint {
        NSPoint(
            x: current.x + (target.x - current.x) * factor,
            y: current.y + (target.y - current.y) * factor
        )
    }
}
