import AppKit
import ApplicationServices
import CoreGraphics
import OSLog

enum WindowDiscoveryError: Error, Equatable {
    case accessibilityUnavailable
    case windowServerUnavailable
}

@MainActor
protocol WindowDetecting: AnyObject {
    func visibleTerminalWindows(on screen: ScreenDescriptor, includedBundleIdentifiers: Set<String>) throws -> [WindowDescriptor]
    func focusedWindowIdentifier(in windows: [WindowDescriptor]) -> WindowIdentifier?
    func selectionToken(for identifier: WindowIdentifier) -> WindowSelectionToken?
    func resolveSelectionToken(_ token: WindowSelectionToken, in windows: [WindowDescriptor]) -> WindowIdentifier?
    func windowUnderPointerIdentifier(in windows: [WindowDescriptor], at point: CGPoint) -> WindowIdentifier?
}

extension WindowDetecting {
    func focusedWindowIdentifier(in _: [WindowDescriptor]) -> WindowIdentifier? { nil }
    func selectionToken(for _: WindowIdentifier) -> WindowSelectionToken? { nil }
    func resolveSelectionToken(_: WindowSelectionToken, in _: [WindowDescriptor]) -> WindowIdentifier? { nil }
    func windowUnderPointerIdentifier(in _: [WindowDescriptor], at _: CGPoint) -> WindowIdentifier? { nil }
}

@MainActor
final class AXWindowHandleRegistry {
    private var handles: [WindowIdentifier: AXUIElement] = [:]

    func replaceAll(with handles: [WindowIdentifier: AXUIElement]) { self.handles = handles }
    func element(for identifier: WindowIdentifier) -> AXUIElement? { handles[identifier] }
    func remove(_ identifier: WindowIdentifier) { handles.removeValue(forKey: identifier) }
    func removeAll() { handles.removeAll() }
}

struct CGWindowSnapshot: Sendable {
    let ownerPID: Int32
    let bounds: CGRect
    let layer: Int
    let isOnScreen: Bool
    /// The public Core Graphics window number. Zero means that an injected
    /// legacy snapshot did not provide a selection identity.
    let windowNumber: CGWindowID

    init(ownerPID: Int32, bounds: CGRect, layer: Int, isOnScreen: Bool, windowNumber: CGWindowID = 0) {
        self.ownerPID = ownerPID
        self.bounds = bounds
        self.layer = layer
        self.isOnScreen = isOnScreen
        self.windowNumber = windowNumber
    }
}

struct WindowDiscoveryApplicationSnapshot: Sendable {
    let processIdentifier: Int32
    let bundleIdentifier: String?
    let isHidden: Bool
    let isTerminated: Bool
}

@MainActor
protocol WindowDiscoveryWorkspaceProviding: AnyObject {
    var runningApplications: [WindowDiscoveryApplicationSnapshot] { get }
    var frontmostApplicationProcessIdentifier: Int32? { get }
}

extension WindowDiscoveryWorkspaceProviding {
    var frontmostApplicationProcessIdentifier: Int32? { nil }
}

@MainActor
protocol WindowDiscoveryAXProviding: AnyObject {
    func applicationElement(for processIdentifier: Int32) -> AXUIElement
    func value(for attribute: String, of element: AXUIElement) -> Any?
    func axValue(for attribute: String, of element: AXUIElement) -> AXValue?
}

protocol WindowDiscoveryCGProviding: AnyObject {
    func snapshot() -> [CGWindowSnapshot]?
}

@MainActor
final class MacTerminalWindowDetector: WindowDetecting {
    private let workspace: WindowDiscoveryWorkspaceProviding
    private let ax: WindowDiscoveryAXProviding
    private let cg: WindowDiscoveryCGProviding
    private let trustChecker: () -> Bool
    let registry: AXWindowHandleRegistry
    private var focusedIdentifier: WindowIdentifier?
    private var selectionTokens: [WindowIdentifier: WindowSelectionToken] = [:]
    private var snapshotsByIdentifier: [WindowIdentifier: CGWindowSnapshot] = [:]
    /// CG's on-screen list is front-to-back. Keep this independently of the
    /// deterministic geometric order returned to callers for pointer hit tests.
    private var cgFrontToBackIdentifiers: [WindowIdentifier] = []
    private let logger = Logger(subsystem: "app.schiera.Schiera", category: "window-discovery")

    init(workspace: WindowDiscoveryWorkspaceProviding, ax: WindowDiscoveryAXProviding,
         cg: WindowDiscoveryCGProviding, registry: AXWindowHandleRegistry,
         trustChecker: @escaping () -> Bool = {
             AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary)
         }) {
        self.workspace = workspace; self.ax = ax; self.cg = cg; self.registry = registry; self.trustChecker = trustChecker
    }

    convenience init(workspace: WindowDiscoveryWorkspaceProviding, ax: WindowDiscoveryAXProviding,
         cg: WindowDiscoveryCGProviding, trustChecker: @escaping () -> Bool = {
             AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary)
         }) {
        self.init(workspace: workspace, ax: ax, cg: cg, registry: AXWindowHandleRegistry(), trustChecker: trustChecker)
    }

    convenience init(registry: AXWindowHandleRegistry) {
        self.init(workspace: LiveWindowDiscoveryWorkspace(), ax: LiveWindowDiscoveryAX(),
                  cg: LiveWindowDiscoveryCG(), registry: registry)
    }

    convenience init() {
        self.init(registry: AXWindowHandleRegistry())
    }

    func visibleTerminalWindows(on screen: ScreenDescriptor, includedBundleIdentifiers: Set<String>) throws -> [WindowDescriptor] {
        focusedIdentifier = nil
        clearSelectionMetadata()
        guard !includedBundleIdentifiers.isEmpty else { registry.removeAll(); return [] }
        guard trustChecker() else {
            registry.removeAll(); throw WindowDiscoveryError.accessibilityUnavailable
        }
        guard let entries = cg.snapshot() else { registry.removeAll(); throw WindowDiscoveryError.windowServerUnavailable }
        var candidates = entries.enumerated().compactMap { index, entry -> (index: Int, snapshot: CGWindowSnapshot)? in
            guard entry.layer == 0, entry.isOnScreen, entry.ownerPID > 0, valid(entry.bounds) else { return nil }
            return (index: index, snapshot: entry)
        }
        var result: [WindowDescriptor] = []
        var newHandles: [WindowIdentifier: AXUIElement] = [:]
        var cgOrderByIdentifier: [WindowIdentifier: Int] = [:]
        let frontmostProcessIdentifier = workspace.frontmostApplicationProcessIdentifier
        for application in workspace.runningApplications {
            guard let bundle = application.bundleIdentifier, includedBundleIdentifiers.contains(bundle),
                  !application.isHidden, !application.isTerminated else { continue }
            let appElement = ax.applicationElement(for: application.processIdentifier)
            if boolValue(ax.value(for: kAXHiddenAttribute as String, of: appElement)) == true { continue }
            guard let windows = ax.value(for: kAXWindowsAttribute as String, of: appElement) as? [AXUIElement] else { continue }
            let focusedElement = frontmostProcessIdentifier == application.processIdentifier
                ? elementValue(for: kAXFocusedWindowAttribute as String, of: appElement)
                : nil
            for window in windows {
                guard ax.value(for: kAXRoleAttribute as String, of: window) as? String == kAXWindowRole,
                      ax.value(for: kAXSubroleAttribute as String, of: window) as? String == kAXStandardWindowSubrole,
                      boolValue(ax.value(for: kAXMinimizedAttribute as String, of: window)) != true,
                      let frame = frame(of: window), screen.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) else { continue }
                guard let index = candidates.firstIndex(where: { $0.snapshot.ownerPID == application.processIdentifier && close($0.snapshot.bounds, frame) }) else { continue }
                let matchedCandidate = candidates.remove(at: index)
                let matchedSnapshot = matchedCandidate.snapshot
                let id = WindowIdentifier(token: UUID(), processIdentifier: application.processIdentifier)
                result.append(WindowDescriptor(id: id, bundleIdentifier: bundle, title: nil, frame: frame,
                                               windowNumber: matchedSnapshot.windowNumber == 0 ? nil : matchedSnapshot.windowNumber))
                newHandles[id] = window
                let token = WindowSelectionToken(processIdentifier: application.processIdentifier, windowNumber: matchedSnapshot.windowNumber)
                selectionTokens[id] = token
                snapshotsByIdentifier[id] = matchedSnapshot
                cgFrontToBackIdentifiers.append(id)
                cgOrderByIdentifier[id] = matchedCandidate.index
                if let focusedElement, CFEqual(focusedElement, window) {
                    focusedIdentifier = id
                }
            }
        }
        result.sort { lhs, rhs in
            if lhs.frame.minX != rhs.frame.minX { return lhs.frame.minX < rhs.frame.minX }
            if lhs.frame.minY != rhs.frame.minY { return lhs.frame.minY < rhs.frame.minY }
            if lhs.id.processIdentifier != rhs.id.processIdentifier { return lhs.id.processIdentifier < rhs.id.processIdentifier }
            return lhs.id.token.uuidString < rhs.id.token.uuidString
        }
        cgFrontToBackIdentifiers.sort {
            cgOrderByIdentifier[$0, default: Int.max] < cgOrderByIdentifier[$1, default: Int.max]
        }
        registry.replaceAll(with: newHandles)
        logger.debug("Window discovery found \(result.count, privacy: .public) windows")
        return result
    }

    func focusedWindowIdentifier(in windows: [WindowDescriptor]) -> WindowIdentifier? {
        guard let focusedIdentifier,
              windows.contains(where: { $0.id == focusedIdentifier }) else { return nil }
        return focusedIdentifier
    }

    func selectionToken(for identifier: WindowIdentifier) -> WindowSelectionToken? {
        guard identifier.processIdentifier == selectionTokens[identifier]?.processIdentifier,
              let token = selectionTokens[identifier], token.windowNumber != 0 else { return nil }
        return token
    }

    func resolveSelectionToken(_ token: WindowSelectionToken, in windows: [WindowDescriptor]) -> WindowIdentifier? {
        guard token.windowNumber != 0 else { return nil }
        let allowed = Set(windows.map(\.id))
        return selectionTokens.first(where: { identifier, candidate in
            allowed.contains(identifier) && candidate == token
        })?.key
    }

    func windowUnderPointerIdentifier(in windows: [WindowDescriptor], at point: CGPoint) -> WindowIdentifier? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        let allowed = Set(windows.map(\.id))
        for identifier in cgFrontToBackIdentifiers where allowed.contains(identifier) {
            guard let bounds = snapshotsByIdentifier[identifier]?.bounds, valid(bounds) else { continue }
            // Use half-open containment so shared edges resolve consistently.
            guard point.x >= bounds.minX, point.x < bounds.maxX,
                  point.y >= bounds.minY, point.y < bounds.maxY else { continue }
            return identifier
        }
        return nil
    }

    private func clearSelectionMetadata() {
        selectionTokens.removeAll(keepingCapacity: true)
        snapshotsByIdentifier.removeAll(keepingCapacity: true)
        cgFrontToBackIdentifiers.removeAll(keepingCapacity: true)
    }

    private func valid(_ rect: CGRect) -> Bool { rect.origin.x.isFinite && rect.origin.y.isFinite && rect.width.isFinite && rect.height.isFinite && rect.width > 0 && rect.height > 0 }
    private func close(_ a: CGRect, _ b: CGRect) -> Bool { abs(a.minX-b.minX) <= 2 && abs(a.minY-b.minY) <= 2 && abs(a.width-b.width) <= 2 && abs(a.height-b.height) <= 2 }
    private func boolValue(_ value: Any?) -> Bool? { value as? Bool }
    private func elementValue(for attribute: String, of element: AXUIElement) -> AXUIElement? {
        guard let value = ax.value(for: attribute, of: element) else { return nil }
        let object = value as AnyObject
        guard CFGetTypeID(object) == AXUIElementGetTypeID() else { return nil }
        return Unmanaged<AXUIElement>.fromOpaque(Unmanaged.passUnretained(object).toOpaque()).takeUnretainedValue()
    }
    private func frame(of element: AXUIElement) -> CGRect? {
        guard let position = ax.axValue(for: kAXPositionAttribute as String, of: element),
              let size = ax.axValue(for: kAXSizeAttribute as String, of: element),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero; var dimensions = CGSize.zero
        guard AXValueGetType(position) == .cgPoint, AXValueGetType(size) == .cgSize,
              AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &dimensions) else { return nil }
        let rect = CGRect(origin: point, size: dimensions)
        return valid(rect) ? rect : nil
    }
}

@MainActor private final class LiveWindowDiscoveryWorkspace: NSObject, WindowDiscoveryWorkspaceProviding {
    private var lastExternalApplicationProcessIdentifier: Int32?

    override init() {
        let current = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let own = ProcessInfo.processInfo.processIdentifier
        lastExternalApplicationProcessIdentifier = current == own ? nil : current
        super.init()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    var frontmostApplicationProcessIdentifier: Int32? {
        let current = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let own = ProcessInfo.processInfo.processIdentifier
        if let current, current != own {
            lastExternalApplicationProcessIdentifier = current
            return current
        }
        return lastExternalApplicationProcessIdentifier
    }

    @objc private func applicationDidActivate(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        lastExternalApplicationProcessIdentifier = application.processIdentifier
    }

    var runningApplications: [WindowDiscoveryApplicationSnapshot] {
        NSWorkspace.shared.runningApplications.map {
            WindowDiscoveryApplicationSnapshot(processIdentifier: $0.processIdentifier, bundleIdentifier: $0.bundleIdentifier,
                                               isHidden: $0.isHidden, isTerminated: $0.isTerminated)
        }
    }
}
@MainActor private final class LiveWindowDiscoveryAX: WindowDiscoveryAXProviding {
    func applicationElement(for processIdentifier: Int32) -> AXUIElement { AXUIElementCreateApplication(processIdentifier) }
    func value(for attribute: String, of element: AXUIElement) -> Any? { var value: CFTypeRef?; return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil }
    func axValue(for attribute: String, of element: AXUIElement) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        // The CFTypeID check above establishes that this opaque CF object is an AXValue.
        // Preserve the retained CF object without a forced or conditional cast.
        return Unmanaged<AXValue>.fromOpaque(Unmanaged.passUnretained(value).toOpaque()).takeUnretainedValue()
    }
}
private final class LiveWindowDiscoveryCG: WindowDiscoveryCGProviding {
    func snapshot() -> [CGWindowSnapshot]? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        return list.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32, let layer = info[kCGWindowLayer as String] as? Int,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary, let rect = CGRect(dictionaryRepresentation: bounds) else { return nil }
            let number = (info[kCGWindowNumber as String] as? NSNumber).map { CGWindowID(truncating: $0) } ?? 0
            return CGWindowSnapshot(ownerPID: pid, bounds: rect, layer: layer,
                                    isOnScreen: (info[kCGWindowIsOnscreen as String] as? Bool) ?? false,
                                    windowNumber: number)
        }
    }
}
