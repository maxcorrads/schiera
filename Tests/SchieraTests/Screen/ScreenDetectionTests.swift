import CoreGraphics
import XCTest
@testable import Schiera

@MainActor
final class ScreenDetectionTests: XCTestCase {
    private final class Provider: ScreenSnapshotProviding {
        var snapshots: [ScreenSnapshot]
        var calls = 0

        init(_ snapshots: [ScreenSnapshot]) { self.snapshots = snapshots }

        func snapshot() -> ScreenSnapshot {
            calls += 1
            return snapshots[min(calls - 1, snapshots.count - 1)]
        }
    }

    func testConvertsPrimaryAndSecondaryFrames() {
        let primary = CGRect(x: 100, y: 50, width: 1000, height: 800)
        let secondary = ScreenSnapshot.Display(
            displayID: 2,
            frame: CGRect(x: -500, y: 250, width: 500, height: 400),
            visibleFrame: CGRect(x: -500, y: 270, width: 500, height: 380)
        )
        let provider = Provider([ScreenSnapshot(
            pointerLocation: CGPoint(x: -10, y: 300),
            displays: [ScreenSnapshot.Display(displayID: 1, frame: primary, visibleFrame: primary), secondary],
            primaryFrame: primary
        )])

        let result = MacScreenDetector(snapshotProvider: provider).screenUnderPointer()

        XCTAssertEqual(result?.displayID, 2)
        XCTAssertEqual(result?.frame, CGRect(x: -500, y: 200, width: 500, height: 400))
        XCTAssertEqual(result?.visibleFrame, CGRect(x: -500, y: 200, width: 500, height: 380))
    }

    func testSharedEdgeUsesFirstDisplayAndSnapshotIsFresh() {
        let first = ScreenSnapshot.Display(displayID: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100), visibleFrame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let second = ScreenSnapshot.Display(displayID: 2, frame: CGRect(x: 100, y: 0, width: 100, height: 100), visibleFrame: CGRect(x: 100, y: 0, width: 100, height: 100))
        let snapshots = [
            ScreenSnapshot(pointerLocation: CGPoint(x: 100, y: 20), displays: [first, second], primaryFrame: first.frame),
            ScreenSnapshot(pointerLocation: CGPoint(x: 150, y: 20), displays: [first, second], primaryFrame: first.frame)
        ]
        let provider = Provider(snapshots)
        let detector = MacScreenDetector(snapshotProvider: provider)

        XCTAssertEqual(detector.screenUnderPointer()?.displayID, 2)
        XCTAssertEqual(detector.screenUnderPointer()?.displayID, 2)
        XCTAssertEqual(provider.calls, 2)
    }

    func testNoContainingScreenOrDisplayIDReturnsNil() {
        let display = ScreenSnapshot.Display(displayID: nil, frame: CGRect(x: 0, y: 0, width: 100, height: 100), visibleFrame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let provider = Provider([ScreenSnapshot(pointerLocation: CGPoint(x: 200, y: 20), displays: [display], primaryFrame: display.frame)])
        XCTAssertNil(MacScreenDetector(snapshotProvider: provider).screenUnderPointer())
    }

    func testTargetConvertsPointerToAccessibilityCoordinatesAndExposesBinding() {
        let primary = CGRect(x: 100, y: 50, width: 1_000, height: 800)
        let display = ScreenSnapshot.Display(
            displayID: 2,
            uuid: "display-two",
            frame: CGRect(x: -500, y: 250, width: 500, height: 400),
            visibleFrame: CGRect(x: -500, y: 270, width: 500, height: 380)
        )
        let provider = Provider([ScreenSnapshot(
            pointerLocation: CGPoint(x: -10, y: 300),
            displays: [display],
            primaryFrame: primary
        )])
        let detector = MacScreenDetector(snapshotProvider: provider)

        let target = detector.targetUnderPointer()

        XCTAssertEqual(target?.screen.displayID, 2)
        XCTAssertEqual(target?.pointerLocation, CGPoint(x: -10, y: 550))
        XCTAssertEqual(detector.bindingForScreenUnderPointer(), DisplayBinding(uuid: "display-two", fallbackDisplayID: 2))
    }

    func testScreenBindingPrefersUUIDAndFallsBackToDisplayIDWhenUUIDUnavailable() {
        let primary = CGRect(x: 0, y: 0, width: 800, height: 600)
        let display = ScreenSnapshot.Display(
            displayID: 7,
            uuid: "stable-display",
            frame: primary,
            visibleFrame: primary
        )
        let provider = Provider([ScreenSnapshot(pointerLocation: .zero, displays: [display], primaryFrame: primary)])
        let detector = MacScreenDetector(snapshotProvider: provider)

        XCTAssertEqual(detector.screen(matching: DisplayBinding(uuid: "stable-display", fallbackDisplayID: 99))?.displayID, 7)
        XCTAssertNil(detector.screen(matching: DisplayBinding(uuid: "different-display", fallbackDisplayID: 7)))

        let fallbackDisplay = ScreenSnapshot.Display(displayID: 7, frame: primary, visibleFrame: primary)
        let fallbackProvider = Provider([ScreenSnapshot(pointerLocation: .zero, displays: [fallbackDisplay], primaryFrame: primary)])
        let fallbackDetector = MacScreenDetector(snapshotProvider: fallbackProvider)
        XCTAssertEqual(fallbackDetector.screen(matching: DisplayBinding(uuid: "stable-display", fallbackDisplayID: 7))?.displayID, 7)
    }

    func testDisconnectedDisplayNoLongerMatchesFreshSnapshot() {
        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let connected = ScreenSnapshot.Display(displayID: 4, uuid: "display-four", frame: frame, visibleFrame: frame)
        let provider = Provider([
            ScreenSnapshot(pointerLocation: .zero, displays: [connected], primaryFrame: frame),
            ScreenSnapshot(pointerLocation: .zero, displays: [], primaryFrame: frame)
        ])
        let detector = MacScreenDetector(snapshotProvider: provider)
        let binding = DisplayBinding(uuid: "display-four", fallbackDisplayID: 4)

        XCTAssertEqual(detector.screen(matching: binding)?.displayID, 4)
        XCTAssertNil(detector.screen(matching: binding))
        XCTAssertEqual(provider.calls, 2)
    }

    func testVisibleFrameIsReadFromEverySnapshot() {
        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let first = ScreenSnapshot.Display(displayID: 1, frame: frame, visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 580))
        let second = ScreenSnapshot.Display(displayID: 1, frame: frame, visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 560))
        let provider = Provider([
            ScreenSnapshot(pointerLocation: CGPoint(x: 10, y: 10), displays: [first], primaryFrame: frame),
            ScreenSnapshot(pointerLocation: CGPoint(x: 10, y: 10), displays: [second], primaryFrame: frame)
        ])
        let detector = MacScreenDetector(snapshotProvider: provider)

        XCTAssertEqual(detector.screenUnderPointer()?.visibleFrame, CGRect(x: 0, y: 20, width: 800, height: 580))
        XCTAssertEqual(detector.screenUnderPointer()?.visibleFrame, CGRect(x: 0, y: 40, width: 800, height: 560))
        XCTAssertEqual(provider.calls, 2)
    }

    func testMissingPrimaryAndInvalidGeometryReturnNil() {
        let display = ScreenSnapshot.Display(displayID: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100), visibleFrame: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertNil(MacScreenDetector(snapshotProvider: Provider([
            ScreenSnapshot(pointerLocation: .zero, displays: [display], primaryFrame: nil)
        ])).targetUnderPointer())

        let invalid = ScreenSnapshot.Display(displayID: 1, frame: CGRect(x: 0, y: 0, width: 0, height: 100), visibleFrame: display.visibleFrame)
        XCTAssertNil(MacScreenDetector(snapshotProvider: Provider([
            ScreenSnapshot(pointerLocation: .zero, displays: [invalid], primaryFrame: display.frame)
        ])).screenUnderPointer())
    }
}
