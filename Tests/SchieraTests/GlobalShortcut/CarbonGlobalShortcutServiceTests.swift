import Carbon
import XCTest
@testable import Schiera

private final class TestToken: NSObject {
    let number: Int
    init(_ number: Int) { self.number = number }
}

private final class FakeCarbonBackend: CarbonGlobalShortcutBackend {
    var installStatus: Int32 = noErr
    var registrationStatuses: [Int32] = []
    var installCount = 0
    var removeHandlerCount = 0
    var registerCalls: [(keyCode: UInt32, modifiers: UInt32, signature: UInt32, identifier: UInt32)] = []
    var unregisterCount = 0
    private var nextToken = 0
    private var eventHandler: (@Sendable (CarbonHotKeyEvent) -> Void)?

    func installEventHandler(_ handler: @escaping @Sendable (CarbonHotKeyEvent) -> Void) -> Int32 {
        installCount += 1
        guard installStatus == noErr else { return installStatus }
        eventHandler = handler
        return noErr
    }

    func removeEventHandler() {
        removeHandlerCount += 1
        eventHandler = nil
    }

    func register(keyCode: UInt32, modifiers: UInt32, signature: UInt32, identifier: UInt32) -> (status: Int32, token: AnyObject?) {
        registerCalls.append((keyCode, modifiers, signature, identifier))
        let status = registrationStatuses.isEmpty ? noErr : registrationStatuses.removeFirst()
        guard status == noErr else { return (status, nil) }
        nextToken += 1
        return (status, TestToken(nextToken))
    }

    func unregister(token: AnyObject) { unregisterCount += 1 }

    func emit(signature: UInt32 = 0x53434852, identifier: UInt32 = 1) {
        eventHandler?(CarbonHotKeyEvent(signature: signature, identifier: identifier))
    }
}

@MainActor
final class CarbonGlobalShortcutServiceTests: XCTestCase {
    func testDefaultShortcutMapsExactly() throws {
        let backend = FakeCarbonBackend()
        let service = CarbonGlobalShortcutService(backend: backend)
        try service.register(.defaultSchiera) {}
        XCTAssertEqual(backend.registerCalls.count, 1)
        XCTAssertEqual(backend.registerCalls[0].keyCode, 1)
        XCTAssertEqual(backend.registerCalls[0].modifiers, UInt32(controlKey | optionKey | cmdKey))
    }

    func testEveryModifierCombinationMapsExactly() throws {
        let backend = FakeCarbonBackend()
        let service = CarbonGlobalShortcutService(backend: backend)
        let cases: [(ShortcutModifiers, UInt32)] = [
            ([.control], UInt32(controlKey)), ([.option], UInt32(optionKey)),
            ([.shift], UInt32(shiftKey)), ([.command], UInt32(cmdKey)),
            ([.control, .option, .shift, .command], UInt32(controlKey | optionKey | shiftKey | cmdKey))
        ]
        for (modifiers, mask) in cases {
            XCTAssertEqual(CarbonGlobalShortcutService.carbonModifiers(for: modifiers), mask)
            try service.register(GlobalShortcut(keyCode: 0, modifiers: modifiers)) {}
        }
        XCTAssertEqual(backend.registerCalls.map(\.modifiers), cases.map { $0.1 })
    }

    func testInvalidShortcutsAreRejectedBeforeBackendRegistration() {
        let backend = FakeCarbonBackend()
        let service = CarbonGlobalShortcutService(backend: backend)
        let invalid = [
            GlobalShortcut(keyCode: 128, modifiers: [.command]),
            GlobalShortcut(keyCode: 0, modifiers: []),
            GlobalShortcut(keyCode: 0, modifiers: ShortcutModifiers(rawValue: 1 << 8)),
            GlobalShortcut(keyCode: 55, modifiers: [.command])
        ]
        for shortcut in invalid {
            XCTAssertThrowsError(try service.register(shortcut) {}) { error in
                XCTAssertEqual(error as? GlobalShortcutError, .invalidShortcut)
            }
        }
        XCTAssertEqual(backend.installCount, 0)
        XCTAssertTrue(backend.registerCalls.isEmpty)
    }

    func testMatchingEventInvokesHandlerOnceAndWrongIdentityDoesNot() async throws {
        let backend = FakeCarbonBackend()
        let service = CarbonGlobalShortcutService(backend: backend)
        var invocations = 0
        try service.register(.defaultSchiera) { invocations += 1 }
        backend.emit(signature: 0x11111111)
        backend.emit(identifier: 9)
        backend.emit()
        await Task.yield()
        XCTAssertEqual(invocations, 1)
    }

    func testReplacementUnregistersOldRegistrationOnce() throws {
        let backend = FakeCarbonBackend()
        let service = CarbonGlobalShortcutService(backend: backend)
        let first = GlobalShortcut(keyCode: 0, modifiers: [.command])
        let second = GlobalShortcut(keyCode: 1, modifiers: [.option])
        try service.register(first) {}
        try service.register(second) {}
        XCTAssertEqual(backend.registerCalls.count, 2)
        XCTAssertEqual(backend.unregisterCount, 1)
        XCTAssertEqual(service.currentShortcut, second)
    }

    func testIdenticalRegistrationReplacesHandlerWithoutDuplicateRegistration() async throws {
        let backend = FakeCarbonBackend()
        let service = CarbonGlobalShortcutService(backend: backend)
        var first = 0
        var second = 0
        try service.register(.defaultSchiera) { first += 1 }
        try service.register(.defaultSchiera) { second += 1 }
        backend.emit()
        await Task.yield()
        XCTAssertEqual(first, 0)
        XCTAssertEqual(second, 1)
        XCTAssertEqual(backend.registerCalls.count, 1)
        XCTAssertEqual(backend.unregisterCount, 0)
    }

    func testFailedReplacementPreservesOldShortcutAndHandler() async throws {
        let backend = FakeCarbonBackend()
        let service = CarbonGlobalShortcutService(backend: backend)
        var calls = 0
        try service.register(.defaultSchiera) { calls += 1 }
        backend.registrationStatuses = [-9876]
        XCTAssertThrowsError(try service.register(GlobalShortcut(keyCode: 0, modifiers: [.command])) {}) { error in
            XCTAssertEqual(error as? GlobalShortcutError, .registrationFailed(status: -9876))
        }
        XCTAssertEqual(service.currentShortcut, .defaultSchiera)
        XCTAssertEqual(backend.unregisterCount, 0)
        backend.emit()
        await Task.yield()
        XCTAssertEqual(calls, 1)
    }

    func testHandlerInstallationAndRegistrationStatusesPropagate() {
        let installBackend = FakeCarbonBackend()
        installBackend.installStatus = -10
        XCTAssertThrowsError(try CarbonGlobalShortcutService(backend: installBackend).register(.defaultSchiera) {}) { error in
            XCTAssertEqual(error as? GlobalShortcutError, .handlerInstallationFailed(status: -10))
        }

        let registrationBackend = FakeCarbonBackend()
        registrationBackend.registrationStatuses = [-11]
        XCTAssertThrowsError(try CarbonGlobalShortcutService(backend: registrationBackend).register(.defaultSchiera) {}) { error in
            XCTAssertEqual(error as? GlobalShortcutError, .registrationFailed(status: -11))
        }
    }

    func testUnregisterAndTeardownAreSafeAndIdempotent() throws {
        let backend = FakeCarbonBackend()
        var service: CarbonGlobalShortcutService? = CarbonGlobalShortcutService(backend: backend)
        try service!.register(.defaultSchiera) {}
        service!.unregister()
        service!.unregister()
        XCTAssertEqual(backend.unregisterCount, 1)
        XCTAssertEqual(backend.removeHandlerCount, 1)
        service = nil
        XCTAssertEqual(backend.unregisterCount, 1)
        XCTAssertEqual(backend.removeHandlerCount, 1)
    }

    func testFormatterCoversModifiersLettersNumbersAndFallback() {
        XCTAssertEqual(ShortcutDisplayFormatter.string(for: .defaultSchiera), "⌃⌥⌘S")
        XCTAssertEqual(ShortcutDisplayFormatter.string(for: GlobalShortcut(keyCode: 0, modifiers: [.control, .option, .shift, .command])), "⌃⌥⇧⌘A")
        XCTAssertEqual(ShortcutDisplayFormatter.string(for: GlobalShortcut(keyCode: 18, modifiers: [.command])), "⌘1")
        XCTAssertEqual(ShortcutDisplayFormatter.string(for: GlobalShortcut(keyCode: 127, modifiers: [.shift])), "⇧Key 127")
    }
}
