import ApplicationServices
import CoreGraphics
import Foundation

@MainActor
protocol WindowFrameControlling: AnyObject {
    func setFrame(_ frame: CGRect, for window: WindowIdentifier) throws
}

enum WindowFrameControlError: Error, Equatable {
    case missingHandle
    case invalidPositionValue
    case invalidSizeValue
    case accessibilityFailure(code: Int32)
}

@MainActor
protocol LayoutApplying: AnyObject {
    var canRestore: Bool { get }
    func arrange(windows: [WindowDescriptor], in visibleFrame: CGRect, gap: CGFloat) -> ArrangementOutcome
    func arrange(windows: [WindowDescriptor], in visibleFrame: CGRect, gap: CGFloat, mode: LayoutMode) -> ArrangementOutcome
    func arrange(
        windows: [WindowDescriptor],
        in visibleFrame: CGRect,
        gap: CGFloat,
        mode: LayoutMode,
        customization: LayoutCustomization
    ) -> ArrangementOutcome
    func restore() -> RestoreOutcome
}

extension LayoutApplying {
    func arrange(windows: [WindowDescriptor], in visibleFrame: CGRect, gap: CGFloat, mode _: LayoutMode) -> ArrangementOutcome {
        arrange(windows: windows, in: visibleFrame, gap: gap)
    }

    func arrange(
        windows: [WindowDescriptor],
        in visibleFrame: CGRect,
        gap: CGFloat,
        mode: LayoutMode,
        customization _: LayoutCustomization
    ) -> ArrangementOutcome {
        arrange(windows: windows, in: visibleFrame, gap: gap, mode: mode)
    }
}

@MainActor
final class AccessibilityWindowFrameController: WindowFrameControlling {
    private let registry: AXWindowHandleRegistry

    init(registry: AXWindowHandleRegistry) {
        self.registry = registry
    }

    func setFrame(_ frame: CGRect, for window: WindowIdentifier) throws {
        guard let element = registry.element(for: window) else {
            throw WindowFrameControlError.missingHandle
        }
        var position = CGPoint(x: frame.minX, y: frame.minY)
        var size = CGSize(width: frame.width, height: frame.height)
        guard let positionValue = AXValueCreate(.cgPoint, &position) else {
            throw WindowFrameControlError.invalidPositionValue
        }
        guard let sizeValue = AXValueCreate(.cgSize, &size) else {
            throw WindowFrameControlError.invalidSizeValue
        }

        do {
            try set(positionValue, attribute: kAXPositionAttribute, on: element, for: window)
            try set(sizeValue, attribute: kAXSizeAttribute, on: element, for: window)
            // Resizing can cause some applications to move their window. Re-apply
            // the requested origin so the resulting frame is deterministic.
            try set(positionValue, attribute: kAXPositionAttribute, on: element, for: window)
        } catch {
            throw error
        }
    }

    private func set(
        _ value: AXValue,
        attribute: String,
        on element: AXUIElement,
        for identifier: WindowIdentifier
    ) throws {
        let result = AXUIElementSetAttributeValue(element, attribute as CFString, value)
        guard result == .success else {
            if result == .invalidUIElement || result == .cannotComplete {
                registry.remove(identifier)
            }
            throw WindowFrameControlError.accessibilityFailure(code: result.rawValue)
        }
    }
}

@MainActor
final class LayoutService: LayoutApplying {
    private let calculator: any LayoutCalculating
    private let frameController: any WindowFrameControlling
    private let history: LayoutHistory

    init(
        calculator: any LayoutCalculating,
        frameController: any WindowFrameControlling,
        history: LayoutHistory? = nil
    ) {
        self.calculator = calculator
        self.frameController = frameController
        self.history = history ?? LayoutHistory()
    }

    var canRestore: Bool { history.canUndo }

    func arrange(windows: [WindowDescriptor], in visibleFrame: CGRect, gap: CGFloat) -> ArrangementOutcome {
        arrange(windows: windows, in: visibleFrame, gap: gap, mode: .row)
    }

    func arrange(windows: [WindowDescriptor], in visibleFrame: CGRect, gap: CGFloat, mode: LayoutMode) -> ArrangementOutcome {
        arrange(
            windows: windows,
            in: visibleFrame,
            gap: gap,
            mode: mode,
            customization: .default
        )
    }

    func arrange(
        windows: [WindowDescriptor],
        in visibleFrame: CGRect,
        gap: CGFloat,
        mode: LayoutMode,
        customization: LayoutCustomization
    ) -> ArrangementOutcome {
        guard windows.count >= 2 else {
            return .insufficientWindows(count: windows.count)
        }

        let frames: [CGRect]
        do {
            var effectiveCustomization = customization.normalized
            let effectiveMode: LayoutMode
            if mode == .smart {
                let decision = SmartLayoutPolicy.decision(forWindowCount: windows.count)
                effectiveMode = decision.mode
                if decision.rows != .automatic, effectiveCustomization.wrappedRows == .automatic {
                    effectiveCustomization.wrappedRows = decision.rows
                }
            } else {
                effectiveMode = mode
            }
            let selectedCalculator: any LayoutCalculating
            switch effectiveMode {
            case .smart: selectedCalculator = calculator
            case .row: selectedCalculator = calculator
            case .wrappedRows: selectedCalculator = WrappedRowsLayoutCalculator(customization: effectiveCustomization)
            case .balancedGrid: selectedCalculator = BalancedGridLayoutCalculator(customization: effectiveCustomization)
            case .focus: selectedCalculator = FocusLayoutCalculator(customization: effectiveCustomization)
            }
            frames = try selectedCalculator.frames(in: visibleFrame, windowCount: windows.count, gap: gap)
        } catch {
            return .invalidGeometry
        }
        guard frames.count == windows.count else {
            return .invalidGeometry
        }

        var moved = 0
        var failed = 0
        var successfulOriginalFrames: [(WindowIdentifier, CGRect)] = []
        successfulOriginalFrames.reserveCapacity(windows.count)
        for (window, frame) in zip(windows, frames) {
            do {
                try frameController.setFrame(frame, for: window.id)
                moved += 1
                successfulOriginalFrames.append((window.id, window.frame))
            } catch {
                failed += 1
            }
        }

        if moved > 0 {
            history.append(successfulOriginalFrames.map { LayoutHistoryEntry($0.0, $0.1) })
        }
        return .completed(moved: moved, failed: failed)
    }

    func restore() -> RestoreOutcome {
        guard let entries = history.takeLatest() else { return .nothingToRestore }

        var restored = 0
        var failed = 0
        for entry in entries {
            do {
                try frameController.setFrame(entry.frame, for: entry.window)
                restored += 1
            } catch {
                failed += 1
            }
        }
        return .completed(restored: restored, failed: failed)
    }
}
