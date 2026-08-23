import AppKit
import CoreGraphics
import CoreText

/// Rejects text for which macOS can only supply its LastResort missing-glyph
/// font. Real fallback fonts remain valid, so uncommon characters are kept
/// whenever this Mac can actually draw them.
enum CandidateTextDisplayability {
    private static let cache = NSCache<NSString, NSNumber>()

    static func canRender(_ text: String) -> Bool {
        guard !text.isEmpty else {
            return false
        }
        let key = text as NSString
        if let cached = cache.object(forKey: key) {
            return cached.boolValue
        }

        let baseFont = NSFont.systemFont(
            ofSize: 18,
            weight: .medium
        ) as CTFont
        let renderable = composedCharacterSequences(in: key).allSatisfy {
            sequence in
            let fallback = CTFontCreateForString(
                baseFont,
                sequence as CFString,
                CFRange(
                    location: 0,
                    length: (sequence as NSString).length
                )
            )
            return !isLastResort(fallback)
        }
        cache.setObject(NSNumber(value: renderable), forKey: key)
        return renderable
    }

    static func isLastResort(_ font: CTFont) -> Bool {
        let postScriptName = CTFontCopyPostScriptName(font) as String
        let familyName = CTFontCopyFamilyName(font) as String
        return postScriptName.localizedCaseInsensitiveContains("LastResort")
            || familyName.localizedCaseInsensitiveContains("LastResort")
            || familyName.localizedCaseInsensitiveContains("Last Resort")
    }

    private static func composedCharacterSequences(
        in text: NSString
    ) -> [String] {
        var result: [String] = []
        var location = 0
        while location < text.length {
            let range = text.rangeOfComposedCharacterSequence(at: location)
            result.append(text.substring(with: range))
            location = NSMaxRange(range)
        }
        return result
    }
}

struct CandidateScrollAxes: Equatable {
    let horizontal: Bool
    let vertical: Bool
}

struct CandidateGridMetrics: Equatable {
    let cellFrames: [CGRect]
    let documentSize: CGSize
}

enum CandidateWindowSizing {
    static let contentInset: CGFloat = 8
    static let cellWidth: CGFloat = 64
    static let cellHeight: CGFloat = 38
    static let cellSpacing: CGFloat = 4
    static let defaultScrollerThickness: CGFloat = 17
    static let revisionHeaderHeight: CGFloat = 38
    static let phraseStatusMinimumWidth: CGFloat = 280
    static let savedPhraseActionButtonWidth: CGFloat = 28
    static let savedPhraseActionGap: CGFloat = 6

    static func phraseStatusPanelSize(contentWidth: CGFloat) -> CGSize {
        CGSize(
            width: max(
                phraseStatusMinimumWidth,
                contentWidth + (2 * contentInset)
            ),
            height: revisionHeaderHeight
        )
    }

    static func savedPhraseConfirmationPanelSize(
        contentWidth: CGFloat
    ) -> CGSize {
        phraseStatusPanelSize(
            contentWidth: contentWidth
                + savedPhraseActionGap
                + savedPhraseActionButtonWidth
        )
    }

    static func cellWidth(for candidateText: String) -> CGFloat {
        min(
            320,
            max(cellWidth, 24 + CGFloat(candidateText.count + 2) * 20)
        )
    }

    static func gridMetrics(
        candidateTexts: [String],
        mode: CandidatePresentationMode
    ) -> CandidateGridMetrics {
        let itemCount = max(1, candidateTexts.count)
        let columnCount: Int
        switch mode {
        case .compact:
            columnCount = itemCount
        case .expanded:
            columnCount = min(itemCount, CandidateSession.expandedColumnCount)
        }
        let rows = rowCount(itemCount: itemCount, columns: columnCount)

        var columnWidths = Array(repeating: cellWidth, count: columnCount)
        for (index, text) in candidateTexts.enumerated() {
            let column = index % columnCount
            columnWidths[column] = max(
                columnWidths[column],
                cellWidth(for: text)
            )
        }

        var columnOrigins: [CGFloat] = []
        var nextX = contentInset
        for width in columnWidths {
            columnOrigins.append(nextX)
            nextX += width + cellSpacing
        }
        let frames = candidateTexts.indices.map { index in
            let row = index / columnCount
            let column = index % columnCount
            return CGRect(
                x: columnOrigins[column],
                y: contentInset + CGFloat(row) * (cellHeight + cellSpacing),
                width: columnWidths[column],
                height: cellHeight
            )
        }
        let horizontalSpacing = CGFloat(max(0, columnCount - 1)) * cellSpacing
        let verticalSpacing = CGFloat(max(0, rows - 1)) * cellSpacing
        return CandidateGridMetrics(
            cellFrames: frames,
            documentSize: CGSize(
                width: (2 * contentInset)
                    + columnWidths.reduce(0, +)
                    + horizontalSpacing,
                height: (2 * contentInset)
                    + CGFloat(rows) * cellHeight
                    + verticalSpacing
            )
        )
    }

    static func viewportSize(
        candidateCount: Int,
        mode: CandidatePresentationMode,
        scrollerThickness: CGFloat = defaultScrollerThickness
    ) -> CGSize {
        viewportSize(
            candidateTexts: Array(repeating: "", count: max(1, candidateCount)),
            mode: mode,
            scrollerThickness: scrollerThickness
        )
    }

    static func viewportSize(
        candidateTexts: [String],
        mode: CandidatePresentationMode,
        scrollerThickness: CGFloat = defaultScrollerThickness
    ) -> CGSize {
        let count = max(1, candidateTexts.count)
        let metrics = gridMetrics(candidateTexts: candidateTexts, mode: mode)

        switch mode {
        case .compact:
            return metrics.documentSize
        case .expanded:
            let visibleCount = min(
                count,
                CandidateSession.expandedVisibleCandidateCount
            )
            let columns = min(count, CandidateSession.expandedColumnCount)
            let visibleRows = rowCount(
                itemCount: visibleCount,
                columns: columns
            )
            return CGSize(
                width: metrics.documentSize.width
                    + (count > CandidateSession.expandedVisibleCandidateCount
                        ? scrollerThickness
                        : 0),
                height: (2 * contentInset)
                    + CGFloat(visibleRows) * cellHeight
                    + CGFloat(max(0, visibleRows - 1)) * cellSpacing
            )
        }
    }

    static func documentSize(
        candidateCount: Int,
        mode: CandidatePresentationMode
    ) -> CGSize {
        documentSize(
            candidateTexts: Array(repeating: "", count: max(1, candidateCount)),
            mode: mode
        )
    }

    static func documentSize(
        candidateTexts: [String],
        mode: CandidatePresentationMode
    ) -> CGSize {
        gridMetrics(
            candidateTexts: candidateTexts,
            mode: mode
        ).documentSize
    }

    static func panelSize(
        candidateViewportSize: CGSize,
        revisionHeaderContentWidth: CGFloat?
    ) -> CGSize {
        guard let revisionHeaderContentWidth else {
            return candidateViewportSize
        }

        return CGSize(
            width: max(
                candidateViewportSize.width,
                revisionHeaderContentWidth + (2 * contentInset)
            ),
            height: candidateViewportSize.height + revisionHeaderHeight
        )
    }

    static func candidateViewportSize(
        panelSize: CGSize,
        showsRevisionHeader: Bool
    ) -> CGSize {
        CGSize(
            width: panelSize.width,
            height: max(
                1,
                panelSize.height
                    - (showsRevisionHeader ? revisionHeaderHeight : 0)
            )
        )
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

}

/// Validates a caret rectangle reported by the text client before it is
/// trusted as a candidate-window anchor.
///
/// Some web-backed clients (Electron/Chromium apps, canvas-rendered
/// terminals) cannot determine a real caret position and report a rect
/// pinned to the screen's own coordinate origin instead of failing
/// outright. That rect is otherwise finite and non-empty, so a naive
/// finiteness check accepts it — pinning the candidate window to the
/// screen's lower-left corner no matter where the user is actually typing.
/// A genuine caret is never rendered at that exact corner (window chrome,
/// insets, and the menu bar all keep real text away from it), so a rect
/// sitting within `originEpsilon` of `(0, 0)` is rejected as that known
/// stub value rather than trusted.
enum CandidateAnchorValidation {
    static let originEpsilon: CGFloat = 2

    static func isPlausibleCaretAnchor(_ rect: CGRect) -> Bool {
        guard rect.origin.x.isFinite,
              rect.origin.y.isFinite,
              rect.size.width.isFinite,
              rect.size.height.isFinite,
              rect.size.height > 0 else {
            return false
        }

        return !isPinnedToScreenOrigin(rect)
    }

    private static func isPinnedToScreenOrigin(_ rect: CGRect) -> Bool {
        abs(rect.origin.x) <= originEpsilon
            && abs(rect.origin.y) <= originEpsilon
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
