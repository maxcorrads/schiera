# Frozen implementation contracts

These declarations describe required names, cases, fields, and semantics. The owning task creates the actual Swift declarations. Other tasks code against them immediately. Access control may remain `internal` because production code and tests use `@testable import Schiera`.

## Core value types — owned by TASK-02

```swift
import CoreGraphics
import Foundation

struct ScreenDescriptor: Equatable, Sendable {
    let displayID: UInt32
    let frame: CGRect          // AX global coordinates
    let visibleFrame: CGRect   // AX global coordinates
}

struct WindowIdentifier: Hashable, Sendable {
    let token: UUID
    let processIdentifier: Int32
}

struct WindowDescriptor: Equatable, Sendable {
    let id: WindowIdentifier
    let bundleIdentifier: String
    let title: String?
    let frame: CGRect          // AX global coordinates
}

struct TerminalApplicationDefinition: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let displayName: String
    let bundleIdentifiers: Set<String>
    let defaultEnabled: Bool
}

struct ShortcutModifiers: OptionSet, Hashable, Codable, Sendable {
    let rawValue: UInt32
    static let control: ShortcutModifiers
    static let option: ShortcutModifiers
    static let shift: ShortcutModifiers
    static let command: ShortcutModifiers
}

struct GlobalShortcut: Hashable, Codable, Sendable {
    let keyCode: UInt32
    let modifiers: ShortcutModifiers
    static let defaultSchiera: GlobalShortcut
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

enum ArrangementOutcome: Equatable, Sendable {
    case insufficientWindows(count: Int)
    case invalidGeometry
    case completed(moved: Int, failed: Int)
}

enum RestoreOutcome: Equatable, Sendable {
    case nothingToRestore
    case completed(restored: Int, failed: Int)
}
```

`GlobalShortcut.defaultSchiera` is key code `1` with `[.control, .option, .command]`. Modifier raw values are Schiera-owned stable bits: control `1 << 0`, option `1 << 1`, shift `1 << 2`, command `1 << 3`; never persist Carbon or AppKit masks directly.

## Layout calculation — owned by TASK-02

```swift
protocol LayoutCalculating: Sendable {
    func frames(in visibleFrame: CGRect, windowCount: Int, gap: CGFloat) throws -> [CGRect]
}

struct HorizontalLayoutCalculator: LayoutCalculating, Sendable {
    func frames(in visibleFrame: CGRect, windowCount: Int, gap: CGFloat) throws -> [CGRect]
}
```

Follow the exact algorithm and error rules in `PROJECT_SPEC.md`. A count of zero returns `[]`; a count of one returns the integral visible frame.

## Screen detection — owned by TASK-03

```swift
@MainActor
protocol ScreenDetecting: AnyObject {
    func screenUnderPointer() -> ScreenDescriptor?
}

struct ScreenCoordinateConverter: Sendable {
    func accessibilityRect(fromAppKit rect: CGRect, primaryScreenFrame: CGRect) -> CGRect
}

@MainActor
final class MacScreenDetector: ScreenDetecting {
    func screenUnderPointer() -> ScreenDescriptor?
}
```

`MacScreenDetector` must have an internal injectable screen-snapshot provider initializer for unit tests and a convenience/live initializer for production.

## Accessibility permission — owned by TASK-04

```swift
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
}
```

The concrete service has injectable trust checking, URL opening, and `UserDefaults` adapters. The stable prompt marker key is `accessibilityPromptWasRequested`.

## Window discovery — owned by TASK-05

```swift
enum WindowDiscoveryError: Error, Equatable {
    case accessibilityUnavailable
    case windowServerUnavailable
}

@MainActor
protocol WindowDetecting: AnyObject {
    func visibleTerminalWindows(
        on screen: ScreenDescriptor,
        includedBundleIdentifiers: Set<String>
    ) throws -> [WindowDescriptor]
}

@MainActor
final class AXWindowHandleRegistry {
    func replaceAll(with handles: [WindowIdentifier: AXUIElement])
    func element(for identifier: WindowIdentifier) -> AXUIElement?
    func remove(_ identifier: WindowIdentifier)
    func removeAll()
}

@MainActor
final class MacTerminalWindowDetector: WindowDetecting {
    // Production and internal dependency-injected initializers.
}
```

`MacTerminalWindowDetector` uses `NSWorkspace`, AX, and CG snapshot adapters. It must not require Screen Recording permission and must not use window titles for logging.

## Layout application and restore — owned by TASK-06

```swift
@MainActor
protocol WindowFrameControlling: AnyObject {
    func setFrame(_ frame: CGRect, for window: WindowIdentifier) throws
}

@MainActor
protocol LayoutApplying: AnyObject {
    var canRestore: Bool { get }
    func arrange(windows: [WindowDescriptor], in visibleFrame: CGRect, gap: CGFloat) -> ArrangementOutcome
    func restore() -> RestoreOutcome
}

@MainActor
final class AccessibilityWindowFrameController: WindowFrameControlling {
    init(registry: AXWindowHandleRegistry)
}

@MainActor
final class LayoutService: LayoutApplying {
    init(calculator: any LayoutCalculating, frameController: any WindowFrameControlling)
}
```

The service follows the snapshot lifecycle in `ARCHITECTURE.md`. `canRestore` changes synchronously.

## Preferences and catalog — owned by TASK-07

```swift
enum PreferenceConstraints {
    static let defaultGap: Double       // 8
    static let minimumGap: Double       // 0
    static let maximumGap: Double       // 64
}

enum TerminalCatalog {
    static let applications: [TerminalApplicationDefinition]
    static var defaultIncludedIDs: Set<String> { get }
    static func bundleIdentifiers(forIncludedIDs ids: Set<String>) -> Set<String>
}

@MainActor
protocol PreferencesProviding: AnyObject {
    var gap: Double { get set }
    var includedTerminalIDs: Set<String> { get set }
    var shortcut: GlobalShortcut { get set }
    func reset()
}

@MainActor
final class PreferencesStore: ObservableObject, PreferencesProviding {
    @Published var gap: Double
    @Published var includedTerminalIDs: Set<String>
    @Published var shortcut: GlobalShortcut
    init(defaults: UserDefaults = .standard)
    func reset()
}
```

Stable keys are `windowGap`, `includedTerminalIDs`, and `globalShortcut`. Invalid decoded values fall back independently rather than resetting all preferences.

## Global shortcut — owned by TASK-08

```swift
enum GlobalShortcutError: Error, Equatable, LocalizedError {
    case invalidShortcut
    case registrationFailed(status: Int32)
    case handlerInstallationFailed(status: Int32)
}

@MainActor
protocol GlobalShortcutManaging: AnyObject {
    var currentShortcut: GlobalShortcut? { get }
    func register(
        _ shortcut: GlobalShortcut,
        handler: @escaping @MainActor @Sendable () -> Void
    ) throws
    func unregister()
}

@MainActor
final class CarbonGlobalShortcutService: GlobalShortcutManaging {
    // Live initializer plus an internal injectable Carbon backend initializer.
}

enum ShortcutDisplayFormatter {
    static func string(for shortcut: GlobalShortcut) -> String
}
```

At least one supported modifier and a non-modifier virtual key code in `0...127` are required. The formatter order is Control, Option, Shift, Command, key.

## Settings UI — owned by TASK-09

```swift
@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var shortcutDraft: GlobalShortcut
    @Published private(set) var shortcutError: String?
    @Published private(set) var permissionState: AccessibilityPermissionState
    let preferences: PreferencesStore
    let permissionService: any AccessibilityPermissionServicing
    let shortcutService: any GlobalShortcutManaging

    init(
        preferences: PreferencesStore,
        permissionService: any AccessibilityPermissionServicing,
        shortcutService: any GlobalShortcutManaging,
        shortcutHandler: @escaping @MainActor @Sendable () -> Void
    )
    func commitShortcut(_ shortcut: GlobalShortcut)
    func refreshPermission()
    func requestPermission()
    func openAccessibilitySettings()
}

struct SettingsView: View {
    init(model: SettingsViewModel)
}

struct ShortcutRecorderView: View {
    @Binding var shortcut: GlobalShortcut
}
```

`SettingsViewModel.commitShortcut` registers first with the injected `shortcutHandler` and persists only on success. On failure it leaves the working registration and persisted shortcut unchanged. TASK-10 wires the handler through a weak action relay to `AppModel.arrange()` so TASK-09 never depends on an initialized `AppModel` instance.

## App orchestration and menu — owned by TASK-10

```swift
enum AppFeedback: Equatable {
    case ready
    case permissionRequired(AccessibilityPermissionState)
    case noTargetScreen
    case insufficientWindows(Int)
    case arranged(moved: Int, failed: Int)
    case restored(restored: Int, failed: Int)
    case nothingToRestore
    case failed(String)
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var permissionState: AccessibilityPermissionState
    @Published private(set) var feedback: AppFeedback
    @Published private(set) var canRestore: Bool
    let settingsViewModel: SettingsViewModel

    static func live() -> AppModel
    func start()
    func arrange()
    func restore()
    func requestAccessibilityPermission()
    func openAccessibilitySettings()
    func quit()
}

struct MenuBarContentView: View {
    @ObservedObject var model: AppModel
}
```

The dependency-injected `AppModel` initializer may be internal and is required for unit tests. `start()` is idempotent, refreshes permission, and registers the persisted shortcut.

## App entry point — owned by TASK-01

`SchieraApp` owns one `@StateObject` created with `AppModel.live()`, provides a `MenuBarExtra("Schiera", systemImage: "rectangle.split.3x1")` containing `MenuBarContentView`, provides a `Settings` scene containing `SettingsView(model: model.settingsViewModel)`, and calls `model.start()` once through an app-lifecycle-safe mechanism.
