import XCTest
@testable import Schiera

@MainActor
final class MacAccessibilityPermissionServiceTests: XCTestCase {
    func testUntrustedFreshInstallIsNotDetermined() {
        let trust = Trust(false)
        let marker = Marker(false)
        let service = MacAccessibilityPermissionService(trustChecker: trust.check, markerStore: marker, settingsOpener: Opener())
        XCTAssertEqual(service.state, .notDetermined)
    }

    func testTrustedStateWinsRegardlessOfMarker() {
        let trust = Trust(true)
        let marker = Marker(true)
        let service = MacAccessibilityPermissionService(trustChecker: trust.check, markerStore: marker, settingsOpener: Opener())
        XCTAssertEqual(service.state, .granted)
        trust.value = false
        XCTAssertEqual(service.refresh(), .denied)
    }

    func testRefreshNeverPromptsOrChangesMarker() {
        let trust = Trust(false)
        let marker = Marker(false)
        let service = MacAccessibilityPermissionService(trustChecker: trust.check, markerStore: marker, settingsOpener: Opener())
        _ = service.refresh()
        XCTAssertEqual(trust.prompts, [false, false])
        XCTAssertFalse(marker.wasRequested)
    }

    func testRequestWritesMarkerBeforePromptCheck() {
        let marker = Marker(false)
        let trust = Trust(false) { prompt in
            if prompt { XCTAssertTrue(marker.wasRequested) }
        }
        let service = MacAccessibilityPermissionService(trustChecker: trust.check, markerStore: marker, settingsOpener: Opener())
        XCTAssertEqual(service.request(), .denied)
        XCTAssertTrue(marker.wasRequested)
        XCTAssertEqual(trust.prompts, [false, true])
    }

    func testRequestCanBecomeGranted() {
        let trust = Trust(true)
        let marker = Marker(false)
        let service = MacAccessibilityPermissionService(trustChecker: trust.check, markerStore: marker, settingsOpener: Opener())
        XCTAssertEqual(service.request(), .granted)
    }

    func testSettingsURLAndOpenResult() {
        let opener = Opener(result: true)
        let service = MacAccessibilityPermissionService(trustChecker: { _ in false }, markerStore: Marker(false), settingsOpener: opener)
        XCTAssertTrue(service.openSystemSettings())
        XCTAssertEqual(opener.url?.absoluteString, "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func testSettingsOpenFailurePropagates() {
        let opener = Opener(result: false)
        let service = MacAccessibilityPermissionService(trustChecker: { _ in false }, markerStore: Marker(false), settingsOpener: opener)
        XCTAssertFalse(service.openSystemSettings())
    }

    private final class Marker: AccessibilityPromptMarkerStoring {
        var wasRequested: Bool
        init(_ value: Bool) { wasRequested = value }
    }

    private final class Opener: AccessibilitySettingsOpening {
        var result: Bool
        var url: URL?
        init(result: Bool = true) { self.result = result }
        func open(_ url: URL) -> Bool { self.url = url; return result }
    }

    private final class Trust {
        var value: Bool
        var prompts: [Bool] = []
        private let onCheck: ((Bool) -> Void)?
        init(_ value: Bool, onCheck: ((Bool) -> Void)? = nil) { self.value = value; self.onCheck = onCheck }
        func check(prompt: Bool) -> Bool { prompts.append(prompt); onCheck?(prompt); return value }
    }
}
