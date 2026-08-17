import CoreGraphics
import XCTest
@testable import Schiera

final class TemporaryWindowSelectionTests: XCTestCase {
    func testDiscoveryStartsWithAllWindowsInDiscoveryOrder() {
        let windows = makeWindows()
        let selection = TemporaryWindowSelection(windows: windows)

        XCTAssertEqual(selection.arrangeableWindows, windows)
        XCTAssertEqual(selection.displayLabels, [
            "Terminal window 1", "Terminal window 2", "iTerm2 window 1", "Terminal window 3"
        ])
    }

    func testExclusionIsTemporaryAndOmitsOnlySelectedWindow() {
        let windows = makeWindows()
        var selection = TemporaryWindowSelection(windows: windows)

        XCTAssertTrue(selection.toggleExcluded(windows[1].id))
        XCTAssertEqual(selection.arrangeableWindows, [windows[0], windows[2], windows[3]])
        XCTAssertFalse(selection.toggleExcluded(windows[1].id))
        XCTAssertEqual(selection.arrangeableWindows, windows)
    }

    func testPriorityUsesEventOrderThenPreservesDiscoveryOrder() {
        let windows = makeWindows()
        var selection = TemporaryWindowSelection(windows: windows)

        XCTAssertTrue(selection.togglePriority(windows[3].id))
        XCTAssertTrue(selection.togglePriority(windows[1].id))
        XCTAssertEqual(selection.arrangeableWindows, [windows[3], windows[1], windows[0], windows[2]])

        XCTAssertFalse(selection.togglePriority(windows[3].id))
        XCTAssertEqual(selection.arrangeableWindows, [windows[1], windows[0], windows[2], windows[3]])
    }

    func testExclusionWinsOverPriorityWithoutLosingPriorityState() {
        let windows = makeWindows()
        var selection = TemporaryWindowSelection(windows: windows)

        XCTAssertTrue(selection.togglePriority(windows[0].id))
        XCTAssertTrue(selection.toggleExcluded(windows[0].id))
        XCTAssertEqual(selection.arrangeableWindows, Array(windows.dropFirst()))
        XCTAssertFalse(selection.toggleExcluded(windows[0].id))
        XCTAssertEqual(selection.arrangeableWindows, windows)
        XCTAssertEqual(selection.priorityOrder, [windows[0].id])
    }

    func testRediscoveryClearsExclusionsAndPrioritiesEvenWhenTokenChanges() {
        let old = makeWindows()
        var selection = TemporaryWindowSelection(windows: old)
        XCTAssertTrue(selection.toggleExcluded(old[0].id))
        XCTAssertTrue(selection.togglePriority(old[2].id))

        let rediscovered = makeWindows(tokenSeed: 100)
        selection.replaceDiscovery(with: rediscovered)

        XCTAssertEqual(selection.arrangeableWindows, rediscovered)
        XCTAssertTrue(selection.excluded.isEmpty)
        XCTAssertTrue(selection.priorityOrder.isEmpty)
    }

    func testClearRemovesDiscoveryAndTemporaryChoices() {
        let windows = makeWindows()
        var selection = TemporaryWindowSelection(windows: windows)
        XCTAssertTrue(selection.toggleExcluded(windows[0].id))
        XCTAssertTrue(selection.togglePriority(windows[1].id))

        selection.clear()

        XCTAssertTrue(selection.discoveredWindows.isEmpty)
        XCTAssertTrue(selection.arrangeableWindows.isEmpty)
        XCTAssertTrue(selection.excluded.isEmpty)
        XCTAssertTrue(selection.priorityOrder.isEmpty)
    }

    func testStaleIdentifiersCannotChangeCurrentSelection() {
        let old = makeWindows()
        var selection = TemporaryWindowSelection(windows: old)
        selection.replaceDiscovery(with: makeWindows(tokenSeed: 200))

        XCTAssertFalse(selection.toggleExcluded(old[0].id))
        XCTAssertFalse(selection.togglePriority(old[1].id))
        XCTAssertEqual(selection.arrangeableWindows, makeWindows(tokenSeed: 200))
    }

    func testLabelsIgnoreTitlesPIDsAndUUIDs() {
        let id = WindowIdentifier(token: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!, processIdentifier: 99123)
        let window = WindowDescriptor(
            id: id,
            bundleIdentifier: "com.apple.Terminal",
            title: "secret command and path",
            frame: CGRect(x: 0, y: 0, width: 100, height: 100)
        )
        let label = TemporaryWindowSelection(windows: [window]).displayLabel(for: window)

        XCTAssertEqual(label, "Terminal window 1")
        XCTAssertFalse(label.contains("secret"))
        XCTAssertFalse(label.contains("99123"))
        XCTAssertFalse(label.contains(id.token.uuidString))
    }

    func testUnknownBundleUsesSafeGenericLabelAndOrdinal() {
        let windows = [
            makeWindow(index: 0, bundle: "unknown.bundle", tokenSeed: 1),
            makeWindow(index: 1, bundle: "unknown.bundle", tokenSeed: 2)
        ]
        let selection = TemporaryWindowSelection(windows: windows)

        XCTAssertEqual(selection.displayLabels, ["Terminal window 1", "Terminal window 2"])
    }

    private func makeWindows(tokenSeed: Int = 0) -> [WindowDescriptor] {
        [
            makeWindow(index: 0, bundle: "com.apple.Terminal", tokenSeed: tokenSeed + 1),
            makeWindow(index: 1, bundle: "com.apple.Terminal", tokenSeed: tokenSeed + 2),
            makeWindow(index: 2, bundle: "com.googlecode.iterm2", tokenSeed: tokenSeed + 3),
            makeWindow(index: 3, bundle: "com.apple.Terminal", tokenSeed: tokenSeed + 4)
        ]
    }

    private func makeWindow(index: Int, bundle: String, tokenSeed: Int) -> WindowDescriptor {
        let repeated = String(format: "%012X", tokenSeed)
        let uuidString = "00000000-0000-0000-0000-\(repeated)"
        return WindowDescriptor(
            id: WindowIdentifier(token: UUID(uuidString: uuidString)!, processIdentifier: Int32(index + 1)),
            bundleIdentifier: bundle,
            title: "private title \(index)",
            frame: CGRect(x: index * 100, y: 0, width: 90, height: 80)
        )
    }
}
