import CoreGraphics
import XCTest
@testable import Schiera

final class AlternativeLayoutCalculatorTests: XCTestCase {
    func testLayoutModeMetadataIsStableAndComplete() {
        XCTAssertEqual(LayoutMode.allCases.map(\.rawValue), ["smart", "row", "wrappedRows", "balancedGrid", "focus"])
        XCTAssertEqual(LayoutMode.allCases.map(\.displayName), ["Smart", "Row", "Wrapped Rows", "Balanced Grid", "Focus"])
        XCTAssertTrue(LayoutMode.allCases.allSatisfy { !$0.symbolName.isEmpty && !$0.detail.isEmpty })
    }

    func testSmartPolicyUsesDeterministicCountBands() {
        XCTAssertEqual(SmartLayoutPolicy.decision(forWindowCount: 3), SmartLayoutDecision(mode: .row, rows: .automatic))
        XCTAssertEqual(SmartLayoutPolicy.decision(forWindowCount: 4), SmartLayoutDecision(mode: .balancedGrid, rows: .automatic))
        XCTAssertEqual(SmartLayoutPolicy.decision(forWindowCount: 5), SmartLayoutDecision(mode: .wrappedRows, rows: .two))
        XCTAssertEqual(SmartLayoutPolicy.decision(forWindowCount: 6), SmartLayoutDecision(mode: .wrappedRows, rows: .two))
        XCTAssertEqual(SmartLayoutPolicy.decision(forWindowCount: 7), SmartLayoutDecision(mode: .wrappedRows, rows: .three))
        XCTAssertEqual(SmartLayoutPolicy.decision(forWindowCount: 10), SmartLayoutDecision(mode: .wrappedRows, rows: .three))
        XCTAssertEqual(SmartLayoutPolicy.decision(forWindowCount: 11), SmartLayoutDecision(mode: .balancedGrid, rows: .automatic))
        XCTAssertEqual(
            (0...20).map { SmartLayoutPolicy.decision(forWindowCount: $0) },
            (0...20).map { SmartLayoutPolicy.decision(forWindowCount: $0) }
        )
    }

    func testBalancedGridUsesEqualTwoByTwoCells() throws {
        let frames = try BalancedGridLayoutCalculator().frames(
            in: CGRect(x: 0, y: 0, width: 100, height: 80),
            windowCount: 4,
            gap: 8
        )

        XCTAssertEqual(frames, [
            CGRect(x: 12, y: 12, width: 34, height: 24),
            CGRect(x: 54, y: 12, width: 34, height: 24),
            CGRect(x: 12, y: 44, width: 34, height: 24),
            CGRect(x: 54, y: 44, width: 34, height: 24)
        ])
    }

    func testBalancedGridCentersIncompleteLastRow() throws {
        let three = try BalancedGridLayoutCalculator().frames(
            in: CGRect(x: 0, y: 0, width: 100, height: 80),
            windowCount: 3,
            gap: 8
        )
        XCTAssertEqual(three.last, CGRect(x: 33, y: 44, width: 34, height: 24))

        let five = try BalancedGridLayoutCalculator().frames(
            in: CGRect(x: 0, y: 0, width: 300, height: 200),
            windowCount: 5,
            gap: 10
        )
        XCTAssertEqual(five, [
            CGRect(x: 12, y: 12, width: 86, height: 83),
            CGRect(x: 108, y: 12, width: 85, height: 83),
            CGRect(x: 203, y: 12, width: 85, height: 83),
            CGRect(x: 59, y: 105, width: 86, height: 83),
            CGRect(x: 155, y: 105, width: 85, height: 83)
        ])
    }

    func testBalancedGridHandlesZeroOneNegativeOriginsAndFractionalInput() throws {
        let calculator = BalancedGridLayoutCalculator()
        XCTAssertEqual(try calculator.frames(in: CGRect(x: 0, y: 0, width: 10, height: 10), windowCount: 0, gap: 8), [])
        XCTAssertEqual(
            try calculator.frames(in: CGRect(x: -10.2, y: -3.1, width: 101.9, height: 50.8), windowCount: 1, gap: 8),
            [CGRect(x: -11, y: -4, width: 101, height: 50)]
        )
    }

    func testBalancedGridUsesConfiguredEdgeMargin() throws {
        var customization = LayoutCustomization.default
        customization.edgeMargin = 4
        let frames = try BalancedGridLayoutCalculator(customization: customization).frames(
            in: CGRect(x: 0, y: 0, width: 100, height: 80),
            windowCount: 4,
            gap: 8
        )

        XCTAssertEqual(frames, [
            CGRect(x: 4, y: 4, width: 42, height: 32),
            CGRect(x: 54, y: 4, width: 42, height: 32),
            CGRect(x: 4, y: 44, width: 42, height: 32),
            CGRect(x: 54, y: 44, width: 42, height: 32)
        ])
    }

    func testWrappedRowsUsesTwoThenThreeFullWidthRowsInsideSafeEdges() throws {
        let five = try WrappedRowsLayoutCalculator().frames(
            in: CGRect(x: 0, y: 0, width: 300, height: 200),
            windowCount: 5,
            gap: 10
        )
        XCTAssertEqual(five, [
            CGRect(x: 12, y: 12, width: 86, height: 83),
            CGRect(x: 108, y: 12, width: 85, height: 83),
            CGRect(x: 203, y: 12, width: 85, height: 83),
            CGRect(x: 12, y: 105, width: 133, height: 83),
            CGRect(x: 155, y: 105, width: 133, height: 83)
        ])

        let eight = try WrappedRowsLayoutCalculator().frames(
            in: CGRect(x: -100, y: 20, width: 600, height: 360),
            windowCount: 8,
            gap: 8
        )
        XCTAssertEqual(Set(eight.map(\.minY)).count, 3)
        XCTAssertTrue(eight.allSatisfy { $0.minX >= -88 && $0.maxX <= 488 && $0.minY >= 32 && $0.maxY <= 368 })
    }

    func testWrappedRowsCanForceTwoOrThreeRows() throws {
        var twoRowCustomization = LayoutCustomization.default
        twoRowCustomization.wrappedRows = .two
        twoRowCustomization.edgeMargin = 0
        let sevenInTwoRows = try WrappedRowsLayoutCalculator(customization: twoRowCustomization).frames(
            in: CGRect(x: 0, y: 0, width: 300, height: 200),
            windowCount: 7,
            gap: 10
        )
        XCTAssertEqual(Set(sevenInTwoRows.map(\.minY)).count, 2)
        XCTAssertEqual(Set(sevenInTwoRows.map(\.minY)), Set([CGFloat(0), CGFloat(105)]))

        var threeRowCustomization = LayoutCustomization.default
        threeRowCustomization.wrappedRows = .three
        threeRowCustomization.edgeMargin = 0
        let fiveInThreeRows = try WrappedRowsLayoutCalculator(customization: threeRowCustomization).frames(
            in: CGRect(x: -20, y: -10, width: 300, height: 200),
            windowCount: 5,
            gap: 10
        )
        XCTAssertEqual(Set(fiveInThreeRows.map(\.minY)), Set([CGFloat(-10), CGFloat(60), CGFloat(130)]))
        XCTAssertEqual(fiveInThreeRows.count, 5)
    }

    func testExplicitRowCountNeverCreatesEmptyRows() throws {
        var customization = LayoutCustomization.default
        customization.wrappedRows = .three
        customization.edgeMargin = 0
        let frames = try WrappedRowsLayoutCalculator(customization: customization).frames(
            in: CGRect(x: 0, y: 0, width: 100, height: 100),
            windowCount: 2,
            gap: 0
        )
        XCTAssertEqual(frames.map(\.minY), [0, 50])
    }

    func testBalancedGridRejectsInvalidAndInsufficientGeometry() {
        let calculator = BalancedGridLayoutCalculator()
        XCTAssertThrowsError(try calculator.frames(in: CGRect(x: 0, y: 0, width: 10, height: 2), windowCount: 4, gap: 2)) {
            XCTAssertEqual($0 as? LayoutCalculationError, .insufficientSpace)
        }
        XCTAssertThrowsError(try calculator.frames(in: CGRect(x: 0, y: 0, width: 10, height: 10), windowCount: 4, gap: -.infinity)) {
            XCTAssertEqual($0 as? LayoutCalculationError, .invalidGap)
        }
        XCTAssertThrowsError(try calculator.frames(in: CGRect(x: 0, y: 0, width: CGFloat.nan, height: 10), windowCount: 4, gap: 0)) {
            XCTAssertEqual($0 as? LayoutCalculationError, .invalidFrame)
        }
    }

    func testFocusUsesSixtyFortySplitAndStacksSecondaryWindows() throws {
        let frames = try FocusLayoutCalculator().frames(
            in: CGRect(x: 0, y: 0, width: 1_000, height: 600),
            windowCount: 4,
            gap: 10
        )

        XCTAssertEqual(frames, [
            CGRect(x: 12, y: 12, width: 579, height: 576),
            CGRect(x: 601, y: 12, width: 387, height: 186),
            CGRect(x: 601, y: 208, width: 387, height: 185),
            CGRect(x: 601, y: 403, width: 387, height: 185)
        ])
    }

    func testFocusSupportsConfiguredFractionAndTrailingSide() throws {
        var customization = LayoutCustomization.default
        customization.focusFraction = 0.75
        customization.focusSide = .trailing
        customization.edgeMargin = 0
        let frames = try FocusLayoutCalculator(customization: customization).frames(
            in: CGRect(x: 0, y: 0, width: 1_000, height: 600),
            windowCount: 4,
            gap: 10
        )

        XCTAssertEqual(frames.first, CGRect(x: 258, y: 0, width: 742, height: 600))
        XCTAssertTrue(frames.dropFirst().allSatisfy { $0.minX == 0 && $0.width == 248 })
        XCTAssertEqual(frames.dropFirst().map(\.minY), [0, 204, 407])
    }

    func testFocusFractionAndEdgeMarginAreNormalizedIndependently() throws {
        var customization = LayoutCustomization.default
        customization.focusFraction = 0.1
        customization.edgeMargin = 100
        let normalized = customization.normalized
        XCTAssertEqual(normalized.focusFraction, 0.50)
        XCTAssertEqual(normalized.edgeMargin, 64)

        customization.focusFraction = 0.9
        customization.edgeMargin = -.infinity
        let normalizedAgain = customization.normalized
        XCTAssertEqual(normalizedAgain.focusFraction, 0.75)
        XCTAssertEqual(normalizedAgain.edgeMargin, 12)
    }

    func testFocusPreservesInputOrderAndIntegralNegativeGeometry() throws {
        let frames = try FocusLayoutCalculator().frames(
            in: CGRect(x: -100.2, y: -20.9, width: 101.8, height: 41.9),
            windowCount: 3,
            gap: 1.9
        )

        XCTAssertEqual(frames, [
            CGRect(x: -89, y: -9, width: 45, height: 17),
            CGRect(x: -43, y: -9, width: 31, height: 8),
            CGRect(x: -43, y: 0, width: 31, height: 8)
        ])
    }

    func testFocusHandlesZeroOneAndInsufficientSecondaryStack() throws {
        let calculator = FocusLayoutCalculator()
        XCTAssertEqual(try calculator.frames(in: CGRect(x: 0, y: 0, width: 10, height: 10), windowCount: 0, gap: 8), [])
        XCTAssertEqual(
            try calculator.frames(in: CGRect(x: 3, y: 4, width: 10, height: 20), windowCount: 1, gap: 64),
            [CGRect(x: 3, y: 4, width: 10, height: 20)]
        )
        XCTAssertThrowsError(try calculator.frames(in: CGRect(x: 0, y: 0, width: 100, height: 4), windowCount: 4, gap: 1)) {
            XCTAssertEqual($0 as? LayoutCalculationError, .insufficientSpace)
        }
        XCTAssertThrowsError(try calculator.frames(in: CGRect(x: 0, y: 0, width: 2, height: 100), windowCount: 2, gap: 1)) {
            XCTAssertEqual($0 as? LayoutCalculationError, .insufficientSpace)
        }
    }
}
