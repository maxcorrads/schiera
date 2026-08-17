import CoreGraphics

/// The frame to restore for one window in a layout-history level.
struct LayoutHistoryEntry: Equatable, Sendable {
    let window: WindowIdentifier
    let frame: CGRect

    init(_ window: WindowIdentifier, _ frame: CGRect) {
        self.window = window
        self.frame = frame
    }

    init(window: WindowIdentifier, frame: CGRect) {
        self.init(window, frame)
    }
}

/// A bounded, main-actor history of layout snapshots.
///
/// Levels are kept newest first. Taking the latest level consumes it, while
/// appending a level evicts the oldest level once the configured capacity is
/// reached. Empty levels are ignored so `canUndo` always reflects whether a
/// restore can actually do work.
@MainActor
final class LayoutHistory {
    nonisolated static let defaultCapacity = 8
    nonisolated static let minimumCapacity = 1
    nonisolated static let maximumCapacity = 32

    let capacity: Int
    private var levels: [[LayoutHistoryEntry]] = []

    init(capacity: Int = 8) {
        self.capacity = min(
            max(capacity, Self.minimumCapacity),
            Self.maximumCapacity
        )
    }

    var count: Int { levels.count }

    var canUndo: Bool { !levels.isEmpty }

    func append(_ entries: [LayoutHistoryEntry]) {
        guard !entries.isEmpty else { return }

        levels.insert(entries, at: 0)
        if levels.count > capacity {
            levels.removeLast()
        }
    }

    func takeLatest() -> [LayoutHistoryEntry]? {
        guard !levels.isEmpty else { return nil }
        return levels.removeFirst()
    }

    func removeAll() {
        levels.removeAll(keepingCapacity: true)
    }
}
