import ApplicationServices
import XCTest
@testable import Schiera

@MainActor
final class WindowDiscoveryTests: XCTestCase {
    private func detector(apps: [WindowDiscoveryApplicationSnapshot], ax: FakeAX, entries: [CGWindowSnapshot]?, registry: AXWindowHandleRegistry? = nil, frontmostPID: Int32? = nil) -> MacTerminalWindowDetector {
        MacTerminalWindowDetector(workspace: FakeWorkspace(apps: apps, frontmostPID: frontmostPID), ax: ax, cg: FakeCG(entries: entries), registry: registry ?? AXWindowHandleRegistry(), trustChecker: { true })
    }

    private func screen() -> ScreenDescriptor { ScreenDescriptor(displayID: 1, frame: CGRect(x: -100, y: -50, width: 1_000, height: 800), visibleFrame: CGRect(x: -100, y: -50, width: 1_000, height: 800)) }

    func testDetectorFiltersAppsAndAXWindowAttributes() throws {
        let ax = FakeAX()
        let app = ax.addApplication(pid: 10, hidden: false)
        _ = ax.addWindow(app: app, frame: CGRect(x: 0, y: 0, width: 100, height: 100), role: kAXWindowRole, subrole: kAXStandardWindowSubrole)
        let apps = [WindowDiscoveryApplicationSnapshot(processIdentifier: 10, bundleIdentifier: "com.apple.Terminal", isHidden: false, isTerminated: false),
                    WindowDiscoveryApplicationSnapshot(processIdentifier: 11, bundleIdentifier: "excluded", isHidden: false, isTerminated: false),
                    WindowDiscoveryApplicationSnapshot(processIdentifier: 12, bundleIdentifier: "com.apple.Terminal", isHidden: true, isTerminated: false),
                    WindowDiscoveryApplicationSnapshot(processIdentifier: 13, bundleIdentifier: "com.apple.Terminal", isHidden: false, isTerminated: true)]
        let entries = [CGWindowSnapshot(ownerPID: 10, bounds: CGRect(x: 0, y: 0, width: 100, height: 100), layer: 0, isOnScreen: true)]
        let result = try detector(apps: apps, ax: ax, entries: entries).visibleTerminalWindows(on: screen(), includedBundleIdentifiers: ["com.apple.Terminal"])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(ax.enumeratedPIDs, [10])
    }

    func testDetectorCorrelationToleranceAndSingleEntryConsumption() throws {
        let ax = FakeAX(); let app = ax.addApplication(pid: 20, hidden: false)
        _ = ax.addWindow(app: app, frame: CGRect(x: 100, y: 100, width: 200, height: 200), role: kAXWindowRole, subrole: kAXStandardWindowSubrole)
        _ = ax.addWindow(app: app, frame: CGRect(x: 102, y: 100, width: 200, height: 200), role: kAXWindowRole, subrole: kAXStandardWindowSubrole)
        let apps = [WindowDiscoveryApplicationSnapshot(processIdentifier: 20, bundleIdentifier: "com.googlecode.iterm2", isHidden: false, isTerminated: false)]
        let entry = [CGWindowSnapshot(ownerPID: 20, bounds: CGRect(x: 102, y: 102, width: 200, height: 200), layer: 0, isOnScreen: true)]
        let result = try detector(apps: apps, ax: ax, entries: entry).visibleTerminalWindows(on: screen(), includedBundleIdentifiers: ["com.googlecode.iterm2"])
        XCTAssertEqual(result.count, 1)
    }

    func testMalformedAXGeometryIsSkipped() throws {
        let ax = FakeAX(); let app = ax.addApplication(pid: 21, hidden: false)
        ax.addMalformedWindow(app: app)
        let apps = [WindowDiscoveryApplicationSnapshot(processIdentifier: 21, bundleIdentifier: "com.apple.Terminal", isHidden: false, isTerminated: false)]
        let entries = [CGWindowSnapshot(ownerPID: 21, bounds: CGRect(x: 0, y: 0, width: 100, height: 100), layer: 0, isOnScreen: true)]
        let result = try detector(apps: apps, ax: ax, entries: entries).visibleTerminalWindows(on: screen(), includedBundleIdentifiers: ["com.apple.Terminal"])
        XCTAssertTrue(result.isEmpty)
    }

    func testDetectorSkipsMismatchAndOutOfScreenCenterAndSorts() throws {
        let ax = FakeAX(); let app = ax.addApplication(pid: 30, hidden: false)
        _ = ax.addWindow(app: app, frame: CGRect(x: 300, y: 100, width: 100, height: 100), role: kAXWindowRole, subrole: kAXStandardWindowSubrole)
        _ = ax.addWindow(app: app, frame: CGRect(x: -90, y: -40, width: 40, height: 40), role: kAXWindowRole, subrole: kAXStandardWindowSubrole)
        let apps = [WindowDiscoveryApplicationSnapshot(processIdentifier: 30, bundleIdentifier: "dev.warp.Warp", isHidden: false, isTerminated: false)]
        let entries = [CGWindowSnapshot(ownerPID: 30, bounds: CGRect(x: 300, y: 100, width: 100, height: 100), layer: 0, isOnScreen: true),
                       CGWindowSnapshot(ownerPID: 30, bounds: CGRect(x: 0, y: 0, width: 100, height: 100), layer: 1, isOnScreen: true)]
        let result = try detector(apps: apps, ax: ax, entries: entries).visibleTerminalWindows(on: screen(), includedBundleIdentifiers: ["dev.warp.Warp"])
        XCTAssertEqual(result.map(\.frame.minX), [300])
    }

    func testWindowServerFailureClearsRegistryAndThrows() {
        let registry = AXWindowHandleRegistry(); let old = WindowIdentifier(token: UUID(), processIdentifier: 1)
        registry.replaceAll(with: [old: AXUIElementCreateApplication(1)])
        let ax = FakeAX(); let detector = detector(apps: [], ax: ax, entries: nil, registry: registry)
        XCTAssertThrowsError(try detector.visibleTerminalWindows(on: screen(), includedBundleIdentifiers: ["com.apple.Terminal"])) { error in XCTAssertEqual(error as? WindowDiscoveryError, .windowServerUnavailable) }
        XCTAssertNil(registry.element(for: old))
    }
    func testRegistryReplaceRemoveAndClear() {
        let registry = AXWindowHandleRegistry()
        let first = WindowIdentifier(token: UUID(), processIdentifier: 101)
        let second = WindowIdentifier(token: UUID(), processIdentifier: 202)
        let firstElement = AXUIElementCreateApplication(first.processIdentifier)
        let secondElement = AXUIElementCreateApplication(second.processIdentifier)

        registry.replaceAll(with: [first: firstElement, second: secondElement])
        XCTAssertNotNil(registry.element(for: first))
        XCTAssertNotNil(registry.element(for: second))

        registry.remove(first)
        XCTAssertNil(registry.element(for: first))
        XCTAssertNotNil(registry.element(for: second))

        registry.removeAll()
        XCTAssertNil(registry.element(for: second))
    }

    func testRegistryReplacementDiscardsStaleEntries() {
        let registry = AXWindowHandleRegistry()
        let stale = WindowIdentifier(token: UUID(), processIdentifier: 1)
        let current = WindowIdentifier(token: UUID(), processIdentifier: 2)
        registry.replaceAll(with: [stale: AXUIElementCreateApplication(1)])
        registry.replaceAll(with: [current: AXUIElementCreateApplication(2)])

        XCTAssertNil(registry.element(for: stale))
        XCTAssertNotNil(registry.element(for: current))
    }

    func testSnapshotPreservesNegativeCoordinatesAndToleranceInputs() {
        let snapshot = CGWindowSnapshot(ownerPID: 42, bounds: CGRect(x: -120, y: -30, width: 800, height: 600), layer: 0, isOnScreen: true)
        XCTAssertEqual(snapshot.ownerPID, 42)
        XCTAssertEqual(snapshot.bounds.minX, -120)
        XCTAssertTrue(snapshot.isOnScreen)
        XCTAssertEqual(snapshot.layer, 0)
    }

    func testFocusedWindowIdentifierComesFromFrontmostTerminal() throws {
        let ax = FakeAX()
        let app = ax.addApplication(pid: 50, hidden: false)
        _ = ax.addWindow(app: app, frame: CGRect(x: 0, y: 0, width: 100, height: 100), role: kAXWindowRole, subrole: kAXStandardWindowSubrole)
        let focused = ax.addWindow(app: app, frame: CGRect(x: 120, y: 0, width: 100, height: 100), role: kAXWindowRole, subrole: kAXStandardWindowSubrole)
        ax.setFocusedWindow(focused, for: app)
        let apps = [WindowDiscoveryApplicationSnapshot(processIdentifier: 50, bundleIdentifier: "com.apple.Terminal", isHidden: false, isTerminated: false)]
        let entries = [
            CGWindowSnapshot(ownerPID: 50, bounds: CGRect(x: 0, y: 0, width: 100, height: 100), layer: 0, isOnScreen: true),
            CGWindowSnapshot(ownerPID: 50, bounds: CGRect(x: 120, y: 0, width: 100, height: 100), layer: 0, isOnScreen: true)
        ]
        let detector = detector(apps: apps, ax: ax, entries: entries, frontmostPID: 50)

        let windows = try detector.visibleTerminalWindows(on: screen(), includedBundleIdentifiers: ["com.apple.Terminal"])

        XCTAssertEqual(detector.focusedWindowIdentifier(in: windows), windows[1].id)
    }

    func testSelectionTokenUsesPIDAndWindowNumberAcrossFreshScans() throws {
        let ax = FakeAX()
        let app = ax.addApplication(pid: 60, hidden: false)
        _ = ax.addWindow(app: app, frame: CGRect(x: 0, y: 0, width: 100, height: 100), role: kAXWindowRole, subrole: kAXStandardWindowSubrole)
        _ = ax.addWindow(app: app, frame: CGRect(x: 120, y: 0, width: 100, height: 100), role: kAXWindowRole, subrole: kAXStandardWindowSubrole)
        let apps = [WindowDiscoveryApplicationSnapshot(processIdentifier: 60, bundleIdentifier: "com.apple.Terminal", isHidden: false, isTerminated: false)]
        let entries = [
            CGWindowSnapshot(ownerPID: 60, bounds: CGRect(x: 0, y: 0, width: 100, height: 100), layer: 0, isOnScreen: true, windowNumber: 601),
            CGWindowSnapshot(ownerPID: 60, bounds: CGRect(x: 120, y: 0, width: 100, height: 100), layer: 0, isOnScreen: true, windowNumber: 602)
        ]
        let detector = detector(apps: apps, ax: ax, entries: entries)

        let firstScan = try detector.visibleTerminalWindows(on: screen(), includedBundleIdentifiers: ["com.apple.Terminal"])
        let token = try XCTUnwrap(detector.selectionToken(for: firstScan[1].id))
        XCTAssertEqual(token, WindowSelectionToken(processIdentifier: 60, windowNumber: 602))

        let freshScan = try detector.visibleTerminalWindows(on: screen(), includedBundleIdentifiers: ["com.apple.Terminal"])
        XCTAssertNotEqual(firstScan[1].id, freshScan[1].id)
        XCTAssertEqual(detector.resolveSelectionToken(token, in: freshScan), freshScan[1].id)
        XCTAssertNil(detector.resolveSelectionToken(WindowSelectionToken(processIdentifier: 61, windowNumber: 602), in: freshScan))
        XCTAssertNil(detector.resolveSelectionToken(WindowSelectionToken(processIdentifier: 60, windowNumber: 603), in: freshScan))
    }

    func testPointerSelectionUsesCGFrontToBackAndHalfOpenEdges() throws {
        let ax = FakeAX()
        let app = ax.addApplication(pid: 70, hidden: false)
        _ = ax.addWindow(app: app, frame: CGRect(x: 0, y: 0, width: 200, height: 200), role: kAXWindowRole, subrole: kAXStandardWindowSubrole)
        _ = ax.addWindow(app: app, frame: CGRect(x: 100, y: 100, width: 200, height: 200), role: kAXWindowRole, subrole: kAXStandardWindowSubrole)
        let apps = [WindowDiscoveryApplicationSnapshot(processIdentifier: 70, bundleIdentifier: "com.apple.Terminal", isHidden: false, isTerminated: false)]
        // The second AX window is in front in CG order even though the AX list
        // and returned result are deterministic by geometry.
        let entries = [
            CGWindowSnapshot(ownerPID: 70, bounds: CGRect(x: 100, y: 100, width: 200, height: 200), layer: 0, isOnScreen: true, windowNumber: 701),
            CGWindowSnapshot(ownerPID: 70, bounds: CGRect(x: 0, y: 0, width: 200, height: 200), layer: 0, isOnScreen: true, windowNumber: 702),
            CGWindowSnapshot(ownerPID: 99, bounds: CGRect(x: 100, y: 100, width: 200, height: 200), layer: 0, isOnScreen: true, windowNumber: 799)
        ]
        let detector = detector(apps: apps, ax: ax, entries: entries)
        let windows = try detector.visibleTerminalWindows(on: screen(), includedBundleIdentifiers: ["com.apple.Terminal"])

        let overlap = try XCTUnwrap(detector.windowUnderPointerIdentifier(in: windows, at: CGPoint(x: 150, y: 150)))
        XCTAssertEqual(windows.first(where: { $0.frame.minX == 100 })?.id, overlap)
        let sharedEdge = try XCTUnwrap(detector.windowUnderPointerIdentifier(in: windows, at: CGPoint(x: 200, y: 150)))
        XCTAssertEqual(windows.first(where: { $0.frame.minX == 100 })?.id, sharedEdge)
        XCTAssertNil(detector.windowUnderPointerIdentifier(in: windows, at: CGPoint(x: 301, y: 150)))
        XCTAssertNil(detector.windowUnderPointerIdentifier(in: windows, at: CGPoint(x: CGFloat.nan, y: 150)))
    }

    func testLegacySnapshotInitializerKeepsZeroSelectionNumber() {
        let snapshot = CGWindowSnapshot(ownerPID: 80, bounds: .zero, layer: 0, isOnScreen: false)
        XCTAssertEqual(snapshot.windowNumber, 0)
    }
}

@MainActor private final class FakeWorkspace: WindowDiscoveryWorkspaceProviding {
    let apps: [WindowDiscoveryApplicationSnapshot]
    let frontmostPID: Int32?
    init(apps: [WindowDiscoveryApplicationSnapshot], frontmostPID: Int32? = nil) {
        self.apps = apps
        self.frontmostPID = frontmostPID
    }
    var runningApplications: [WindowDiscoveryApplicationSnapshot] { apps }
    var frontmostApplicationProcessIdentifier: Int32? { frontmostPID }
}
private final class FakeCG: WindowDiscoveryCGProviding {
    let entries: [CGWindowSnapshot]?; init(entries: [CGWindowSnapshot]?) { self.entries = entries }
    func snapshot() -> [CGWindowSnapshot]? { entries }
}
@MainActor private final class FakeAX: WindowDiscoveryAXProviding {
    private var values: [Int: [String: Any]] = [:]; private var typedValues: [Int: [String: AXValue]] = [:]; private(set) var enumeratedPIDs: [Int32] = []
    private var applications: [Int32: AXUIElement] = [:]
    private func key(_ element: AXUIElement) -> Int { Int(CFHash(element)) }
    func addApplication(pid: Int32, hidden: Bool) -> AXUIElement { let e = AXUIElementCreateApplication(pid); applications[pid] = e; values[key(e)] = [kAXHiddenAttribute as String: hidden]; return e }
    func addWindow(app: AXUIElement, frame: CGRect, role: String, subrole: String) -> AXUIElement {
        let w = AXUIElementCreateApplication(Int32(values.count + 1000)); var p = frame.origin; var s = frame.size
        guard let position = AXValueCreate(.cgPoint, &p), let size = AXValueCreate(.cgSize, &s) else { return w }
        values[key(w)] = [kAXRoleAttribute as String: role, kAXSubroleAttribute as String: subrole]; typedValues[key(w)] = [kAXPositionAttribute as String: position, kAXSizeAttribute as String: size]
        var windows = (values[key(app)]?[kAXWindowsAttribute as String] as? [AXUIElement]) ?? []; windows.append(w); values[key(app)]?[kAXWindowsAttribute as String] = windows; return w
    }
    func addMalformedWindow(app: AXUIElement) {
        let w = AXUIElementCreateApplication(Int32(values.count + 1000)); values[key(w)] = [kAXRoleAttribute as String: kAXWindowRole, kAXSubroleAttribute as String: kAXStandardWindowSubrole, kAXPositionAttribute as String: "bad", kAXSizeAttribute as String: "bad"]; var windows = (values[key(app)]?[kAXWindowsAttribute as String] as? [AXUIElement]) ?? []; windows.append(w); values[key(app)]?[kAXWindowsAttribute as String] = windows
    }
    func setFocusedWindow(_ window: AXUIElement, for app: AXUIElement) {
        values[key(app)]?[kAXFocusedWindowAttribute as String] = window
    }
    func applicationElement(for processIdentifier: Int32) -> AXUIElement { enumeratedPIDs.append(processIdentifier); return applications[processIdentifier] ?? AXUIElementCreateApplication(processIdentifier) }
    func value(for attribute: String, of element: AXUIElement) -> Any? { values[key(element)]?[attribute] }
    func axValue(for attribute: String, of element: AXUIElement) -> AXValue? {
        typedValues[key(element)]?[attribute]
    }
}
