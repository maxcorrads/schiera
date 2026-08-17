import XCTest
@testable import Schiera

final class SmartLayoutPolicyTests: XCTestCase {
    func testWindowCountMatrixUsesTheContractBoundaries() {
        let expected: [Int: SmartLayoutDecision] = [
            0: SmartLayoutDecision(mode: .row, rows: .automatic),
            1: SmartLayoutDecision(mode: .row, rows: .automatic),
            3: SmartLayoutDecision(mode: .row, rows: .automatic),
            4: SmartLayoutDecision(mode: .balancedGrid, rows: .automatic),
            5: SmartLayoutDecision(mode: .wrappedRows, rows: .two),
            6: SmartLayoutDecision(mode: .wrappedRows, rows: .two),
            7: SmartLayoutDecision(mode: .wrappedRows, rows: .three),
            10: SmartLayoutDecision(mode: .wrappedRows, rows: .three),
            11: SmartLayoutDecision(mode: .balancedGrid, rows: .automatic),
            100: SmartLayoutDecision(mode: .balancedGrid, rows: .automatic)
        ]

        for (count, expectedDecision) in expected {
            XCTAssertEqual(
                SmartLayoutPolicy.decision(forWindowCount: count),
                expectedDecision,
                "Unexpected smart-layout decision for window count \(count)"
            )
        }
    }

    func testSmartPolicyNeverSelectsFocusOrRecursesToSmart() {
        for count in [0, 1, 3, 4, 5, 6, 7, 10, 11, 100] {
            let decision = SmartLayoutPolicy.decision(forWindowCount: count)
            XCTAssertNotEqual(decision.mode, .focus, "Smart layout must not select focus at \(count)")
            XCTAssertNotEqual(decision.mode, .smart, "Smart layout must resolve to a concrete mode at \(count)")
        }
    }
}
