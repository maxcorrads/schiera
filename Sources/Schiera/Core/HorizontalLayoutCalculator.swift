import CoreGraphics
import Foundation

protocol LayoutCalculating: Sendable {
    func frames(in visibleFrame: CGRect, windowCount: Int, gap: CGFloat) throws -> [CGRect]
}

struct HorizontalLayoutCalculator: LayoutCalculating, Sendable {
    func frames(in visibleFrame: CGRect, windowCount: Int, gap: CGFloat) throws -> [CGRect] {
        guard gap.isFinite, gap >= 0 else { throw LayoutCalculationError.invalidGap }
        guard visibleFrame.origin.x.isFinite,
              visibleFrame.origin.y.isFinite,
              visibleFrame.size.width.isFinite,
              visibleFrame.size.height.isFinite else {
            throw LayoutCalculationError.invalidFrame
        }
        guard visibleFrame.size.height > 0 else { throw LayoutCalculationError.invalidFrame }
        guard windowCount >= 0 else { throw LayoutCalculationError.insufficientSpace }
        guard windowCount > 0 else { return [] }

        // Accessibility geometry is integral points. Floor each component independently,
        // preserving negative origins (rather than flooring a derived max coordinate).
        let x = floor(visibleFrame.origin.x)
        let y = floor(visibleFrame.origin.y)
        let width = floor(visibleFrame.size.width)
        let height = floor(visibleFrame.size.height)
        guard height > 0 else { throw LayoutCalculationError.invalidFrame }

        let integralGap = floor(gap)
        let gapCount = windowCount - 1
        let gapTotal = integralGap * CGFloat(gapCount)
        let usableWidth = width - gapTotal
        guard usableWidth >= CGFloat(windowCount) else {
            throw LayoutCalculationError.insufficientSpace
        }

        let baseWidth = floor(usableWidth / CGFloat(windowCount))
        let remainder = Int(usableWidth.truncatingRemainder(dividingBy: CGFloat(windowCount)))
        guard baseWidth >= 1 else { throw LayoutCalculationError.insufficientSpace }

        var result: [CGRect] = []
        result.reserveCapacity(windowCount)
        var currentX = x
        for index in 0..<windowCount {
            let frameWidth = baseWidth + (index < remainder ? 1 : 0)
            result.append(CGRect(x: currentX, y: y, width: frameWidth, height: height))
            currentX += frameWidth + integralGap
        }
        return result
    }
}
