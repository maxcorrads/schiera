import AppKit
import CoreGraphics

/// The display information needed by the detector.  Values are copied from
/// NSScreen so tests do not need a live window server.
struct ScreenSnapshot: Sendable {
    struct Display: Sendable {
        let displayID: UInt32?
        /// The public Core Graphics display UUID, when the snapshot source can provide it.
        /// Test providers may leave this nil and exercise the numeric fallback binding.
        let uuid: String?
        let frame: CGRect
        let visibleFrame: CGRect

        init(displayID: UInt32?, uuid: String? = nil, frame: CGRect, visibleFrame: CGRect) {
            self.displayID = displayID
            self.uuid = uuid
            self.frame = frame
            self.visibleFrame = visibleFrame
        }
    }

    let pointerLocation: CGPoint
    let displays: [Display]
    let primaryFrame: CGRect?

    init(pointerLocation: CGPoint, displays: [Display], primaryFrame: CGRect?) {
        self.pointerLocation = pointerLocation
        self.displays = displays
        self.primaryFrame = primaryFrame
    }
}

@MainActor
protocol ScreenSnapshotProviding: AnyObject {
    func snapshot() -> ScreenSnapshot
}

@MainActor
private final class LiveScreenSnapshotProvider: ScreenSnapshotProviding {
    func snapshot() -> ScreenSnapshot {
        let screens = NSScreen.screens
        let displays = screens.map { screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            let id: UInt32?
            if let number, number.doubleValue.isFinite,
               number.doubleValue > 0,
               number.doubleValue <= Double(UInt32.max),
               number.doubleValue.rounded(.towardZero) == number.doubleValue {
                id = number.uint32Value
            } else {
                id = nil
            }
            // visibleFrame is intentionally read as part of every snapshot.
            return ScreenSnapshot.Display(
                displayID: id,
                uuid: id.flatMap(Self.uuidString(for:)),
                frame: screen.frame,
                visibleFrame: screen.visibleFrame
            )
        }
        return ScreenSnapshot(
            pointerLocation: NSEvent.mouseLocation,
            displays: displays,
            primaryFrame: screens.first?.frame
        )
    }

    private static func uuidString(for displayID: UInt32) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID) else { return nil }
        return CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String
    }
}

struct ScreenCoordinateConverter: Sendable {
    func accessibilityRect(fromAppKit rect: CGRect, primaryScreenFrame: CGRect) -> CGRect {
        CGRect(
            x: rect.minX,
            y: primaryScreenFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    func accessibilityPoint(fromAppKit point: CGPoint, primaryScreenFrame: CGRect) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenFrame.maxY - point.y)
    }
}

@MainActor
protocol ScreenDetecting: AnyObject {
    func screenUnderPointer() -> ScreenDescriptor?
    func targetUnderPointer() -> ScreenTarget?
    func screen(matching binding: DisplayBinding) -> ScreenDescriptor?
    func bindingForScreenUnderPointer() -> DisplayBinding?
}

/// Additive defaults keep existing test and platform conformers source-compatible while
/// allowing callers that need monitor context to opt into the richer APIs.
extension ScreenDetecting {
    func targetUnderPointer() -> ScreenTarget? {
        guard let screen = screenUnderPointer() else { return nil }
        return ScreenTarget(screen: screen, pointerLocation: .zero)
    }

    func screen(matching binding: DisplayBinding) -> ScreenDescriptor? {
        guard let screen = screenUnderPointer(), screen.displayID == binding.fallbackDisplayID else {
            return nil
        }
        return screen
    }

    func bindingForScreenUnderPointer() -> DisplayBinding? {
        screenUnderPointer().map { DisplayBinding(uuid: nil, fallbackDisplayID: $0.displayID) }
    }
}

@MainActor
final class MacScreenDetector: ScreenDetecting {
    private let snapshotProvider: any ScreenSnapshotProviding
    private let converter = ScreenCoordinateConverter()

    /// Injectable initializer used by headless tests and platform adapters.
    init(snapshotProvider: any ScreenSnapshotProviding) {
        self.snapshotProvider = snapshotProvider
    }

    /// Convenience initializer using the current AppKit display state.
    convenience init() {
        self.init(snapshotProvider: LiveScreenSnapshotProvider())
    }

    func screenUnderPointer() -> ScreenDescriptor? {
        targetUnderPointer()?.screen
    }

    func targetUnderPointer() -> ScreenTarget? {
        let snapshot = snapshotProvider.snapshot()
        guard let primaryFrame = snapshot.primaryFrame, usable(primaryFrame),
              let display = displayUnderPointer(in: snapshot),
              let screen = descriptor(for: display, primaryFrame: primaryFrame) else { return nil }

        return ScreenTarget(
            screen: screen,
            pointerLocation: converter.accessibilityPoint(
                fromAppKit: snapshot.pointerLocation,
                primaryScreenFrame: primaryFrame
            )
        )
    }

    func screen(matching binding: DisplayBinding) -> ScreenDescriptor? {
        let snapshot = snapshotProvider.snapshot()
        guard let primaryFrame = snapshot.primaryFrame, usable(primaryFrame) else { return nil }
        guard let display = snapshot.displays.first(where: { display in
            guard let id = display.displayID, id > 0, usable(display.frame), usable(display.visibleFrame) else {
                return false
            }
            return matches(binding, display: display, id: id)
        }) else { return nil }
        return descriptor(for: display, primaryFrame: primaryFrame)
    }

    func bindingForScreenUnderPointer() -> DisplayBinding? {
        let snapshot = snapshotProvider.snapshot()
        guard let primaryFrame = snapshot.primaryFrame, usable(primaryFrame),
              let display = displayUnderPointer(in: snapshot),
              let id = display.displayID, id > 0,
              descriptor(for: display, primaryFrame: primaryFrame) != nil else {
            return nil
        }
        return DisplayBinding(uuid: display.uuid, fallbackDisplayID: id)
    }

    private func displayUnderPointer(in snapshot: ScreenSnapshot) -> ScreenSnapshot.Display? {
        // The half-open interval makes a shared edge belong to the display that
        // starts at that edge, and keeps the result deterministic for ordered NSScreen.screens.
        snapshot.displays.first {
            usable($0.frame) && containsHalfOpen($0.frame, point: snapshot.pointerLocation)
        }
    }

    private func descriptor(for display: ScreenSnapshot.Display, primaryFrame: CGRect) -> ScreenDescriptor? {
        guard let displayID = display.displayID, displayID > 0,
              usable(display.frame), usable(display.visibleFrame) else { return nil }
        return ScreenDescriptor(
            displayID: displayID,
            frame: converter.accessibilityRect(fromAppKit: display.frame, primaryScreenFrame: primaryFrame),
            visibleFrame: converter.accessibilityRect(fromAppKit: display.visibleFrame, primaryScreenFrame: primaryFrame)
        )
    }

    private func matches(_ binding: DisplayBinding, display: ScreenSnapshot.Display, id: UInt32) -> Bool {
        // A pair of UUIDs is authoritative. If either side lacks a UUID (as is
        // allowed for deterministic test providers), fall back to the session ID.
        if let expected = binding.uuid, let actual = display.uuid {
            return expected == actual
        }
        return id == binding.fallbackDisplayID
    }

    private func usable(_ rect: CGRect) -> Bool {
        rect.isFinite && rect.width > 0 && rect.height > 0
    }

    private func containsHalfOpen(_ rect: CGRect, point: CGPoint) -> Bool {
        point.x >= rect.minX && point.x < rect.maxX &&
            point.y >= rect.minY && point.y < rect.maxY
    }
}

private extension CGRect {
    var isFinite: Bool {
        minX.isFinite && minY.isFinite && width.isFinite && height.isFinite
    }
}
