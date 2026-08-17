import CoreGraphics
import Foundation

struct ScreenDescriptor: Equatable, Sendable {
    let displayID: UInt32
    let frame: CGRect
    let visibleFrame: CGRect
}

struct ScreenTarget: Equatable, Sendable {
    let screen: ScreenDescriptor
    let pointerLocation: CGPoint
}

struct WindowIdentifier: Hashable, Sendable {
    let token: UUID
    let processIdentifier: Int32
}

struct WindowSelectionToken: Hashable, Sendable {
    let processIdentifier: Int32
    let windowNumber: UInt32
}

struct WindowDescriptor: Equatable, Sendable {
    let id: WindowIdentifier
    let bundleIdentifier: String
    let title: String?
    let frame: CGRect
    let windowNumber: UInt32?

    init(
        id: WindowIdentifier,
        bundleIdentifier: String,
        title: String?,
        frame: CGRect,
        windowNumber: UInt32? = nil
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.title = title
        self.frame = frame
        self.windowNumber = windowNumber
    }
}

struct TerminalApplicationDefinition: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let displayName: String
    let bundleIdentifiers: Set<String>
    let defaultEnabled: Bool
}

struct ShortcutModifiers: OptionSet, Hashable, Codable, Sendable {
    let rawValue: UInt32

    static let control = ShortcutModifiers(rawValue: 1 << 0)
    static let option = ShortcutModifiers(rawValue: 1 << 1)
    static let shift = ShortcutModifiers(rawValue: 1 << 2)
    static let command = ShortcutModifiers(rawValue: 1 << 3)
}

struct GlobalShortcut: Hashable, Codable, Sendable {
    let keyCode: UInt32
    let modifiers: ShortcutModifiers

    static let defaultSchiera = GlobalShortcut(
        keyCode: 1,
        modifiers: [.control, .option, .command]
    )
}

enum AccessibilityPermissionState: String, Equatable, Sendable {
    case notDetermined
    case denied
    case granted
}

enum LayoutCalculationError: Error, Equatable {
    case invalidGap
    case invalidFrame
    case insufficientSpace
}

enum LayoutMode: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case smart
    case row
    case wrappedRows
    case balancedGrid
    case focus

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .smart: return "Smart"
        case .row: return "Row"
        case .wrappedRows: return "Wrapped Rows"
        case .balancedGrid: return "Balanced Grid"
        case .focus: return "Focus"
        }
    }

    var symbolName: String {
        switch self {
        case .smart: return "sparkles.rectangle.stack"
        case .row: return "rectangle.split.3x1"
        case .wrappedRows: return "rectangle.grid.2x2"
        case .balancedGrid: return "square.grid.2x2"
        case .focus: return "rectangle.split.2x1"
        }
    }

    var detail: String {
        switch self {
        case .smart: return "Choose a balanced layout automatically from the window count."
        case .row: return "Place every terminal side by side."
        case .wrappedRows: return "Wrap terminals across two or three full-width rows."
        case .balancedGrid: return "Use equal cells in balanced rows and columns."
        case .focus: return "Give the active terminal 60% of the width and stack the rest."
        }
    }
}

enum FocusTargetMode: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case activeWindow
    case windowUnderPointer
    case chooseFromMenu

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .activeWindow: return "Active Window"
        case .windowUnderPointer: return "Window Under Pointer"
        case .chooseFromMenu: return "Choose from Menu"
        }
    }
}

enum FocusSide: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case leading
    case trailing

    var id: String { rawValue }
    var displayName: String { self == .leading ? "Left" : "Right" }
}

enum WrappedRowCount: Int, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case automatic = 0
    case two = 2
    case three = 3

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .two: return "2 Rows"
        case .three: return "3 Rows"
        }
    }
}

struct LayoutCustomization: Codable, Hashable, Sendable {
    var wrappedRows: WrappedRowCount
    var focusFraction: Double
    var focusSide: FocusSide
    var edgeMargin: Double

    static let `default` = LayoutCustomization(
        wrappedRows: .automatic,
        focusFraction: 0.60,
        focusSide: .leading,
        edgeMargin: 12
    )

    var normalized: LayoutCustomization {
        LayoutCustomization(
            wrappedRows: WrappedRowCount(rawValue: wrappedRows.rawValue) ?? .automatic,
            focusFraction: focusFraction.isFinite ? min(max(focusFraction, 0.50), 0.75) : 0.60,
            focusSide: focusSide,
            edgeMargin: edgeMargin.isFinite ? min(max(edgeMargin, 0), 64) : 12
        )
    }
}

/// A public-display identity. The UUID is preferred across reconnects; the
/// numeric ID is retained only as an in-session fallback.
struct DisplayBinding: Codable, Hashable, Sendable {
    let uuid: String?
    let fallbackDisplayID: UInt32
}

struct ArrangementProfile: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var layoutMode: LayoutMode
    var gap: Double
    var includedTerminalIDs: Set<String>
    var focusTargetMode: FocusTargetMode
    var customization: LayoutCustomization
    var displayBinding: DisplayBinding?
    var shortcut: GlobalShortcut?

    func normalized(knownTerminalIDs: Set<String>) -> ArrangementProfile {
        var copy = self
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.name = String((trimmedName.isEmpty ? "Profile" : trimmedName).prefix(48))
        copy.gap = gap.isFinite ? min(max(gap, 0), 64) : 8
        copy.includedTerminalIDs.formIntersection(knownTerminalIDs)
        copy.customization = customization.normalized
        if let shortcut, !Self.validShortcut(shortcut) { copy.shortcut = nil }
        return copy
    }

    private static func validShortcut(_ shortcut: GlobalShortcut) -> Bool {
        let supported = ShortcutModifiers.control.rawValue
            | ShortcutModifiers.option.rawValue
            | ShortcutModifiers.shift.rawValue
            | ShortcutModifiers.command.rawValue
        return shortcut.keyCode <= 127
            && shortcut.modifiers.rawValue != 0
            && shortcut.modifiers.rawValue & ~supported == 0
    }
}

struct FocusWindowChoice: Identifiable, Equatable, Sendable {
    let id: WindowIdentifier
    let label: String
}

struct LayoutShortcutBinding: Codable, Hashable, Sendable {
    let mode: LayoutMode
    var shortcut: GlobalShortcut
}

enum ArrangementOutcome: Equatable, Sendable {
    case insufficientWindows(count: Int)
    case invalidGeometry
    case completed(moved: Int, failed: Int)
}

enum RestoreOutcome: Equatable, Sendable {
    case nothingToRestore
    case completed(restored: Int, failed: Int)
}
