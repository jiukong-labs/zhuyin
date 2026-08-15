import CoreGraphics

struct CandidateScrollAxes: Equatable {
    let horizontal: Bool
    let vertical: Bool
}

enum CandidateWindowSizing {
    static let contentInset: CGFloat = 8
    static let cellWidth: CGFloat = 64
    static let cellHeight: CGFloat = 38
    static let cellSpacing: CGFloat = 4
    static let defaultScrollerThickness: CGFloat = 17

    static func viewportSize(
        candidateCount: Int,
        mode: CandidatePresentationMode,
        scrollerThickness: CGFloat = defaultScrollerThickness
    ) -> CGSize {
        let count = max(1, candidateCount)

        switch mode {
        case .compact:
            let columns = min(count, CandidateSession.selectionPageSize)
            return size(columns: columns, rows: 1, scrollerThickness: 0)
        case .expanded:
            let columns = min(count, CandidateSession.expandedColumnCount)
            let visibleCount = min(
                count,
                CandidateSession.expandedVisibleCandidateCount
            )
            let rows = rowCount(itemCount: visibleCount, columns: columns)
            return size(
                columns: columns,
                rows: rows,
                scrollerThickness: count
                    > CandidateSession.expandedVisibleCandidateCount
                    ? scrollerThickness
                    : 0
            )
        }
    }

    static func documentSize(
        candidateCount: Int,
        mode: CandidatePresentationMode
    ) -> CGSize {
        let count = max(1, candidateCount)

        switch mode {
        case .compact:
            let columns = min(count, CandidateSession.selectionPageSize)
            return size(columns: columns, rows: 1, scrollerThickness: 0)
        case .expanded:
            let columns = min(count, CandidateSession.expandedColumnCount)
            let rows = rowCount(itemCount: count, columns: columns)
            return size(columns: columns, rows: rows, scrollerThickness: 0)
        }
    }

    static func scrollAxes(
        documentSize: CGSize,
        viewportSize: CGSize,
        scrollerThickness: CGFloat = defaultScrollerThickness
    ) -> CandidateScrollAxes {
        var axes = CandidateScrollAxes(
            horizontal: documentSize.width > viewportSize.width + 0.5,
            vertical: documentSize.height > viewportSize.height + 0.5
        )

        while true {
            let availableSize = CGSize(
                width: max(
                    0,
                    viewportSize.width
                        - (axes.vertical ? scrollerThickness : 0)
                ),
                height: max(
                    0,
                    viewportSize.height
                        - (axes.horizontal ? scrollerThickness : 0)
                )
            )
            let updatedAxes = CandidateScrollAxes(
                horizontal: axes.horizontal
                    || documentSize.width > availableSize.width + 0.5,
                vertical: axes.vertical
                    || documentSize.height > availableSize.height + 0.5
            )

            if updatedAxes == axes {
                return axes
            }
            axes = updatedAxes
        }
    }

    static func rowCount(itemCount: Int, columns: Int) -> Int {
        guard itemCount > 0, columns > 0 else {
            return 0
        }

        return (itemCount + columns - 1) / columns
    }

    private static func size(
        columns: Int,
        rows: Int,
        scrollerThickness: CGFloat
    ) -> CGSize {
        let horizontalSpacing = CGFloat(max(0, columns - 1)) * cellSpacing
        let verticalSpacing = CGFloat(max(0, rows - 1)) * cellSpacing
        return CGSize(
            width: (2 * contentInset)
                + (CGFloat(columns) * cellWidth)
                + horizontalSpacing
                + scrollerThickness,
            height: (2 * contentInset)
                + (CGFloat(rows) * cellHeight)
                + verticalSpacing
        )
    }
}

enum CandidateWindowPlacement {
    static func frame(
        anchor: CGRect,
        desiredSize: CGSize,
        visibleFrames: [CGRect],
        gap: CGFloat = 6,
        margin: CGFloat = 8
    ) -> CGRect {
        guard let visibleFrame = targetVisibleFrame(
            anchor: anchor,
            visibleFrames: visibleFrames
        ) else {
            return CGRect(origin: anchor.origin, size: desiredSize)
        }

        let insetFrame = visibleFrame.insetBy(dx: margin, dy: margin)
        let safeFrame = insetFrame.width > 0 && insetFrame.height > 0
            ? insetFrame
            : visibleFrame
        let size = CGSize(
            width: min(max(1, desiredSize.width), safeFrame.width),
            height: min(max(1, desiredSize.height), safeFrame.height)
        )

        let x = clamp(
            anchor.minX,
            minimum: safeFrame.minX,
            maximum: safeFrame.maxX - size.width
        )
        let belowY = anchor.minY - gap - size.height
        let aboveY = anchor.maxY + gap
        let y: CGFloat

        if belowY >= safeFrame.minY {
            y = belowY
        } else if aboveY + size.height <= safeFrame.maxY {
            y = aboveY
        } else {
            let spaceBelow = max(0, anchor.minY - gap - safeFrame.minY)
            let spaceAbove = max(0, safeFrame.maxY - anchor.maxY - gap)
            let preferredY = spaceAbove > spaceBelow ? aboveY : belowY
            y = clamp(
                preferredY,
                minimum: safeFrame.minY,
                maximum: safeFrame.maxY - size.height
            )
        }

        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    static func targetVisibleFrame(
        anchor: CGRect,
        visibleFrames: [CGRect]
    ) -> CGRect? {
        guard !visibleFrames.isEmpty else {
            return nil
        }

        let anchorPoint = CGPoint(x: anchor.midX, y: anchor.midY)
        if let containingFrame = visibleFrames.first(where: {
            $0.contains(anchorPoint)
        }) {
            return containingFrame
        }

        return visibleFrames.min {
            squaredDistance(from: anchorPoint, to: $0)
                < squaredDistance(from: anchorPoint, to: $1)
        }
    }

    private static func squaredDistance(
        from point: CGPoint,
        to rect: CGRect
    ) -> CGFloat {
        let nearestX = clamp(
            point.x,
            minimum: rect.minX,
            maximum: rect.maxX
        )
        let nearestY = clamp(
            point.y,
            minimum: rect.minY,
            maximum: rect.maxY
        )
        let dx = point.x - nearestX
        let dy = point.y - nearestY
        return (dx * dx) + (dy * dy)
    }

    private static func clamp(
        _ value: CGFloat,
        minimum: CGFloat,
        maximum: CGFloat
    ) -> CGFloat {
        guard maximum >= minimum else {
            return minimum
        }

        return min(max(value, minimum), maximum)
    }
}
