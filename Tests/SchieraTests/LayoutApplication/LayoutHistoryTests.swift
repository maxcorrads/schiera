import CoreGraphics
import Foundation
import XCTest
@testable import Schiera

@MainActor
final class LayoutHistoryTests: XCTestCase {
    func testDefaultCapacityAndEmptyState() {
        let history = LayoutHistory()

        XCTAssertEqual(history.capacity, 8)
        XCTAssertEqual(history.count, 0)
        XCTAssertFalse(history.canUndo)
        XCTAssertNil(history.takeLatest())
    }

    func testCapacityIsClampedToSupportedBounds() {
        XCTAssertEqual(LayoutHistory(capacity: Int.min).capacity, 1)
        XCTAssertEqual(LayoutHistory(capacity: 0).capacity, 1)
        XCTAssertEqual(LayoutHistory(capacity: 1).capacity, 1)
        XCTAssertEqual(LayoutHistory(capacity: 32).capacity, 32)
        XCTAssertEqual(LayoutHistory(capacity: 33).capacity, 32)
        XCTAssertEqual(LayoutHistory(capacity: Int.max).capacity, 32)
    }

    func testEmptyLevelsAreIgnored() {
        let history = LayoutHistory(capacity: 2)

        history.append([])

        XCTAssertEqual(history.count, 0)
        XCTAssertFalse(history.canUndo)
        XCTAssertNil(history.takeLatest())
    }

    func testAppendsNewestFirstAndTakeLatestConsumesLevels() {
        let history = LayoutHistory(capacity: 3)
        let oldest = [entry(processIdentifier: 1, x: 10)]
        let newest = [entry(processIdentifier: 2, x: 20), entry(processIdentifier: 3, x: 30)]

        history.append(oldest)
        history.append(newest)

        XCTAssertEqual(history.count, 2)
        XCTAssertTrue(history.canUndo)
        XCTAssertEqual(history.takeLatest(), newest)
        XCTAssertEqual(history.count, 1)
        XCTAssertTrue(history.canUndo)
        XCTAssertEqual(history.takeLatest(), oldest)
        XCTAssertEqual(history.count, 0)
        XCTAssertFalse(history.canUndo)
        XCTAssertNil(history.takeLatest())
    }

    func testAppendingBeyondCapacityEvictsOldestLevel() {
        let history = LayoutHistory(capacity: 2)
        let first = [entry(processIdentifier: 1, x: 10)]
        let second = [entry(processIdentifier: 2, x: 20)]
        let third = [entry(processIdentifier: 3, x: 30)]

        history.append(first)
        history.append(second)
        history.append(third)

        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history.takeLatest(), third)
        XCTAssertEqual(history.takeLatest(), second)
        XCTAssertNil(history.takeLatest())
    }

    func testAppendingCopiesEntriesAndDoesNotAliasCallerStorage() {
        let history = LayoutHistory(capacity: 2)
        var entries = [entry(processIdentifier: 1, x: 10)]
        history.append(entries)
        entries.append(entry(processIdentifier: 2, x: 20))

        XCTAssertEqual(history.takeLatest(), [entry(processIdentifier: 1, x: 10)])
    }

    func testRemoveAllClearsEveryLevelAndCanBeUsedRepeatedly() {
        let history = LayoutHistory(capacity: 3)
        history.append([entry(processIdentifier: 1, x: 10)])
        history.append([entry(processIdentifier: 2, x: 20)])

        history.removeAll()
        history.removeAll()

        XCTAssertEqual(history.count, 0)
        XCTAssertFalse(history.canUndo)
        XCTAssertNil(history.takeLatest())
    }

    func testHistoryEntrySupportsLabeledAndUnlabeledInitializers() {
        let identifier = WindowIdentifier(token: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, processIdentifier: 7)
        let frame = CGRect(x: -10, y: 20, width: 300, height: 200)

        XCTAssertEqual(LayoutHistoryEntry(identifier, frame), LayoutHistoryEntry(window: identifier, frame: frame))
        XCTAssertEqual(LayoutHistoryEntry(identifier, frame).window, identifier)
        XCTAssertEqual(LayoutHistoryEntry(identifier, frame).frame, frame)
    }

    private func entry(processIdentifier: Int32, x: CGFloat) -> LayoutHistoryEntry {
        let identifier = WindowIdentifier(
            token: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", processIdentifier))!,
            processIdentifier: processIdentifier
        )
        return LayoutHistoryEntry(identifier, CGRect(x: x, y: 0, width: 100, height: 80))
    }
}
