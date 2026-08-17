import CoreGraphics
import Foundation

struct BalancedGridLayoutCalculator: LayoutCalculating, Sendable {
    private let customization: LayoutCustomization

    init(customization: LayoutCustomization = .default) {
        self.customization = customization.normalized
    }

    func frames(in visibleFrame: CGRect, windowCount: Int, gap: CGFloat) throws -> [CGRect] {
        let geometry = try IntegralLayoutGeometry(
            visibleFrame: visibleFrame,
            windowCount: windowCount,
            gap: gap,
            edgeMargin: CGFloat(customization.edgeMargin)
        )
        guard windowCount > 0 else { return [] }
        guard windowCount > 1 else { return [try geometry.fullFrame()] }

        let columnCount = Int(ceil(sqrt(Double(windowCount))))
        let rowCount = Int(ceil(Double(windowCount) / Double(columnCount)))
        let columnWidths = try IntegralLayoutGeometry.axisLengths(
            total: geometry.width,
            count: columnCount,
            gap: geometry.gap
        )
        let rowHeights = try IntegralLayoutGeometry.axisLengths(
            total: geometry.height,
            count: rowCount,
            gap: geometry.gap
        )

        var result: [CGRect] = []
        result.reserveCapacity(windowCount)
        var currentY = geometry.y

        for row in 0..<rowCount {
            let firstIndex = row * columnCount
            let itemsInRow = min(columnCount, windowCount - firstIndex)
            let itemWidths = Array(columnWidths.prefix(itemsInRow))
            let contentWidth = itemWidths.reduce(0, +) + geometry.gap * CGFloat(max(0, itemsInRow - 1))
            var currentX = geometry.x + floor((geometry.width - contentWidth) / 2)

            for width in itemWidths {
                result.append(CGRect(x: currentX, y: currentY, width: width, height: rowHeights[row]))
                currentX += width + geometry.gap
            }
            currentY += rowHeights[row] + geometry.gap
        }
        return result
    }
}

/// A row-oriented layout that keeps terminals wider than a square grid. The
/// automatic configuration uses two rows for three through six windows and
/// three rows for larger sets.
struct WrappedRowsLayoutCalculator: LayoutCalculating, Sendable {
    private let customization: LayoutCustomization

    init(customization: LayoutCustomization = .default) {
        self.customization = customization.normalized
    }

    func frames(in visibleFrame: CGRect, windowCount: Int, gap: CGFloat) throws -> [CGRect] {
        let geometry = try IntegralLayoutGeometry(
            visibleFrame: visibleFrame,
            windowCount: windowCount,
            gap: gap,
            edgeMargin: CGFloat(customization.edgeMargin)
        )
        guard windowCount > 0 else { return [] }
        guard windowCount > 1 else { return [try geometry.fullFrame()] }

        let requestedRowCount: Int
        switch customization.wrappedRows {
        case .automatic:
            switch windowCount {
            case 2: requestedRowCount = 1
            case 3...6: requestedRowCount = 2
            default: requestedRowCount = 3
            }
        case .two:
            requestedRowCount = 2
        case .three:
            requestedRowCount = 3
        }
        // Never create empty rows when an explicit row count exceeds the
        // number of windows. The automatic two-window behavior remains one
        // full-width row for backwards compatibility.
        let rowCount = min(requestedRowCount, windowCount)

        let rowHeights = try IntegralLayoutGeometry.axisLengths(
            total: geometry.height,
            count: rowCount,
            gap: geometry.gap
        )
        let minimumItemsPerRow = windowCount / rowCount
        let rowsWithExtraItem = windowCount % rowCount

        var result: [CGRect] = []
        result.reserveCapacity(windowCount)
        var currentY = geometry.y

        for row in 0..<rowCount {
            let itemsInRow = minimumItemsPerRow + (row < rowsWithExtraItem ? 1 : 0)
            let widths = try IntegralLayoutGeometry.axisLengths(
                total: geometry.width,
                count: itemsInRow,
                gap: geometry.gap
            )
            var currentX = geometry.x
            for width in widths {
                result.append(CGRect(x: currentX, y: currentY, width: width, height: rowHeights[row]))
                currentX += width + geometry.gap
            }
            currentY += rowHeights[row] + geometry.gap
        }
        return result
    }
}

struct FocusLayoutCalculator: LayoutCalculating, Sendable {
    static let primaryWidthFraction: CGFloat = 0.6

    private let customization: LayoutCustomization

    init(customization: LayoutCustomization = .default) {
        self.customization = customization.normalized
    }

    func frames(in visibleFrame: CGRect, windowCount: Int, gap: CGFloat) throws -> [CGRect] {
        let geometry = try IntegralLayoutGeometry(
            visibleFrame: visibleFrame,
            windowCount: windowCount,
            gap: gap,
            edgeMargin: CGFloat(customization.edgeMargin)
        )
        guard windowCount > 0 else { return [] }
        guard windowCount > 1 else { return [try geometry.fullFrame()] }

        let usableWidth = geometry.width - geometry.gap
        guard usableWidth >= 2 else { throw LayoutCalculationError.insufficientSpace }
        let primaryWidth = min(
            usableWidth - 1,
            max(1, floor(usableWidth * CGFloat(customization.focusFraction)))
        )
        let secondaryWidth = usableWidth - primaryWidth
        let secondaryCount = windowCount - 1
        let secondaryHeights = try IntegralLayoutGeometry.axisLengths(
            total: geometry.height,
            count: secondaryCount,
            gap: geometry.gap
        )

        let primaryOnLeadingSide = customization.focusSide == .leading
        let primaryX = primaryOnLeadingSide
            ? geometry.x
            : geometry.x + secondaryWidth + geometry.gap
        let secondaryX = primaryOnLeadingSide
            ? geometry.x + primaryWidth + geometry.gap
            : geometry.x + 0

        var result = [CGRect(x: primaryX, y: geometry.y, width: primaryWidth, height: geometry.height)]
        result.reserveCapacity(windowCount)
        var currentY = geometry.y
        for height in secondaryHeights {
            result.append(CGRect(x: secondaryX, y: currentY, width: secondaryWidth, height: height))
            currentY += height + geometry.gap
        }
        return result
    }
}

private struct IntegralLayoutGeometry {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    let gap: CGFloat

    init(
        visibleFrame: CGRect,
        windowCount: Int,
        gap: CGFloat,
        edgeMargin: CGFloat = 0
    ) throws {
        guard gap.isFinite, gap >= 0 else { throw LayoutCalculationError.invalidGap }
        guard edgeMargin.isFinite, edgeMargin >= 0 else { throw LayoutCalculationError.invalidFrame }
        guard visibleFrame.origin.x.isFinite,
              visibleFrame.origin.y.isFinite,
              visibleFrame.size.width.isFinite,
              visibleFrame.size.height.isFinite else {
            throw LayoutCalculationError.invalidFrame
        }
        guard visibleFrame.size.height > 0 else { throw LayoutCalculationError.invalidFrame }
        guard windowCount >= 0 else { throw LayoutCalculationError.insufficientSpace }

        let inset = windowCount > 1 ? floor(edgeMargin) : 0
        x = floor(visibleFrame.origin.x) + inset
        y = floor(visibleFrame.origin.y) + inset
        width = floor(visibleFrame.size.width) - inset * 2
        height = floor(visibleFrame.size.height) - inset * 2
        self.gap = floor(gap)
        guard width > 0, height > 0 else { throw LayoutCalculationError.insufficientSpace }
    }

    func fullFrame() throws -> CGRect {
        guard width >= 1 else { throw LayoutCalculationError.insufficientSpace }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func axisLengths(total: CGFloat, count: Int, gap: CGFloat) throws -> [CGFloat] {
        guard count > 0 else { return [] }
        let usable = total - gap * CGFloat(count - 1)
        guard usable >= CGFloat(count) else { throw LayoutCalculationError.insufficientSpace }
        let base = floor(usable / CGFloat(count))
        let remainder = Int(usable - base * CGFloat(count))
        guard base >= 1 else { throw LayoutCalculationError.insufficientSpace }
        return (0..<count).map { base + ($0 < remainder ? 1 : 0) }
    }
}
