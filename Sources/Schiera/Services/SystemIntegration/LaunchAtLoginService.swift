import Foundation
import ServiceManagement

enum LaunchAtLoginStatus: String, Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

@MainActor
protocol LaunchAtLoginBackend: AnyObject {
    var status: LaunchAtLoginStatus { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

@MainActor
protocol LaunchAtLoginManaging: AnyObject {
    var status: LaunchAtLoginStatus { get }
    @discardableResult
    func refresh() -> LaunchAtLoginStatus
    func setEnabled(_ enabled: Bool) throws
    func openSystemSettings()
}

@MainActor
final class LaunchAtLoginService: LaunchAtLoginManaging {
    private let backend: any LaunchAtLoginBackend
    private(set) var status: LaunchAtLoginStatus

    init() {
        let backend = SMAppLaunchAtLoginBackend()
        self.backend = backend
        status = backend.status
    }

    init(backend: any LaunchAtLoginBackend) {
        self.backend = backend
        status = backend.status
    }

    @discardableResult
    func refresh() -> LaunchAtLoginStatus {
        status = backend.status
        return status
    }

    func setEnabled(_ enabled: Bool) throws {
        let current = refresh()

        if enabled {
            // Both states mean that Service Management already knows about the
            // item. Avoid an unnecessary kSMErrorAlreadyRegistered failure.
            guard current != .enabled, current != .requiresApproval else { return }
            try backend.register()
        } else {
            // A disabled or missing service is already in the requested state.
            guard current == .enabled || current == .requiresApproval else { return }
            try backend.unregister()
        }

        _ = refresh()
    }

    func openSystemSettings() {
        backend.openSystemSettings()
    }
}

@MainActor
private final class SMAppLaunchAtLoginBackend: LaunchAtLoginBackend {
    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
    }

    var status: LaunchAtLoginStatus {
        switch service.status {
        case .notRegistered:
            return .notRegistered
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        @unknown default:
            return .notFound
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

// Descriptive aliases keep the integration boundary easy to discover without
// exposing the Service Management implementation to callers.
typealias SMAppLaunchAtLoginService = LaunchAtLoginService
typealias MacLaunchAtLoginService = LaunchAtLoginService
