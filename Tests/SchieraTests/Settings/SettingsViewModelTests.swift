import AppKit
import XCTest
@testable import Schiera

@MainActor
final class SettingsViewModelTests: XCTestCase {
    func testSuccessfulShortcutCommitRegistersBeforePersistence() {
        let defaults = UserDefaults(suiteName: "SettingsViewModelTests.success")!
        defaults.removePersistentDomain(forName: "SettingsViewModelTests.success")
        let preferences = PreferencesStore(defaults: defaults)
        let permission = TestPermissionService()
        let shortcuts = TestShortcutService()
        let model = SettingsViewModel(preferences: preferences, permissionService: permission, shortcutService: shortcuts) {}
        let value = GlobalShortcut(keyCode: 0, modifiers: .control)

        model.commitShortcut(value)

        XCTAssertEqual(shortcuts.registered, value)
        XCTAssertEqual(preferences.shortcut, value)
        XCTAssertNil(model.shortcutError)
    }

    func testFailedCommitRestoresDraftAndDoesNotPersist() {
        let defaults = UserDefaults(suiteName: "SettingsViewModelTests.failure")!
        defaults.removePersistentDomain(forName: "SettingsViewModelTests.failure")
        let preferences = PreferencesStore(defaults: defaults)
        let permission = TestPermissionService()
        let shortcuts = TestShortcutService()
        shortcuts.error = GlobalShortcutError.registrationFailed(status: -1)
        let model = SettingsViewModel(preferences: preferences, permissionService: permission, shortcutService: shortcuts) {}
        let original = preferences.shortcut

        model.commitShortcut(GlobalShortcut(keyCode: 0, modifiers: .control))

        XCTAssertEqual(model.shortcutDraft, original)
        XCTAssertEqual(preferences.shortcut, original)
        XCTAssertNotNil(model.shortcutError)
    }

    func testPermissionActionsDelegateAndMirrorState() {
        let preferences = PreferencesStore(defaults: UserDefaults(suiteName: "SettingsViewModelTests.permission")!)
        let permission = TestPermissionService()
        let model = SettingsViewModel(preferences: preferences, permissionService: permission, shortcutService: TestShortcutService()) {}

        permission.nextState = .denied
        model.refreshPermission()
        XCTAssertEqual(model.permissionState, .denied)
        model.requestPermission()
        XCTAssertEqual(permission.requestCount, 1)
        model.openAccessibilitySettings()
        XCTAssertEqual(permission.openCount, 1)
    }

    func testPermissionRefreshPublishesSharedStateChange() {
        let preferences = PreferencesStore(defaults: UserDefaults(suiteName: "SettingsViewModelTests.permissionPublish")!)
        let permission = TestPermissionService()
        let model = SettingsViewModel(preferences: preferences, permissionService: permission, shortcutService: TestShortcutService()) {}
        var publishedState: AccessibilityPermissionState?
        model.permissionStateDidChange = { publishedState = $0 }

        permission.nextState = .granted
        model.refreshPermission()

        XCTAssertEqual(publishedState, .granted)
    }
}

final class ShortcutEventTranslatorTests: XCTestCase {
    func testDefaultCombinationAndIgnoredFlags() {
        let result = ShortcutEventTranslator.translate(keyCode: 1, modifierFlags: [.control, .option, .command, .numericPad, .function])
        XCTAssertEqual(result, .shortcut(.defaultSchiera))
    }

    func testEachModifierAndSpecialKeys() {
        XCTAssertEqual(ShortcutEventTranslator.translate(keyCode: 0, modifierFlags: .control), .shortcut(GlobalShortcut(keyCode: 0, modifiers: .control)))
        XCTAssertEqual(ShortcutEventTranslator.translate(keyCode: 0, modifierFlags: .option), .shortcut(GlobalShortcut(keyCode: 0, modifiers: .option)))
        XCTAssertEqual(ShortcutEventTranslator.translate(keyCode: 0, modifierFlags: .shift), .shortcut(GlobalShortcut(keyCode: 0, modifiers: .shift)))
        XCTAssertEqual(ShortcutEventTranslator.translate(keyCode: 0, modifierFlags: .command), .shortcut(GlobalShortcut(keyCode: 0, modifiers: .command)))
        XCTAssertEqual(ShortcutEventTranslator.translate(keyCode: 53, modifierFlags: []), .cancel)
        XCTAssertEqual(ShortcutEventTranslator.translate(keyCode: 51, modifierFlags: []), .reset)
        XCTAssertEqual(ShortcutEventTranslator.translate(keyCode: 56, modifierFlags: .command), .rejected)
        XCTAssertEqual(ShortcutEventTranslator.translate(keyCode: 0, modifierFlags: []), .rejected)
    }
}

@MainActor
private final class TestPermissionService: AccessibilityPermissionServicing {
    var state: AccessibilityPermissionState = .notDetermined
    var nextState: AccessibilityPermissionState = .granted
    var requestCount = 0
    var openCount = 0
    func refresh() -> AccessibilityPermissionState { state = nextState; return state }
    func request() -> AccessibilityPermissionState { requestCount += 1; state = nextState; return state }
    func openSystemSettings() -> Bool { openCount += 1; return true }
}

@MainActor
private final class TestShortcutService: GlobalShortcutManaging {
    var currentShortcut: GlobalShortcut?
    var registered: GlobalShortcut?
    var error: Error?
    func register(_ shortcut: GlobalShortcut, handler: @escaping @MainActor @Sendable () -> Void) throws {
        if let error { throw error }
        registered = shortcut
        currentShortcut = shortcut
    }
    func unregister() { currentShortcut = nil }
}
