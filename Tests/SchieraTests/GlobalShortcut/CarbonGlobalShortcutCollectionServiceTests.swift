import Carbon
import XCTest
@testable import Schiera

private final class CollectionTestToken: NSObject {
    let number: Int

    init(number: Int) {
        self.number = number
    }
}

private final class CollectionFakeCarbonBackend: CarbonGlobalShortcutBackend {
    var installStatus: Int32 = noErr
    var statuses: [Int32] = []
    var installCount = 0
    var removeHandlerCount = 0
    var unregisterCount = 0
    var registerCalls: [(keyCode: UInt32, modifiers: UInt32, signature: UInt32, identifier: UInt32)] = []

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

    func register(
        keyCode: UInt32,
        modifiers: UInt32,
        signature: UInt32,
        identifier: UInt32
    ) -> (status: Int32, token: AnyObject?) {
        registerCalls.append((keyCode, modifiers, signature, identifier))
        let status = statuses.isEmpty ? noErr : statuses.removeFirst()
        guard status == noErr else { return (status, nil) }
        nextToken += 1
        return (noErr, CollectionTestToken(number: nextToken))
    }

    func unregister(token: AnyObject) {
        unregisterCount += 1
    }

    func emit(signature: UInt32 = 0x53434852, identifier: UInt32) {
        eventHandler?(CarbonHotKeyEvent(signature: signature, identifier: identifier))
    }
}

@MainActor
final class CarbonGlobalShortcutCollectionServiceTests: XCTestCase {
    private func registration(
        id: String,
        keyCode: UInt32,
        modifiers: ShortcutModifiers = [.command],
        handler: @escaping @MainActor @Sendable () -> Void = {}
    ) -> ShortcutRegistration {
        ShortcutRegistration(
            binding: ShortcutBinding(id: id, shortcut: GlobalShortcut(keyCode: keyCode, modifiers: modifiers)),
            handler: handler
        )
    }

    func testMultipleBindingsUseOneHandlerAndDispatchByStableIdentifier() async throws {
        let backend = CollectionFakeCarbonBackend()
        let service = CarbonGlobalShortcutCollectionService(backend: backend)
        var arrangeCalls = 0
        var profileCalls = 0

        try service.replaceAll([
            registration(id: "arrange", keyCode: 1, modifiers: [.control, .command]) { arrangeCalls += 1 },
            registration(id: "profile:row", keyCode: 0) { profileCalls += 1 }
        ])

        XCTAssertEqual(backend.installCount, 1)
        XCTAssertEqual(backend.registerCalls.count, 2)
        XCTAssertEqual(Set(backend.registerCalls.map(\.identifier)).count, 2)

        let arrangeIdentifier = try XCTUnwrap(backend.registerCalls.first { $0.keyCode == 1 }?.identifier)
        let profileIdentifier = try XCTUnwrap(backend.registerCalls.first { $0.keyCode == 0 }?.identifier)
        backend.emit(identifier: arrangeIdentifier)
        backend.emit(identifier: profileIdentifier)
        backend.emit(signature: 0x11111111, identifier: arrangeIdentifier)
        backend.emit(identifier: UInt32.max)
        await Task.yield()

        XCTAssertEqual(arrangeCalls, 1)
        XCTAssertEqual(profileCalls, 1)
        XCTAssertEqual(service.bindings.map(\.id), ["arrange", "profile:row"])
    }

    func testLegacyManagingAPIReservesArrangeAndLeavesOtherBindings() throws {
        let backend = CollectionFakeCarbonBackend()
        let service: any GlobalShortcutManaging = CarbonGlobalShortcutCollectionService(backend: backend)
        let collection = service as! any GlobalShortcutCollectionManaging

        try collection.replaceAll([registration(id: "profile:row", keyCode: 0)])
        try service.register(.defaultSchiera) {}

        XCTAssertEqual(service.currentShortcut, .defaultSchiera)
        XCTAssertEqual(collection.bindings.map(\.id), ["arrange", "profile:row"])
        service.unregister()
        XCTAssertNil(service.currentShortcut)
        XCTAssertEqual(collection.bindings.map(\.id), ["profile:row"])
    }

    func testValidationRejectsDuplicatesAndInvalidValuesBeforeCarbon() {
        let backend = CollectionFakeCarbonBackend()
        let service = CarbonGlobalShortcutCollectionService(backend: backend)

        XCTAssertThrowsError(try service.replaceAll([
            registration(id: "same", keyCode: 0),
            registration(id: "same", keyCode: 1)
        ])) { error in
            XCTAssertEqual(error as? GlobalShortcutCollectionError, .duplicateBindingID("same"))
        }
        XCTAssertThrowsError(try service.replaceAll([
            registration(id: "one", keyCode: 0),
            registration(id: "two", keyCode: 0)
        ])) { error in
            XCTAssertEqual(
                error as? GlobalShortcutCollectionError,
                .duplicateShortcut(GlobalShortcut(keyCode: 0, modifiers: [.command]), firstID: "one", secondID: "two")
            )
        }
        XCTAssertThrowsError(try service.replaceAll([
            registration(id: "bad", keyCode: 128)
        ])) { error in
            XCTAssertEqual(error as? GlobalShortcutError, .invalidShortcut)
        }
        XCTAssertEqual(backend.installCount, 0)
        XCTAssertTrue(backend.registerCalls.isEmpty)
    }

    func testSuccessfulReplacementRegistersCandidateBeforeRemovingOld() throws {
        let backend = CollectionFakeCarbonBackend()
        let service = CarbonGlobalShortcutCollectionService(backend: backend)

        try service.register(.defaultSchiera) {}
        try service.register(GlobalShortcut(keyCode: 0, modifiers: [.command])) {}

        XCTAssertEqual(backend.registerCalls.count, 2)
        XCTAssertEqual(backend.unregisterCount, 1)
        XCTAssertEqual(service.currentShortcut, GlobalShortcut(keyCode: 0, modifiers: [.command]))
    }

    func testIdenticalBindingUpdatesHandlerWithoutCarbonReplacement() async throws {
        let backend = CollectionFakeCarbonBackend()
        let service = CarbonGlobalShortcutCollectionService(backend: backend)
        var firstCalls = 0
        var secondCalls = 0

        try service.replaceAll([registration(id: "arrange", keyCode: 1) { firstCalls += 1 }])
        try service.replaceAll([registration(id: "arrange", keyCode: 1) { secondCalls += 1 }])
        let identifier = try XCTUnwrap(backend.registerCalls.first?.identifier)
        backend.emit(identifier: identifier)
        await Task.yield()

        XCTAssertEqual(backend.registerCalls.count, 1)
        XCTAssertEqual(backend.unregisterCount, 0)
        XCTAssertEqual(firstCalls, 0)
        XCTAssertEqual(secondCalls, 1)
    }

    func testFailedExternalReplacementRollsBackCandidateAndRestoresOld() async throws {
        let backend = CollectionFakeCarbonBackend()
        let service = CarbonGlobalShortcutCollectionService(backend: backend)
        var oldCalls = 0

        try service.register(.defaultSchiera) { oldCalls += 1 }
        // Initial candidate fails, retry after removing the old token fails,
        // and the third call restores the old Carbon registration.
        backend.statuses = [-10, -11, noErr]
        XCTAssertThrowsError(try service.replaceAll([registration(id: "arrange", keyCode: 0)])) { error in
            XCTAssertEqual(error as? GlobalShortcutCollectionError, .registrationFailed(bindingID: "arrange", status: -11))
        }

        XCTAssertEqual(service.currentShortcut, .defaultSchiera)
        XCTAssertEqual(backend.unregisterCount, 1)
        let oldIdentifier = try XCTUnwrap(backend.registerCalls.first?.identifier)
        backend.emit(identifier: oldIdentifier)
        await Task.yield()
        XCTAssertEqual(oldCalls, 1)
    }

    func testRollbackFailureIsTyped() throws {
        let backend = CollectionFakeCarbonBackend()
        let service = CarbonGlobalShortcutCollectionService(backend: backend)
        try service.register(.defaultSchiera) {}
        backend.statuses = [-10, -11, -12]

        XCTAssertThrowsError(try service.replaceAll([registration(id: "arrange", keyCode: 0)])) { error in
            XCTAssertEqual(error as? GlobalShortcutCollectionError, .rollbackFailed(bindingID: "arrange", status: -12))
        }
    }

    func testStableCarbonIdentifiersSurviveReorderingAndOneHandlerRemains() throws {
        let backend = CollectionFakeCarbonBackend()
        let service = CarbonGlobalShortcutCollectionService(backend: backend)
        let values = [registration(id: "profile:b", keyCode: 0), registration(id: "profile:a", keyCode: 1)]
        try service.replaceAll(values)
        let firstIDs = [
            "profile:a": backend.registerCalls.first { $0.keyCode == 1 }?.identifier,
            "profile:b": backend.registerCalls.first { $0.keyCode == 0 }?.identifier
        ]

        try service.replaceAll(Array(values.reversed()))
        XCTAssertEqual(backend.registerCalls.count, 2)
        XCTAssertEqual(backend.installCount, 1)
        XCTAssertEqual(backend.removeHandlerCount, 0)
        XCTAssertEqual(firstIDs["profile:a"], backend.registerCalls.first { $0.keyCode == 1 }?.identifier)
        XCTAssertEqual(firstIDs["profile:b"], backend.registerCalls.first { $0.keyCode == 0 }?.identifier)
    }

    func testUnregisterIsIdempotentAndRemovesHandlerAfterLastBinding() throws {
        let backend = CollectionFakeCarbonBackend()
        let service = CarbonGlobalShortcutCollectionService(backend: backend)
        try service.replaceAll([registration(id: "arrange", keyCode: 1)])
        service.unregister(id: "missing")
        service.unregister(id: "arrange")
        service.unregister(id: "arrange")
        service.unregisterAll()

        XCTAssertEqual(backend.unregisterCount, 1)
        XCTAssertEqual(backend.removeHandlerCount, 1)
    }
}
