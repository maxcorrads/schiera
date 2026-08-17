import AppKit
import CoreGraphics
import Foundation
import OSLog
import SwiftUI

enum AppFeedback: Equatable {
    case ready
    case permissionRequired(AccessibilityPermissionState)
    case noTargetScreen
    case insufficientWindows(Int)
    case focusSelectionRequired
    case arranged(moved: Int, failed: Int)
    case restored(restored: Int, failed: Int)
    case nothingToRestore
    case failed(String)
}

extension AppFeedback {
    var message: String {
        switch self {
        case .ready: return "Ready"
        case .permissionRequired: return "Accessibility permission is required."
        case .noTargetScreen: return "No target screen found."
        case let .insufficientWindows(count): return "Need at least two terminal windows (found \(count))."
        case .focusSelectionRequired: return "Choose a focus window from the menu."
        case let .arranged(moved, failed): return failed == 0 ? "Arranged \(moved) terminal windows." : "Arranged \(moved) windows; \(failed) failed."
        case let .restored(restored, failed): return failed == 0 ? "Restored \(restored) terminal windows." : "Restored \(restored) windows; \(failed) failed."
        case .nothingToRestore: return "Nothing to restore."
        case let .failed(text): return text
        }
    }

    var symbolName: String {
        switch self {
        case .permissionRequired, .focusSelectionRequired, .failed: return "exclamationmark.triangle"
        default: return "rectangle.split.3x1"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var permissionState: AccessibilityPermissionState
    @Published private(set) var feedback: AppFeedback
    @Published private(set) var canRestore: Bool
    @Published private(set) var profiles: [ArrangementProfile] = []
    @Published private(set) var activeProfileID: UUID?
    @Published private(set) var focusChoices: [FocusWindowChoice] = []
    @Published private(set) var temporaryWindowChoices: [FocusWindowChoice] = []
    @Published private(set) var excludedTemporaryWindowIDs: Set<WindowIdentifier> = []
    @Published private(set) var prioritizedTemporaryWindowIDs: [WindowIdentifier] = []

    let settingsViewModel: SettingsViewModel

    private let permissionService: any AccessibilityPermissionServicing
    private let screenDetector: any ScreenDetecting
    private let preferences: any PreferencesProviding
    private let windowDetector: any WindowDetecting
    private let layoutService: any LayoutApplying
    private let shortcutService: any GlobalShortcutManaging
    private let profileStore: (any ProfileProviding)?
    private let shortcutCollection: (any GlobalShortcutCollectionManaging)?
    private let terminateAction: () -> Void
    private var temporarySelection = TemporaryWindowSelection()
    private var choiceScreen: ScreenDescriptor?
    private var choiceProfileID: UUID?
    private var didStart = false
    private let logger = Logger(subsystem: "app.schiera.Schiera", category: "app")

    static func live() -> AppModel {
        let container = DependencyContainer()
        let model = AppModel(
            permissionService: container.permissionService,
            screenDetector: container.screenDetector,
            preferences: container.preferences,
            windowDetector: container.windowDetector,
            layoutService: container.layoutService,
            shortcutService: container.shortcutService,
            settingsViewModel: container.settingsViewModel,
            terminateAction: { NSApplication.shared.terminate(nil) },
            profileStore: container.profileStore,
            shortcutCollection: container.shortcutCollection
        )
        container.actionRelay.model = model
        return model
    }

    init(
        permissionService: any AccessibilityPermissionServicing,
        screenDetector: any ScreenDetecting,
        preferences: any PreferencesProviding,
        windowDetector: any WindowDetecting,
        layoutService: any LayoutApplying,
        shortcutService: any GlobalShortcutManaging,
        settingsViewModel: SettingsViewModel,
        terminateAction: @escaping () -> Void,
        profileStore: (any ProfileProviding)? = nil,
        shortcutCollection: (any GlobalShortcutCollectionManaging)? = nil
    ) {
        self.permissionService = permissionService
        self.screenDetector = screenDetector
        self.preferences = preferences
        self.windowDetector = windowDetector
        self.layoutService = layoutService
        self.shortcutService = shortcutService
        self.settingsViewModel = settingsViewModel
        self.terminateAction = terminateAction
        self.profileStore = profileStore
        self.shortcutCollection = shortcutCollection
        permissionState = permissionService.state
        feedback = .ready
        canRestore = layoutService.canRestore
        synchronizeProfiles()
        settingsViewModel.permissionStateDidChange = { [weak self] state in
            self?.applyPermissionState(state)
        }
        settingsViewModel.configurationDidChange = { [weak self] in
            self?.configurationDidChange()
        }
    }

    var profileChoices: [MenuProfileChoice] {
        MenuProfileChoiceBuilder.build(from: profiles, activeProfileID: activeProfileID)
    }

    var activeProfileName: String? {
        profiles.first(where: { $0.id == activeProfileID })?.name
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        refreshPermission()
        registerAllShortcuts()
    }

    func configurationDidChange() {
        synchronizeProfiles()
        if didStart { registerAllShortcuts() }
    }

    func refreshMenuState() {
        refreshPermission()
        synchronizeProfiles()
    }

    func arrange() {
        if let profile = currentProfile() {
            arrange(profile: profile, mode: profile.layoutMode)
        } else {
            arrangeLegacy(using: preferences.layoutMode)
        }
    }

    func arrange(using mode: LayoutMode) {
        if let profile = currentProfile() {
            arrange(profile: profile, mode: mode)
        } else {
            arrangeLegacy(using: mode)
        }
    }

    func arrange(profileID: UUID) {
        guard let profileStore,
              profileStore.profiles.contains(where: { $0.id == profileID }) else {
            feedback = .failed("The selected profile is unavailable.")
            return
        }
        profileStore.activeProfileID = profileID
        synchronizeProfiles()
        arrange()
    }

    func selectProfile(_ profileID: UUID) {
        guard let profileStore,
              profileStore.profiles.contains(where: { $0.id == profileID }) else { return }
        profileStore.activeProfileID = profileID
        synchronizeProfiles()
        registerAllShortcuts()
    }

    /// Refreshes one ephemeral discovery used by the focus list and one-shot
    /// include/exclude controls. No window identity survives the next scan.
    func refreshWindowChoices() {
        refreshPermission()
        guard permissionState == .granted else {
            feedback = .permissionRequired(permissionState)
            clearWindowChoices()
            return
        }
        let profile = currentProfile() ?? legacyProfile(mode: preferences.layoutMode)
        guard let screen = targetScreen(for: profile)?.screen else {
            feedback = .noTargetScreen
            clearWindowChoices()
            return
        }
        do {
            let windows = try discoverWindows(for: profile, on: screen)
            choiceScreen = screen
            choiceProfileID = profileStore == nil ? nil : profile.id
            temporarySelection.replaceDiscovery(with: windows)
            publishWindowChoices()
            feedback = windows.count >= 2 ? .ready : .insufficientWindows(windows.count)
        } catch {
            clearWindowChoices()
            feedback = .failed("Could not discover terminal windows.")
            logger.error("Window discovery failed")
        }
    }

    func arrangeFocusedWindow(_ id: WindowIdentifier) {
        guard let profile = profileForChoiceSession(),
              let screen = choiceScreen,
              temporarySelection.discoveredWindows.contains(where: { $0.id == id }) else {
            feedback = .focusSelectionRequired
            return
        }
        var windows = temporarySelection.discoveredWindows
        guard let index = windows.firstIndex(where: { $0.id == id }) else {
            feedback = .focusSelectionRequired
            return
        }
        windows.insert(windows.remove(at: index), at: 0)
        apply(windows: windows, screen: screen, profile: profile, mode: .focus)
    }

    func toggleTemporaryWindow(_ id: WindowIdentifier) {
        _ = temporarySelection.toggleExcluded(id)
        publishWindowChoices()
    }

    func toggleTemporaryPriority(_ id: WindowIdentifier) {
        _ = temporarySelection.togglePriority(id)
        publishWindowChoices()
    }

    func arrangeTemporary(using mode: LayoutMode? = nil) {
        guard let profile = profileForChoiceSession(), let screen = choiceScreen else {
            feedback = .failed("Refresh the window list first.")
            return
        }
        var windows = temporarySelection.arrangeableWindows
        let effectiveMode = mode ?? profile.layoutMode
        if effectiveMode == .focus, windows.count >= 2, temporarySelection.prioritizedWindowIDs.isEmpty {
            feedback = .focusSelectionRequired
            return
        }
        if effectiveMode == .focus,
           let prioritized = temporarySelection.prioritizedWindowIDs.first,
           let index = windows.firstIndex(where: { $0.id == prioritized }) {
            windows.insert(windows.remove(at: index), at: 0)
        }
        apply(windows: windows, screen: screen, profile: profile, mode: effectiveMode)
    }

    func clearWindowChoices() {
        temporarySelection.clear()
        choiceScreen = nil
        choiceProfileID = nil
        publishWindowChoices()
    }

    func restore() {
        refreshPermission()
        guard permissionState == .granted else {
            feedback = .permissionRequired(permissionState)
            return
        }
        map(layoutService.restore())
        syncRestore()
    }

    func requestAccessibilityPermission() {
        applyPermissionState(permissionService.request())
        feedback = permissionState == .granted ? .ready : .permissionRequired(permissionState)
    }

    func openAccessibilitySettings() {
        _ = permissionService.openSystemSettings()
        refreshPermission()
    }

    func refreshPermission() { applyPermissionState(permissionService.refresh()) }
    func quit() { terminateAction() }

    private func arrangeLegacy(using mode: LayoutMode) {
        arrange(profile: legacyProfile(mode: mode), mode: mode)
    }

    private func arrange(profile: ArrangementProfile, mode: LayoutMode) {
        refreshPermission()
        guard permissionState == .granted else {
            feedback = .permissionRequired(permissionState)
            return
        }
        guard let target = targetScreen(for: profile) else {
            feedback = .noTargetScreen
            return
        }
        do {
            var windows = try discoverWindows(for: profile, on: target.screen)
            guard windows.count >= 2 else {
                feedback = .insufficientWindows(windows.count)
                syncRestore()
                return
            }
            if mode == .focus {
                let focusIdentifier: WindowIdentifier?
                switch profile.focusTargetMode {
                case .activeWindow:
                    focusIdentifier = windowDetector.focusedWindowIdentifier(in: windows) ?? windows.first?.id
                case .windowUnderPointer:
                    focusIdentifier = windowDetector.windowUnderPointerIdentifier(
                        in: windows,
                        at: target.pointerLocation
                    )
                case .chooseFromMenu:
                    focusIdentifier = nil
                }
                guard let focusIdentifier,
                      let focusedIndex = windows.firstIndex(where: { $0.id == focusIdentifier }) else {
                    feedback = .focusSelectionRequired
                    return
                }
                windows.insert(windows.remove(at: focusedIndex), at: 0)
            }
            apply(windows: windows, screen: target.screen, profile: profile, mode: mode)
        } catch {
            feedback = .failed("Could not discover terminal windows.")
            logger.error("Window discovery failed")
        }
    }

    private func apply(
        windows: [WindowDescriptor],
        screen: ScreenDescriptor,
        profile: ArrangementProfile,
        mode: LayoutMode
    ) {
        let outcome = layoutService.arrange(
            windows: windows,
            in: screen.visibleFrame,
            gap: CGFloat(profile.gap),
            mode: mode,
            customization: profile.customization
        )
        map(outcome)
        syncRestore()
    }

    private func targetScreen(for profile: ArrangementProfile) -> ScreenTarget? {
        let pointerTarget = screenDetector.targetUnderPointer()
        if let binding = profile.displayBinding,
           let bound = screenDetector.screen(matching: binding) {
            return ScreenTarget(screen: bound, pointerLocation: pointerTarget?.pointerLocation ?? .zero)
        }
        return pointerTarget
    }

    private func discoverWindows(
        for profile: ArrangementProfile,
        on screen: ScreenDescriptor
    ) throws -> [WindowDescriptor] {
        let bundleIDs = TerminalCatalog.bundleIdentifiers(forIncludedIDs: profile.includedTerminalIDs)
        return try windowDetector.visibleTerminalWindows(
            on: screen,
            includedBundleIdentifiers: bundleIDs
        )
    }

    private func currentProfile() -> ArrangementProfile? { profileStore?.activeProfile }

    private func profileForChoiceSession() -> ArrangementProfile? {
        if let choiceProfileID {
            return profileStore?.profiles.first(where: { $0.id == choiceProfileID })
        }
        return legacyProfile(mode: preferences.layoutMode)
    }

    private func legacyProfile(mode: LayoutMode) -> ArrangementProfile {
        ArrangementProfile(
            id: UUID(),
            name: "Default",
            layoutMode: mode,
            gap: preferences.gap,
            includedTerminalIDs: preferences.includedTerminalIDs,
            focusTargetMode: .activeWindow,
            customization: .default,
            displayBinding: nil,
            shortcut: nil
        )
    }

    private func synchronizeProfiles() {
        profiles = profileStore?.profiles ?? []
        activeProfileID = profileStore?.activeProfileID
        settingsViewModel.refreshConfiguration()
    }

    private func publishWindowChoices() {
        let choices = FocusWindowChoiceBuilder.build(from: temporarySelection.discoveredWindows)
        focusChoices = choices
        temporaryWindowChoices = choices
        excludedTemporaryWindowIDs = temporarySelection.excludedWindowIDs
        prioritizedTemporaryWindowIDs = temporarySelection.prioritizedWindowIDs
    }

    private func registerAllShortcuts() {
        guard let shortcutCollection else {
            do {
                try shortcutService.register(preferences.shortcut) { [weak self] in self?.arrange() }
            } catch {
                feedback = .failed("Global shortcut registration failed.")
                logger.error("Global shortcut registration failed")
            }
            return
        }

        var registrations: [ShortcutRegistration] = []
        var used = Set<GlobalShortcut>()
        func append(
            id: String,
            shortcut: GlobalShortcut,
            handler: @escaping @MainActor @Sendable () -> Void
        ) {
            guard used.insert(shortcut).inserted else { return }
            registrations.append(ShortcutRegistration(
                binding: ShortcutBinding(id: id, shortcut: shortcut),
                handler: handler
            ))
        }

        append(id: CarbonGlobalShortcutCollectionService.arrangeBindingID, shortcut: preferences.shortcut) { [weak self] in
            self?.arrange()
        }
        for binding in profileStore?.layoutShortcuts.sorted(by: { $0.mode.rawValue < $1.mode.rawValue }) ?? [] {
            append(id: "layout:\(binding.mode.rawValue)", shortcut: binding.shortcut) { [weak self] in
                self?.arrange(using: binding.mode)
            }
        }
        for profile in profiles.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            guard let shortcut = profile.shortcut else { continue }
            append(id: "profile:\(profile.id.uuidString)", shortcut: shortcut) { [weak self] in
                self?.arrange(profileID: profile.id)
            }
        }

        do {
            try shortcutCollection.replaceAll(registrations)
        } catch {
            feedback = .failed("One or more global shortcuts could not be registered.")
            logger.error("Global shortcut collection registration failed")
        }
    }

    private func applyPermissionState(_ state: AccessibilityPermissionState) {
        permissionState = state
        settingsViewModel.synchronizePermissionState(state)
        if state == .granted, case .permissionRequired = feedback { feedback = .ready }
    }

    private func syncRestore() { canRestore = layoutService.canRestore }

    private func map(_ outcome: ArrangementOutcome) {
        switch outcome {
        case let .insufficientWindows(count): feedback = .insufficientWindows(count)
        case .invalidGeometry: feedback = .failed("Terminal windows cannot fit on this screen.")
        case let .completed(moved, failed): feedback = .arranged(moved: moved, failed: failed)
        }
    }

    private func map(_ outcome: RestoreOutcome) {
        switch outcome {
        case .nothingToRestore: feedback = .nothingToRestore
        case let .completed(restored, failed): feedback = .restored(restored: restored, failed: failed)
        }
    }
}
