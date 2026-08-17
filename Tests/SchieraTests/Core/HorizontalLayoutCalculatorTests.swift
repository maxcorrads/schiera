import CoreGraphics
import XCTest
@testable import Schiera

final class HorizontalLayoutCalculatorTests: XCTestCase {
    private let calculator = HorizontalLayoutCalculator()

    func testZeroWindowsReturnsEmpty() throws {
        XCTAssertEqual(try calculator.frames(in: CGRect(x: 20, y: 10, width: 100, height: 50), windowCount: 0, gap: 8), [])
    }

    func testOneWindowReturnsIntegralVisibleFrame() throws {
        XCTAssertEqual(
            try calculator.frames(in: CGRect(x: -100, y: -20, width: 801, height: 601), windowCount: 1, gap: 64),
            [CGRect(x: -100, y: -20, width: 801, height: 601)]
        )
    }

    func testTwoWindowsUseDefaultGap() throws {
        XCTAssertEqual(
            try calculator.frames(in: CGRect(x: 0, y: 0, width: 100, height: 40), windowCount: 2, gap: 8),
            [CGRect(x: 0, y: 0, width: 46, height: 40), CGRect(x: 54, y: 0, width: 46, height: 40)]
        )
    }

    func testRemainderIsAssignedLeftToRight() throws {
        let frames = try calculator.frames(in: CGRect(x: -10, y: -30, width: 101, height: 70), windowCount: 3, gap: 8)
        XCTAssertEqual(frames, [
            CGRect(x: -10, y: -30, width: 29, height: 70),
            CGRect(x: 27, y: -30, width: 28, height: 70),
            CGRect(x: 63, y: -30, width: 28, height: 70)
        ])
    }

    func testManyWindowsAndInvariants() throws {
        let visible = CGRect(x: -1920, y: -100, width: 1920, height: 1080)
        let count = 20
        let gap: CGFloat = 8
        let frames = try calculator.frames(in: visible, windowCount: count, gap: gap)
        XCTAssertEqual(frames.count, count)
        XCTAssertEqual(frames.first?.minX, visible.minX)
        XCTAssertEqual(frames.last?.maxX, visible.maxX)
        XCTAssertEqual(frames.map(\.width).reduce(0, +) + gap * CGFloat(count - 1), floor(visible.width))
    }

    func testGapsZeroAndMaximum() throws {
        let zero = try calculator.frames(in: CGRect(x: 0, y: 0, width: 10, height: 10), windowCount: 3, gap: 0)
        XCTAssertEqual(zero.map(\.width), [4, 3, 3])
        let maxGap = try calculator.frames(in: CGRect(x: 0, y: 0, width: 130, height: 10), windowCount: 2, gap: 64)
        XCTAssertEqual(maxGap, [CGRect(x: 0, y: 0, width: 33, height: 10), CGRect(x: 97, y: 0, width: 33, height: 10)])
    }

    func testFractionalGeometryIsFloored() throws {
        XCTAssertEqual(
            try calculator.frames(in: CGRect(x: -3.8, y: -2.2, width: 20.9, height: 10.8), windowCount: 2, gap: 1),
            [CGRect(x: -4, y: -3, width: 10, height: 10), CGRect(x: 7, y: -3, width: 9, height: 10)]
        )
    }

    func testSmallWidths() throws {
        XCTAssertEqual(try calculator.frames(in: CGRect(x: 0, y: 0, width: 5, height: 1), windowCount: 2, gap: 1).map(\.width), [2, 2])
        XCTAssertThrowsError(try calculator.frames(in: CGRect(x: 0, y: 0, width: 2, height: 1), windowCount: 2, gap: 1)) { error in
            XCTAssertEqual(error as? LayoutCalculationError, .insufficientSpace)
        }
    }

    func testInvalidGeometryAndGaps() {
        for frame in [CGRect(x: 0, y: 0, width: 10, height: 0), CGRect(x: CGFloat.infinity, y: 0, width: 10, height: 10), CGRect(x: 0, y: 0, width: CGFloat.nan, height: 10)] {
            XCTAssertThrowsError(try calculator.frames(in: frame, windowCount: 1, gap: 0)) { XCTAssertEqual($0 as? LayoutCalculationError, .invalidFrame) }
        }
        for gap in [CGFloat(-1), .infinity, -.infinity, .nan] {
            XCTAssertThrowsError(try calculator.frames(in: CGRect(x: 0, y: 0, width: 10, height: 10), windowCount: 1, gap: gap)) { XCTAssertEqual($0 as? LayoutCalculationError, .invalidGap) }
        }
    }
}
