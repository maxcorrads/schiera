import Foundation

struct SmartLayoutDecision: Equatable, Sendable {
    let mode: LayoutMode
    let rows: WrappedRowCount
}

enum SmartLayoutPolicy {
    /// Optimized for the common Schiera workload of five to ten terminals.
    /// Focus remains explicit because automatic focus would be surprising.
    static func decision(forWindowCount count: Int) -> SmartLayoutDecision {
        switch count {
        case ...3:
            return SmartLayoutDecision(mode: .row, rows: .automatic)
        case 4:
            return SmartLayoutDecision(mode: .balancedGrid, rows: .automatic)
        case 5...6:
            return SmartLayoutDecision(mode: .wrappedRows, rows: .two)
        case 7...10:
            return SmartLayoutDecision(mode: .wrappedRows, rows: .three)
        default:
            return SmartLayoutDecision(mode: .balancedGrid, rows: .automatic)
        }
    }
}
