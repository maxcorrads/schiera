import XCTest
@testable import Schiera

@MainActor
final class LaunchAtLoginServiceTests: XCTestCase {
    func testInitialStatusAndRefreshUseBackend() {
        let backend = LaunchAtLoginBackendFake(status: .requiresApproval)
        let service = LaunchAtLoginService(backend: backend)

        XCTAssertEqual(service.status, .requiresApproval)
        backend.status = .enabled
        XCTAssertEqual(service.refresh(), .enabled)
    }

    func testEnablingAlreadyRegisteredServiceIsIdempotent() throws {
        let backend = LaunchAtLoginBackendFake(status: .enabled)
        let service = LaunchAtLoginService(backend: backend)

        try service.setEnabled(true)

        XCTAssertEqual(backend.registerCount, 0)
        XCTAssertEqual(service.status, .enabled)
    }

    func testRequiresApprovalIsAlreadyRegisteredForEnablement() throws {
        let backend = LaunchAtLoginBackendFake(status: .requiresApproval)
        let service = LaunchAtLoginService(backend: backend)

        try service.setEnabled(true)

        XCTAssertEqual(backend.registerCount, 0)
    }

    func testDisablingRegisteredServiceCallsBackendAndRefreshes() throws {
        let backend = LaunchAtLoginBackendFake(status: .enabled)
        let service = LaunchAtLoginService(backend: backend)
        backend.statusAfterUnregister = .notRegistered

        try service.setEnabled(false)

        XCTAssertEqual(backend.unregisterCount, 1)
        XCTAssertEqual(service.status, .notRegistered)
    }

    func testDisablingUnregisteredOrMissingServiceIsIdempotent() throws {
        for status in [LaunchAtLoginStatus.notRegistered, .notFound] {
            let backend = LaunchAtLoginBackendFake(status: status)
            let service = LaunchAtLoginService(backend: backend)

            try service.setEnabled(false)

            XCTAssertEqual(backend.unregisterCount, 0)
            XCTAssertEqual(service.status, status)
        }
    }

    func testRegistrationErrorIsPropagatedAndStateIsRetained() {
        let backend = LaunchAtLoginBackendFake(status: .notRegistered)
        backend.registerError = FakeError.registration
        let service = LaunchAtLoginService(backend: backend)

        XCTAssertThrowsError(try service.setEnabled(true)) { error in
            XCTAssertEqual(error as? FakeError, .registration)
        }
        XCTAssertEqual(service.status, .notRegistered)
        XCTAssertEqual(backend.registerCount, 1)
    }

    func testUnregistrationErrorIsPropagatedAndStateIsRetained() {
        let backend = LaunchAtLoginBackendFake(status: .enabled)
        backend.unregisterError = FakeError.unregistration
        let service = LaunchAtLoginService(backend: backend)

        XCTAssertThrowsError(try service.setEnabled(false)) { error in
            XCTAssertEqual(error as? FakeError, .unregistration)
        }
        XCTAssertEqual(service.status, .enabled)
        XCTAssertEqual(backend.unregisterCount, 1)
    }

    func testOpeningSettingsIsDelegated() {
        let backend = LaunchAtLoginBackendFake(status: .notRegistered)
        let service = LaunchAtLoginService(backend: backend)

        service.openSystemSettings()

        XCTAssertEqual(backend.openSettingsCount, 1)
    }
}

@MainActor
final class DiagnosticsCollectorTests: XCTestCase {
    func testSnapshotIsInMemoryAndContainsOnlyAggregateValues() {
        let collector = DiagnosticsCollector()
        let profiles = [
            DiagnosticsProfile(name: "Terminal", detected: true, windowCount: 2),
            DiagnosticsProfile(name: "iTerm2", detected: false, windowCount: -5)
        ]
        let displays = [DiagnosticsDisplay(ordinal: 1, isPointerDisplay: true, windowCount: 2)]

        let snapshot = collector.update(
            permission: .granted,
            launchAtLogin: .enabled,
            shortcutRegistered: true,
            profiles: profiles,
            displays: displays,
            totalWindowCount: 2
        )

        XCTAssertEqual(snapshot.permission, .granted)
        XCTAssertEqual(snapshot.launchAtLogin, .enabled)
        XCTAssertTrue(snapshot.shortcutRegistered)
        XCTAssertEqual(snapshot.profiles, profiles)
        XCTAssertEqual(snapshot.displays, displays)
        XCTAssertEqual(snapshot.totalWindowCount, 2)
        XCTAssertEqual(collector.snapshot, snapshot)
        XCTAssertEqual(snapshot.profiles[1].windowCount, 0)
    }

    func testTotalWindowCountDefaultsToProfileAggregateAndClampsNegative() {
        let collector = DiagnosticsCollector()

        let fromProfiles = collector.update(
            permission: .denied,
            launchAtLogin: .notRegistered,
            shortcutRegistered: false,
            profiles: [
                DiagnosticsProfile(name: "Terminal", detected: true, windowCount: 3),
                DiagnosticsProfile(name: "Ghostty", detected: true, windowCount: 1)
            ],
            displays: [],
            totalWindowCount: nil
        )
        XCTAssertEqual(fromProfiles.totalWindowCount, 4)

        let clamped = collector.update(
            permission: .notDetermined,
            launchAtLogin: .notFound,
            shortcutRegistered: false,
            profiles: [],
            displays: [],
            totalWindowCount: -1
        )
        XCTAssertEqual(clamped.totalWindowCount, 0)
    }
}

@MainActor
private final class LaunchAtLoginBackendFake: LaunchAtLoginBackend {
    var status: LaunchAtLoginStatus
    var statusAfterRegister: LaunchAtLoginStatus?
    var statusAfterUnregister: LaunchAtLoginStatus?
    var registerError: Error?
    var unregisterError: Error?
    var registerCount = 0
    var unregisterCount = 0
    var openSettingsCount = 0

    init(status: LaunchAtLoginStatus) {
        self.status = status
    }

    func register() throws {
        registerCount += 1
        if let registerError { throw registerError }
        if let statusAfterRegister { status = statusAfterRegister }
    }

    func unregister() throws {
        unregisterCount += 1
        if let unregisterError { throw unregisterError }
        if let statusAfterUnregister { status = statusAfterUnregister }
    }

    func openSystemSettings() {
        openSettingsCount += 1
    }
}

private enum FakeError: Error, Equatable {
    case registration
    case unregistration
}
