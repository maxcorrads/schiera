import ApplicationServices
import AppKit
import Foundation
import OSLog

/// Storage for the local marker that distinguishes a denied permission from a
/// permission that has not yet been requested.
protocol AccessibilityPromptMarkerStoring: AnyObject {
    var wasRequested: Bool { get set }
}

/// Adapter used to open the Accessibility privacy pane. Keeping this behind a
/// small protocol makes the service deterministic in unit tests.
protocol AccessibilitySettingsOpening: AnyObject {
    func open(_ url: URL) -> Bool
}

final class UserDefaultsAccessibilityPromptMarkerStore: AccessibilityPromptMarkerStoring {
    private let defaults: UserDefaults
    private let key = "accessibilityPromptWasRequested"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var wasRequested: Bool {
        get { defaults.bool(forKey: key) }
        set { defaults.set(newValue, forKey: key) }
    }
}

final class WorkspaceAccessibilitySettingsOpener: AccessibilitySettingsOpening {
    func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }
}

@MainActor
protocol AccessibilityPermissionServicing: AnyObject {
    var state: AccessibilityPermissionState { get }
    @discardableResult func refresh() -> AccessibilityPermissionState
    @discardableResult func request() -> AccessibilityPermissionState
    @discardableResult func openSystemSettings() -> Bool
}

@MainActor
final class MacAccessibilityPermissionService: AccessibilityPermissionServicing {
    private(set) var state: AccessibilityPermissionState

    private let trustChecker: (_ prompt: Bool) -> Bool
    private let markerStore: any AccessibilityPromptMarkerStoring
    private let settingsOpener: any AccessibilitySettingsOpening
    private let logger = Logger(subsystem: "app.schiera.Schiera", category: "accessibility")

    /// Creates the live service. Trust is checked without prompting during
    /// initialization so constructing the app never causes an OS prompt.
    convenience init(defaults: UserDefaults = .standard) {
        self.init(
            trustChecker: { prompt in
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
                return AXIsProcessTrustedWithOptions(options)
            },
            markerStore: UserDefaultsAccessibilityPromptMarkerStore(defaults: defaults),
            settingsOpener: WorkspaceAccessibilitySettingsOpener()
        )
    }

    /// Dependency-injected initializer for deterministic tests and adapters.
    init(
        trustChecker: @escaping (_ prompt: Bool) -> Bool,
        markerStore: any AccessibilityPromptMarkerStoring,
        settingsOpener: any AccessibilitySettingsOpening
    ) {
        self.trustChecker = trustChecker
        self.markerStore = markerStore
        self.settingsOpener = settingsOpener
        self.state = Self.derivedState(isTrusted: trustChecker(false), wasRequested: markerStore.wasRequested)
    }

    /// Convenience injection point when tests only need a closure-backed
    /// marker and URL opener.
    convenience init(
        trustChecker: @escaping (_ prompt: Bool) -> Bool,
        wasPromptRequested: @escaping () -> Bool,
        setPromptRequested: @escaping (Bool) -> Void,
        openURL: @escaping (URL) -> Bool
    ) {
        self.init(
            trustChecker: trustChecker,
            markerStore: ClosureAccessibilityPromptMarkerStore(get: wasPromptRequested, set: setPromptRequested),
            settingsOpener: ClosureAccessibilitySettingsOpener(open: openURL)
        )
    }

    @discardableResult
    func refresh() -> AccessibilityPermissionState {
        state = Self.derivedState(isTrusted: trustChecker(false), wasRequested: markerStore.wasRequested)
        return state
    }

    @discardableResult
    func request() -> AccessibilityPermissionState {
        // Persist first: the prompt is asynchronous and may return false even
        // while the user is deciding in System Settings.
        markerStore.wasRequested = true
        state = Self.derivedState(isTrusted: trustChecker(true), wasRequested: true)
        return state
    }

    @discardableResult
    func openSystemSettings() -> Bool {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            logger.error("Failed to construct Accessibility settings URL")
            return false
        }
        let opened = settingsOpener.open(url)
        if !opened {
            logger.error("Failed to open Accessibility settings")
        }
        return opened
    }

    private static func derivedState(isTrusted: Bool, wasRequested: Bool) -> AccessibilityPermissionState {
        if isTrusted { return .granted }
        return wasRequested ? .denied : .notDetermined
    }
}

private final class ClosureAccessibilityPromptMarkerStore: AccessibilityPromptMarkerStoring {
    private let getter: () -> Bool
    private let setter: (Bool) -> Void

    init(get: @escaping () -> Bool, set: @escaping (Bool) -> Void) {
        getter = get
        setter = set
    }

    var wasRequested: Bool {
        get { getter() }
        set { setter(newValue) }
    }
}

private final class ClosureAccessibilitySettingsOpener: AccessibilitySettingsOpening {
    private let opener: (URL) -> Bool

    init(open: @escaping (URL) -> Bool) { opener = open }

    func open(_ url: URL) -> Bool { opener(url) }
}
