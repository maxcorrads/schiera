import Foundation
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var shortcutDraft: GlobalShortcut
    @Published private(set) var shortcutError: String?
    @Published private(set) var permissionState: AccessibilityPermissionState
    @Published private(set) var launchAtLoginStatus: LaunchAtLoginStatus
    @Published private(set) var launchAtLoginError: String?
    @Published private(set) var diagnosticsSnapshot: DiagnosticsSnapshot?

    let preferences: PreferencesStore
    let permissionService: any AccessibilityPermissionServicing
    let shortcutService: any GlobalShortcutManaging
    let profileEditor: ProfileEditorState?

    private let shortcutHandler: @MainActor @Sendable () -> Void
    private let screenDetector: (any ScreenDetecting)?
    private let launchAtLoginService: (any LaunchAtLoginManaging)?
    private let diagnostics: (any DiagnosticsProviding)?
    var permissionStateDidChange: (@MainActor (AccessibilityPermissionState) -> Void)?
    var configurationDidChange: (@MainActor () -> Void)?

    init(
        preferences: PreferencesStore,
        permissionService: any AccessibilityPermissionServicing,
        shortcutService: any GlobalShortcutManaging,
        shortcutHandler: @escaping @MainActor @Sendable () -> Void,
        profileStore: (any ProfileProviding)? = nil,
        screenDetector: (any ScreenDetecting)? = nil,
        launchAtLoginService: (any LaunchAtLoginManaging)? = nil,
        diagnostics: (any DiagnosticsProviding)? = nil
    ) {
        self.preferences = preferences
        self.permissionService = permissionService
        self.shortcutService = shortcutService
        self.shortcutHandler = shortcutHandler
        self.profileEditor = profileStore.map(ProfileEditorState.init)
        self.screenDetector = screenDetector
        self.launchAtLoginService = launchAtLoginService
        self.diagnostics = diagnostics
        shortcutDraft = preferences.shortcut
        permissionState = permissionService.state
        launchAtLoginStatus = launchAtLoginService?.status ?? .notRegistered
        refreshDiagnostics()
    }

    func commitShortcut(_ shortcut: GlobalShortcut) {
        do {
            try shortcutService.register(shortcut, handler: shortcutHandler)
            preferences.shortcut = shortcut
            shortcutDraft = shortcut
            shortcutError = nil
            configurationDidChange?()
            refreshDiagnostics()
        } catch {
            shortcutDraft = preferences.shortcut
            shortcutError = error.localizedDescription
        }
    }

    func refreshConfiguration() {
        profileEditor?.refresh()
        if let launchAtLoginService {
            launchAtLoginStatus = launchAtLoginService.refresh()
        }
        refreshDiagnostics()
    }

    func profileDidChange() {
        configurationDidChange?()
        refreshDiagnostics()
    }

    func bindActiveProfileToPointerDisplay() {
        guard let binding = screenDetector?.bindingForScreenUnderPointer() else { return }
        profileEditor?.setDisplayBinding(binding)
        profileDidChange()
    }

    func clearActiveProfileDisplayBinding() {
        profileEditor?.setDisplayBinding(nil)
        profileDidChange()
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        guard let launchAtLoginService else { return }
        do {
            try launchAtLoginService.setEnabled(enabled)
            launchAtLoginStatus = launchAtLoginService.refresh()
            launchAtLoginError = nil
        } catch {
            launchAtLoginStatus = launchAtLoginService.refresh()
            launchAtLoginError = error.localizedDescription
        }
        refreshDiagnostics()
    }

    func openLoginItemsSettings() {
        launchAtLoginService?.openSystemSettings()
        if let launchAtLoginService {
            launchAtLoginStatus = launchAtLoginService.refresh()
        }
    }

    func refreshPermission() {
        publishPermissionState(permissionService.refresh())
        refreshConfiguration()
    }

    func requestPermission() {
        publishPermissionState(permissionService.request())
        refreshDiagnostics()
    }

    func openAccessibilitySettings() {
        _ = permissionService.openSystemSettings()
    }

    func synchronizePermissionState(_ state: AccessibilityPermissionState) {
        permissionState = state
        refreshDiagnostics()
    }

    private func publishPermissionState(_ state: AccessibilityPermissionState) {
        permissionState = state
        permissionStateDidChange?(state)
    }

    private func refreshDiagnostics() {
        guard let diagnostics else {
            diagnosticsSnapshot = nil
            return
        }
        diagnosticsSnapshot = diagnostics.update(
            permission: permissionState,
            launchAtLogin: launchAtLoginStatus,
            shortcutRegistered: shortcutService.currentShortcut != nil,
            profiles: profileEditor?.profiles.map {
                DiagnosticsProfile(name: $0.name, detected: true, windowCount: 0)
            } ?? [],
            displays: [],
            totalWindowCount: nil
        )
    }
}
