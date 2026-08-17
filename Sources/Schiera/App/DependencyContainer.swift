import AppKit
import Foundation

@MainActor
final class AppActionRelay {
    weak var model: AppModel?
    func invoke() { model?.arrange() }
    func configurationChanged() { model?.configurationDidChange() }
}

@MainActor
final class DependencyContainer {
    let permissionService: any AccessibilityPermissionServicing
    let screenDetector: any ScreenDetecting
    let preferences: PreferencesStore
    let profileStore: ProfileStore
    let windowDetector: MacTerminalWindowDetector
    let layoutService: LayoutService
    let shortcutService: any GlobalShortcutManaging
    let shortcutCollection: any GlobalShortcutCollectionManaging
    let launchAtLoginService: any LaunchAtLoginManaging
    let diagnostics: any DiagnosticsProviding
    let settingsViewModel: SettingsViewModel
    let actionRelay: AppActionRelay

    init() {
        let relay = AppActionRelay()
        let permission = MacAccessibilityPermissionService()
        let screen = MacScreenDetector()
        let store = PreferencesStore()
        let seed = ArrangementProfile(
            id: UUID(),
            name: "Default",
            layoutMode: store.layoutMode,
            gap: store.gap,
            includedTerminalIDs: store.includedTerminalIDs,
            focusTargetMode: .activeWindow,
            customization: .default,
            displayBinding: nil,
            shortcut: nil
        )
        let profiles = ProfileStore(seed: seed)
        let registry = AXWindowHandleRegistry()
        let detector = MacTerminalWindowDetector(registry: registry)
        let layout = LayoutService(calculator: HorizontalLayoutCalculator(), frameController: AccessibilityWindowFrameController(registry: registry))
        let shortcut = CarbonGlobalShortcutCollectionService()
        let launchAtLogin = LaunchAtLoginService()
        let diagnosticsCollector = DiagnosticsCollector()
        actionRelay = relay
        permissionService = permission
        screenDetector = screen
        preferences = store
        profileStore = profiles
        windowDetector = detector
        layoutService = layout
        shortcutService = shortcut
        shortcutCollection = shortcut
        launchAtLoginService = launchAtLogin
        diagnostics = diagnosticsCollector
        settingsViewModel = SettingsViewModel(
            preferences: store,
            permissionService: permission,
            shortcutService: shortcut,
            shortcutHandler: { [weak actionRelay] in actionRelay?.invoke() },
            profileStore: profiles,
            screenDetector: screen,
            launchAtLoginService: launchAtLogin,
            diagnostics: diagnosticsCollector
        )
    }
}
