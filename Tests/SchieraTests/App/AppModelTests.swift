import CoreGraphics
import XCTest
@testable import Schiera

@MainActor
final class AppModelTests: XCTestCase {
    func testStartIsIdempotentAndShortcutUsesArrangeFlow() {
        let h = Harness(permission: .granted, windows: [harnessWindow(0), harnessWindow(1)])
        h.model.start(); h.model.start()
        XCTAssertEqual(h.permission.refreshes, 1)
        XCTAssertEqual(h.shortcut.registerCount, 1)
        h.shortcut.callback?()
        XCTAssertEqual(h.windows.calls, 1)
    }

    func testStartPublishesAllPermissionStates() {
        for state in [AccessibilityPermissionState.granted, .denied, .notDetermined] {
            let h = Harness(permission: state)
            h.model.start()
            XCTAssertEqual(h.model.permissionState, state)
            XCTAssertEqual(h.shortcut.registerCount, 1)
        }
    }

    func testArrangePermissionGatePrecedesEveryOtherService() {
        let h = Harness(permission: .denied, windows: [harnessWindow(0), harnessWindow(1)])
        h.model.arrange()
        XCTAssertEqual(h.model.feedback, .permissionRequired(.denied))
        XCTAssertEqual(h.screen.calls, 0); XCTAssertEqual(h.windows.calls, 0); XCTAssertEqual(h.layout.arrangeCalls, 0)
    }

    func testMissingScreenAndDiscoveryFailureAreNonMutating() {
        let noScreen = Harness(permission: .granted)
        noScreen.screen.result = nil
        noScreen.model.arrange()
        XCTAssertEqual(noScreen.model.feedback, .noTargetScreen)
        let failure = Harness(permission: .granted)
        failure.windows.error = WindowDiscoveryError.windowServerUnavailable
        failure.model.arrange()
        XCTAssertEqual(failure.model.feedback, .failed("Could not discover terminal windows."))
        XCTAssertEqual(failure.layout.arrangeCalls, 0)
    }

    func testZeroOneAndEmptyCatalogProduceInsufficientFeedbackWithoutLayout() {
        for windows in [[], [harnessWindow(0)]] {
            let h = Harness(permission: .granted, windows: windows)
            h.model.arrange()
            XCTAssertEqual(h.model.feedback, .insufficientWindows(windows.count))
            XCTAssertEqual(h.layout.arrangeCalls, 0)
        }
        let empty = Harness(permission: .granted, windows: [harnessWindow(0), harnessWindow(1)])
        empty.preferences.includedTerminalIDs = []
        empty.model.arrange()
        XCTAssertEqual(empty.windows.included, [])
        XCTAssertEqual(empty.model.feedback, .insufficientWindows(0))
        XCTAssertEqual(empty.layout.arrangeCalls, 0)
    }

    func testThreeWindowsPassExactArgumentsAndMapCompleteAndPartial() {
        let windows = [harnessWindow(0), harnessWindow(1), harnessWindow(2)]
        let h = Harness(permission: .granted, windows: windows)
        h.preferences.gap = 13
        h.model.arrange()
        XCTAssertEqual(h.windows.lastWindows, windows)
        XCTAssertEqual(h.windows.included, TerminalCatalog.bundleIdentifiers(forIncludedIDs: h.preferences.includedTerminalIDs))
        XCTAssertEqual(h.layout.lastFrame, h.screen.result!.visibleFrame)
        XCTAssertEqual(h.layout.lastGap, 13)
        XCTAssertEqual(h.model.feedback, .arranged(moved: 3, failed: 0))
        XCTAssertTrue(h.model.canRestore)
        h.layout.arrangement = .completed(moved: 2, failed: 1)
        h.model.arrange()
        XCTAssertEqual(h.model.feedback, .arranged(moved: 2, failed: 1))
    }

    func testExplicitAndPreferredLayoutModesAreForwarded() {
        let h = Harness(permission: .granted, windows: [harnessWindow(0), harnessWindow(1)])

        h.model.arrange(using: .balancedGrid)
        XCTAssertEqual(h.layout.lastMode, .balancedGrid)

        h.preferences.layoutMode = .focus
        h.model.arrange()
        XCTAssertEqual(h.layout.lastMode, .focus)
    }

    func testFocusModeMovesActiveTerminalToPrimaryPosition() {
        let windows = [harnessWindow(0), harnessWindow(1), harnessWindow(2)]
        let h = Harness(permission: .granted, windows: windows)
        h.windows.focusedIdentifier = windows[2].id

        h.model.arrange(using: .focus)

        XCTAssertEqual(h.layout.lastWindows.map(\.id), [windows[2].id, windows[0].id, windows[1].id])
    }

    func testRestoreMapsOutcomesAndConsumesPermissionGate() {
        let h = Harness(permission: .granted)
        h.layout.restoreResult = .nothingToRestore
        h.model.restore()
        XCTAssertEqual(h.model.feedback, .nothingToRestore)
        h.layout.restoreResult = .completed(restored: 2, failed: 1)
        h.model.restore()
        XCTAssertEqual(h.model.feedback, .restored(restored: 2, failed: 1))
        h.permission.stateValue = .denied
        h.model.restore()
        XCTAssertEqual(h.layout.restoreCalls, 2)
    }

    func testPermissionActionsMirrorServiceAndQuitUsesInjectedAction() {
        var quitCount = 0
        let h = Harness(permission: .notDetermined, terminate: { quitCount += 1 })
        h.permission.requestState = .denied
        h.model.requestAccessibilityPermission()
        XCTAssertEqual(h.model.permissionState, .denied)
        h.permission.stateValue = .granted
        h.model.openAccessibilitySettings()
        XCTAssertEqual(h.permission.openCalls, 1)
        XCTAssertEqual(h.model.permissionState, .granted)
        h.model.quit(); XCTAssertEqual(quitCount, 1)
    }

    func testRefreshPermissionPublishesLatestServiceState() {
        let h = Harness(permission: .denied)
        h.permission.stateValue = .granted

        h.model.refreshPermission()

        XCTAssertEqual(h.permission.refreshes, 1)
        XCTAssertEqual(h.model.permissionState, .granted)
    }

    func testSettingsPermissionRefreshSynchronizesMenuStateAndFeedback() {
        let h = Harness(permission: .denied)
        h.model.arrange()
        XCTAssertEqual(h.model.feedback, .permissionRequired(.denied))

        h.permission.stateValue = .granted
        h.model.settingsViewModel.refreshPermission()

        XCTAssertEqual(h.model.permissionState, .granted)
        XCTAssertEqual(h.model.feedback, .ready)
    }

    func testCentralFeedbackStringsRemainEnglish() {
        XCTAssertEqual(AppFeedback.arranged(moved: 2, failed: 0).message, "Arranged 2 terminal windows.")
        XCTAssertEqual(AppFeedback.insufficientWindows(1).message, "Need at least two terminal windows (found 1).")
        XCTAssertFalse(AppFeedback.permissionRequired(.denied).message.isEmpty)
    }

    private func harnessWindow(_ index: Int) -> WindowDescriptor {
        WindowDescriptor(id: WindowIdentifier(token: UUID(), processIdentifier: Int32(index + 1)), bundleIdentifier: "com.apple.Terminal", title: nil, frame: CGRect(x: index * 100, y: 0, width: 90, height: 80))
    }

    private func Harness(permission: AccessibilityPermissionState, windows: [WindowDescriptor] = [], terminate: @escaping () -> Void = {}) -> TestHarness {
        TestHarness(permission: PermissionSpy(permission), screen: ScreenSpy(), preferences: PreferencesStore(defaults: UserDefaults(suiteName: UUID().uuidString)!), windows: WindowSpy(windows), layout: LayoutSpy(), shortcut: ShortcutSpy(), terminate: terminate)
    }
}

@MainActor private final class TestHarness {
    let permission: PermissionSpy; let screen: ScreenSpy; let preferences: PreferencesStore; let windows: WindowSpy; let layout: LayoutSpy; let shortcut: ShortcutSpy
    let model: AppModel
    init(permission: PermissionSpy, screen: ScreenSpy, preferences: PreferencesStore, windows: WindowSpy, layout: LayoutSpy, shortcut: ShortcutSpy, terminate: @escaping () -> Void) {
        self.permission = permission; self.screen = screen; self.preferences = preferences; self.windows = windows; self.layout = layout; self.shortcut = shortcut
        let settings = SettingsViewModel(preferences: preferences, permissionService: permission, shortcutService: shortcut, shortcutHandler: {})
        model = AppModel(permissionService: permission, screenDetector: screen, preferences: preferences, windowDetector: windows, layoutService: layout, shortcutService: shortcut, settingsViewModel: settings, terminateAction: terminate)
    }
}

@MainActor private final class PermissionSpy: AccessibilityPermissionServicing {
    var stateValue: AccessibilityPermissionState; var requestState: AccessibilityPermissionState; var refreshes = 0; var openCalls = 0
    init(_ state: AccessibilityPermissionState) { stateValue = state; requestState = state }
    var state: AccessibilityPermissionState { stateValue }
    func refresh() -> AccessibilityPermissionState { refreshes += 1; return stateValue }
    func request() -> AccessibilityPermissionState { stateValue = requestState; return stateValue }
    func openSystemSettings() -> Bool { openCalls += 1; return true }
}
@MainActor private final class ScreenSpy: ScreenDetecting {
    var calls = 0; var result: ScreenDescriptor? = ScreenDescriptor(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 700), visibleFrame: CGRect(x: 10, y: 20, width: 900, height: 600))
    func screenUnderPointer() -> ScreenDescriptor? { calls += 1; return result }
}
@MainActor private final class WindowSpy: WindowDetecting {
    let windows: [WindowDescriptor]; var calls = 0; var included: Set<String> = []; var lastWindows: [WindowDescriptor] = []; var error: Error?; var focusedIdentifier: WindowIdentifier?
    init(_ windows: [WindowDescriptor]) { self.windows = windows }
    func visibleTerminalWindows(on: ScreenDescriptor, includedBundleIdentifiers: Set<String>) throws -> [WindowDescriptor] { calls += 1; included = includedBundleIdentifiers; if let error { throw error }; lastWindows = includedBundleIdentifiers.isEmpty ? [] : windows; return lastWindows }
    func focusedWindowIdentifier(in windows: [WindowDescriptor]) -> WindowIdentifier? {
        windows.contains(where: { $0.id == focusedIdentifier }) ? focusedIdentifier : nil
    }
}
@MainActor private final class LayoutSpy: LayoutApplying {
    var arrangeCalls = 0; var restoreCalls = 0; var lastFrame: CGRect?; var lastGap: CGFloat = 0; var lastMode: LayoutMode = .row; var lastWindows: [WindowDescriptor] = []; var arrangement: ArrangementOutcome = .completed(moved: 3, failed: 0); var restoreResult: RestoreOutcome = .nothingToRestore; var canRestore = false
    func arrange(windows: [WindowDescriptor], in visibleFrame: CGRect, gap: CGFloat) -> ArrangementOutcome { arrange(windows: windows, in: visibleFrame, gap: gap, mode: .row) }
    func arrange(windows: [WindowDescriptor], in visibleFrame: CGRect, gap: CGFloat, mode: LayoutMode) -> ArrangementOutcome { arrangeCalls += 1; lastWindows = windows; lastFrame = visibleFrame; lastGap = gap; lastMode = mode; canRestore = arrangement != .completed(moved: 0, failed: windows.count); return arrangement }
    func restore() -> RestoreOutcome { restoreCalls += 1; canRestore = false; return restoreResult }
}
@MainActor private final class ShortcutSpy: GlobalShortcutManaging {
    var currentShortcut: GlobalShortcut?; var registerCount = 0; var callback: (@MainActor @Sendable () -> Void)?
    func register(_ shortcut: GlobalShortcut, handler: @escaping @MainActor @Sendable () -> Void) throws { registerCount += 1; currentShortcut = shortcut; callback = handler }
    func unregister() { currentShortcut = nil }
}
