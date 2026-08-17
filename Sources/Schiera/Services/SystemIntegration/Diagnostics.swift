import Foundation

struct DiagnosticsProfile: Equatable, Identifiable, Sendable {
    let name: String
    let detected: Bool
    let windowCount: Int

    var id: String { name }

    init(name: String, detected: Bool, windowCount: Int) {
        self.name = name
        self.detected = detected
        self.windowCount = max(0, windowCount)
    }
}

struct DiagnosticsDisplay: Equatable, Identifiable, Sendable {
    let ordinal: Int
    let isPointerDisplay: Bool
    let windowCount: Int

    var id: Int { ordinal }

    init(ordinal: Int, isPointerDisplay: Bool, windowCount: Int) {
        self.ordinal = ordinal
        self.isPointerDisplay = isPointerDisplay
        self.windowCount = max(0, windowCount)
    }
}

struct DiagnosticsSnapshot: Equatable, Sendable {
    let permission: AccessibilityPermissionState
    let launchAtLogin: LaunchAtLoginStatus
    let shortcutRegistered: Bool
    let profiles: [DiagnosticsProfile]
    let displays: [DiagnosticsDisplay]
    let totalWindowCount: Int

    init(
        permission: AccessibilityPermissionState,
        launchAtLogin: LaunchAtLoginStatus,
        shortcutRegistered: Bool,
        profiles: [DiagnosticsProfile] = [],
        displays: [DiagnosticsDisplay] = [],
        totalWindowCount: Int? = nil
    ) {
        self.permission = permission
        self.launchAtLogin = launchAtLogin
        self.shortcutRegistered = shortcutRegistered
        self.profiles = profiles
        self.displays = displays
        self.totalWindowCount = max(0, totalWindowCount ?? profiles.reduce(0) { $0 + $1.windowCount })
    }
}

@MainActor
protocol DiagnosticsProviding: AnyObject {
    var snapshot: DiagnosticsSnapshot { get }
    @discardableResult
    func update(
        permission: AccessibilityPermissionState,
        launchAtLogin: LaunchAtLoginStatus,
        shortcutRegistered: Bool,
        profiles: [DiagnosticsProfile],
        displays: [DiagnosticsDisplay],
        totalWindowCount: Int?
    ) -> DiagnosticsSnapshot
}

@MainActor
final class DiagnosticsCollector: DiagnosticsProviding {
    private(set) var snapshot: DiagnosticsSnapshot

    init(snapshot: DiagnosticsSnapshot = DiagnosticsSnapshot(
        permission: .notDetermined,
        launchAtLogin: .notRegistered,
        shortcutRegistered: false
    )) {
        self.snapshot = snapshot
    }

    @discardableResult
    func update(
        permission: AccessibilityPermissionState,
        launchAtLogin: LaunchAtLoginStatus,
        shortcutRegistered: Bool,
        profiles: [DiagnosticsProfile] = [],
        displays: [DiagnosticsDisplay] = [],
        totalWindowCount: Int? = nil
    ) -> DiagnosticsSnapshot {
        snapshot = DiagnosticsSnapshot(
            permission: permission,
            launchAtLogin: launchAtLogin,
            shortcutRegistered: shortcutRegistered,
            profiles: profiles,
            displays: displays,
            totalWindowCount: totalWindowCount
        )
        return snapshot
    }
}

typealias InMemoryDiagnosticsService = DiagnosticsCollector
