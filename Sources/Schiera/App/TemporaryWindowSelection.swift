import Foundation

/// The user-facing selection for one window discovery result.
///
/// Accessibility identifiers are intentionally scoped to a discovery. The
/// detector creates a fresh UUID token for every scan, so none of the state in
/// this type is suitable for persistence or matching a later scan.
struct TemporaryWindowSelection: Equatable, Sendable {
    private(set) var discoveredWindows: [WindowDescriptor] = []
    private(set) var excludedWindowIDs: Set<WindowIdentifier> = []
    private(set) var prioritizedWindowIDs: [WindowIdentifier] = []

    init(windows: [WindowDescriptor] = []) {
        replaceDiscovery(with: windows)
    }

    /// Installs a new scan and invalidates every selection from the old scan.
    mutating func replaceDiscovery(with windows: [WindowDescriptor]) {
        discoveredWindows = windows
        excludedWindowIDs.removeAll(keepingCapacity: false)
        prioritizedWindowIDs.removeAll(keepingCapacity: false)
    }

    /// Convenience spelling for callers that do not need an argument label.
    mutating func replaceDiscovery(_ windows: [WindowDescriptor]) {
        replaceDiscovery(with: windows)
    }

    /// Removes the current scan and all temporary choices.
    mutating func clear() {
        discoveredWindows.removeAll(keepingCapacity: false)
        excludedWindowIDs.removeAll(keepingCapacity: false)
        prioritizedWindowIDs.removeAll(keepingCapacity: false)
    }

    /// Toggles exclusion for a window in the current scan.
    ///
    /// A stale identifier is ignored and returns `false`; the return value is
    /// the resulting excluded state for a current identifier.
    @discardableResult
    mutating func toggleExcluded(_ id: WindowIdentifier) -> Bool {
        guard containsCurrentWindow(id) else { return false }
        if excludedWindowIDs.insert(id).inserted {
            return true
        }
        excludedWindowIDs.remove(id)
        return false
    }

    /// Toggles priority for a window in the current scan.
    ///
    /// Priority order is the order in which windows were toggled on. A stale
    /// identifier is ignored and returns `false`; the return value indicates
    /// whether the window is now prioritized.
    @discardableResult
    mutating func togglePriority(_ id: WindowIdentifier) -> Bool {
        guard containsCurrentWindow(id) else { return false }
        if let index = prioritizedWindowIDs.firstIndex(of: id) {
            prioritizedWindowIDs.remove(at: index)
            return false
        }
        prioritizedWindowIDs.append(id)
        return true
    }

    /// Current windows eligible for arrangement. Prioritized windows retain
    /// event order; all other windows retain discovery order.
    var arrangeableWindows: [WindowDescriptor] {
        var current: [WindowIdentifier: WindowDescriptor] = [:]
        for window in discoveredWindows {
            current[window.id] = window
        }
        let prioritized = prioritizedWindowIDs.compactMap { id -> WindowDescriptor? in
            guard let window = current[id], !excludedWindowIDs.contains(id) else { return nil }
            return window
        }
        let remaining = discoveredWindows.filter {
            !excludedWindowIDs.contains($0.id) && !prioritizedWindowIDs.contains($0.id)
        }
        return prioritized + remaining
    }

    /// A title-free, PID-free label for a current discovery item.
    ///
    /// Ordinals are assigned among windows with the same bundle identifier in
    /// discovery order. The label is deliberately not an identity and must
    /// not be persisted across scans.
    func displayLabel(for window: WindowDescriptor) -> String {
        let displayName = TerminalCatalog.applications.first {
            $0.bundleIdentifiers.contains(window.bundleIdentifier)
        }?.displayName ?? "Terminal"
        let ordinal = discoveredWindows
            .prefix(while: { $0.id != window.id })
            .filter { $0.bundleIdentifier == window.bundleIdentifier }
            .count + 1
        return "\(displayName) window \(ordinal)"
    }

    /// Short alias useful to menu/settings callers.
    func label(for window: WindowDescriptor) -> String {
        displayLabel(for: window)
    }

    /// Labels in discovery order, useful when presenting a deterministic list.
    var displayLabels: [String] {
        discoveredWindows.map(displayLabel(for:))
    }

    // Compatibility aliases keep callers independent of the storage naming
    // without exposing any persistent identity or title-based state.
    var excluded: Set<WindowIdentifier> { excludedWindowIDs }
    var priorityOrder: [WindowIdentifier] { prioritizedWindowIDs }

    private func containsCurrentWindow(_ id: WindowIdentifier) -> Bool {
        discoveredWindows.contains { $0.id == id }
    }
}
