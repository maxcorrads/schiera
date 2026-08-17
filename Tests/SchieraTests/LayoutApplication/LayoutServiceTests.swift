import CoreGraphics
import XCTest
@testable import Schiera

@MainActor
final class LayoutServiceTests: XCTestCase {
    func testZeroAndOneWindowDoNotCalculateOrMutateAndPreserveSnapshot() {
        let (service, calculator, controller) = makeService()
        let windows = [window(0), window(1)]
        calculator.result = [.zero, .zero]
        XCTAssertEqual(service.arrange(windows: windows, in: .zero, gap: 8), .completed(moved: 2, failed: 0))
        let callsBefore = controller.frames.count
        XCTAssertTrue(service.canRestore)
        XCTAssertEqual(service.arrange(windows: [], in: .zero, gap: 4), .insufficientWindows(count: 0))
        XCTAssertEqual(service.arrange(windows: [windows[0]], in: .zero, gap: 4), .insufficientWindows(count: 1))
        XCTAssertEqual(calculator.calls, 1)
        XCTAssertEqual(controller.frames.count, callsBefore)
        XCTAssertTrue(service.canRestore)
    }

    func testArrangePairsEveryWindowInOrderAndPassesGap() {
        let (service, calculator, controller) = makeService()
        let windows = (0..<4).map(window)
        calculator.result = windows.map { CGRect(x: CGFloat($0.id.processIdentifier), y: 0, width: 10, height: 10) }
        XCTAssertEqual(service.arrange(windows: windows, in: CGRect(x: 2, y: 3, width: 100, height: 20), gap: 13), .completed(moved: 4, failed: 0))
        XCTAssertEqual(calculator.calls, 1)
        XCTAssertEqual(calculator.lastCount, 4)
        XCTAssertEqual(calculator.lastGap, 13)
        XCTAssertEqual(controller.frames.map(\.frame), calculator.result)
        XCTAssertEqual(controller.frames.map(\.id), windows.map(\.id))
    }

    func testAlternativeModesSelectTheirCalculatorsAndPreserveWindowOrder() {
        let windows = (0..<4).map(window)

        let gridController = RecordingController()
        let gridService = LayoutService(calculator: HorizontalLayoutCalculator(), frameController: gridController)
        XCTAssertEqual(
            gridService.arrange(
                windows: windows,
                in: CGRect(x: 0, y: 0, width: 100, height: 80),
                gap: 8,
                mode: .balancedGrid
            ),
            .completed(moved: 4, failed: 0)
        )
        XCTAssertEqual(gridController.frames.map(\.id), windows.map(\.id))
        XCTAssertEqual(gridController.frames.map(\.frame), [
            CGRect(x: 12, y: 12, width: 34, height: 24),
            CGRect(x: 54, y: 12, width: 34, height: 24),
            CGRect(x: 12, y: 44, width: 34, height: 24),
            CGRect(x: 54, y: 44, width: 34, height: 24)
        ])

        let focusController = RecordingController()
        let focusService = LayoutService(calculator: HorizontalLayoutCalculator(), frameController: focusController)
        XCTAssertEqual(
            focusService.arrange(
                windows: windows,
                in: CGRect(x: 0, y: 0, width: 1_000, height: 600),
                gap: 10,
                mode: .focus
            ),
            .completed(moved: 4, failed: 0)
        )
        XCTAssertEqual(focusController.frames.map(\.id), windows.map(\.id))
        XCTAssertEqual(focusController.frames.first?.frame.width, 579)
        XCTAssertTrue(focusService.canRestore)
    }

    func testCalculationFailureDoesNotMutateOrReplaceSnapshot() {
        let (service, calculator, controller) = makeService()
        let windows = [window(1), window(2)]
        calculator.error = LayoutCalculationError.insufficientSpace
        XCTAssertEqual(service.arrange(windows: windows, in: .zero, gap: 8), .invalidGeometry)
        XCTAssertEqual(calculator.calls, 1)
        XCTAssertTrue(controller.frames.isEmpty)
        XCTAssertFalse(service.canRestore)
    }

    func testCompletePartialAndTotalFailureSnapshotRules() {
        let (service, calculator, controller) = makeService()
        let windows = [window(1), window(2), window(3)]
        calculator.result = Array(repeating: CGRect(x: 100, y: 100, width: 20, height: 20), count: 3)
        controller.failIDs = [windows[1].id]
        XCTAssertEqual(service.arrange(windows: windows, in: .zero, gap: 8), .completed(moved: 2, failed: 1))
        XCTAssertTrue(service.canRestore)
        XCTAssertEqual(service.restore(), .completed(restored: 2, failed: 0))
        XCTAssertEqual(controller.frames.suffix(2).map(\.frame), windows.filter { $0.id != windows[1].id }.map(\.frame))

        controller.failIDs = Set(windows.map(\.id))
        XCTAssertEqual(service.arrange(windows: windows, in: .zero, gap: 8), .completed(moved: 0, failed: 3))
        XCTAssertFalse(service.canRestore)
        XCTAssertEqual(service.restore(), .nothingToRestore)
    }

    func testLaterSuccessfulArrangeAddsBoundedUndoLevelsNewestFirst() {
        let (service, calculator, controller) = makeService()
        let first = [window(1), window(2)]
        let second = [window(3), window(4)]
        calculator.result = [CGRect(x: 10, y: 10, width: 30, height: 30), CGRect(x: 50, y: 10, width: 30, height: 30)]
        XCTAssertEqual(service.arrange(windows: first, in: .zero, gap: 1), .completed(moved: 2, failed: 0))
        XCTAssertEqual(service.arrange(windows: second, in: .zero, gap: 1), .completed(moved: 2, failed: 0))
        XCTAssertEqual(service.restore(), .completed(restored: 2, failed: 0))
        XCTAssertEqual(controller.frames.suffix(2).map(\.id), second.map(\.id))
        XCTAssertEqual(controller.frames.suffix(2).map(\.frame), second.map(\.frame))
        XCTAssertTrue(service.canRestore)
        XCTAssertEqual(service.restore(), .completed(restored: 2, failed: 0))
        XCTAssertEqual(controller.frames.suffix(2).map(\.id), first.map(\.id))
        XCTAssertEqual(controller.frames.suffix(2).map(\.frame), first.map(\.frame))
        XCTAssertFalse(service.canRestore)
        XCTAssertEqual(service.restore(), .nothingToRestore)
    }

    func testRestoreContinuesAfterDisappearingWindowAndConsumesSnapshot() {
        let (service, calculator, controller) = makeService()
        let windows = [window(1), window(2), window(3)]
        calculator.result = Array(repeating: CGRect(x: 1, y: 1, width: 5, height: 5), count: 3)
        XCTAssertEqual(service.arrange(windows: windows, in: .zero, gap: 0), .completed(moved: 3, failed: 0))
        controller.failIDs = [windows[1].id]
        XCTAssertEqual(service.restore(), .completed(restored: 2, failed: 1))
        XCTAssertFalse(service.canRestore)
        XCTAssertEqual(service.restore(), .nothingToRestore)
    }

    func testMissingAXHandleThrowsTypedError() {
        let registry = AXWindowHandleRegistry()
        let controller = AccessibilityWindowFrameController(registry: registry)
        XCTAssertThrowsError(try controller.setFrame(.zero, for: window(1).id)) { error in
            XCTAssertEqual(error as? WindowFrameControlError, .missingHandle)
        }
    }

    private func makeService() -> (LayoutService, RecordingCalculator, RecordingController) {
        let calculator = RecordingCalculator()
        let controller = RecordingController()
        return (LayoutService(calculator: calculator, frameController: controller), calculator, controller)
    }

    private func window(_ index: Int) -> WindowDescriptor {
        WindowDescriptor(id: WindowIdentifier(token: UUID(), processIdentifier: Int32(index)), bundleIdentifier: "terminal", title: nil, frame: CGRect(x: index, y: index, width: 100, height: 80))
    }
}

private final class RecordingCalculator: LayoutCalculating, @unchecked Sendable {
    var calls = 0
    var lastCount = 0
    var lastGap: CGFloat = 0
    var result: [CGRect] = []
    var error: Error?

    func frames(in _: CGRect, windowCount: Int, gap: CGFloat) throws -> [CGRect] {
        calls += 1; lastCount = windowCount; lastGap = gap
        if let error { throw error }
        return result.isEmpty ? Array(repeating: .zero, count: windowCount) : result
    }
}

@MainActor
private final class RecordingController: WindowFrameControlling {
    struct Call { let id: WindowIdentifier; let frame: CGRect }
    var frames: [Call] = []
    var failIDs: Set<WindowIdentifier> = []

    func setFrame(_ frame: CGRect, for window: WindowIdentifier) throws {
        if failIDs.contains(window) { throw WindowFrameControlError.missingHandle }
        frames.append(Call(id: window, frame: frame))
    }
}
