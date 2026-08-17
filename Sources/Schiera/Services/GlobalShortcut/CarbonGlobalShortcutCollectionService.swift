import Carbon
import Foundation

/// A stable application-owned name for one action bound to a global shortcut.
/// The name is persisted by callers; it must not be a display label.
struct ShortcutBinding: Hashable, Codable, Sendable {
    let id: String
    let shortcut: GlobalShortcut

    init(id: String, shortcut: GlobalShortcut) {
        self.id = id
        self.shortcut = shortcut
    }
}

/// A runtime binding and the action delivered when its hot key is pressed.
struct ShortcutRegistration: Sendable {
    let binding: ShortcutBinding
    let handler: @MainActor @Sendable () -> Void

    init(binding: ShortcutBinding, handler: @escaping @MainActor @Sendable () -> Void) {
        self.binding = binding
        self.handler = handler
    }
}

// Descriptive aliases make the collection API easy to discover without adding
// a second representation of a persisted binding.
typealias GlobalShortcutBinding = ShortcutBinding
typealias GlobalShortcutRegistration = ShortcutRegistration

enum GlobalShortcutCollectionError: Error, Equatable, LocalizedError {
    case invalidBindingID
    case duplicateBindingID(String)
    case duplicateShortcut(GlobalShortcut, firstID: String, secondID: String)
    case registrationFailed(bindingID: String, status: Int32)
    case handlerInstallationFailed(status: Int32)
    case rollbackFailed(bindingID: String, status: Int32)

    var errorDescription: String? {
        switch self {
        case .invalidBindingID:
            return "The shortcut binding identifier is not valid."
        case let .duplicateBindingID(id):
            return "The shortcut binding identifier \(id) is used more than once."
        case let .duplicateShortcut(_, firstID, secondID):
            return "The shortcut is assigned to both \(firstID) and \(secondID)."
        case let .registrationFailed(bindingID, status):
            return "The shortcut for \(bindingID) could not be registered (status \(status))."
        case let .handlerInstallationFailed(status):
            return "The shortcut handler could not be installed (status \(status))."
        case let .rollbackFailed(bindingID, status):
            return "The previous shortcut for \(bindingID) could not be restored (status \(status))."
        }
    }
}

@MainActor
protocol GlobalShortcutCollectionManaging: AnyObject {
    var bindings: [ShortcutBinding] { get }

    /// Replaces the complete set as one logical transaction. Existing
    /// registrations remain active if any candidate cannot be registered.
    func replaceAll(_ registrations: [ShortcutRegistration]) throws
    func register(_ binding: ShortcutBinding, handler: @escaping @MainActor @Sendable () -> Void) throws
    func unregister(id: String)
    func unregisterAll()
}

@MainActor
final class CarbonGlobalShortcutCollectionService: GlobalShortcutCollectionManaging, GlobalShortcutManaging {
    private static let signature: UInt32 = 0x53434852 // “SCHR”
    static let arrangeBindingID = "arrange"
    private static let legacyCarbonIdentifier: UInt32 = 1
    private static let firstCarbonIdentifier: UInt32 = 2
    private static let knownModifiers = ShortcutModifiers([.control, .option, .shift, .command])
    private static let physicalModifierKeyCodes: Set<UInt32> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    private struct ActiveRegistration {
        let registration: ShortcutRegistration
        let carbonIdentifier: UInt32
        let token: AnyObject

        var binding: ShortcutBinding { registration.binding }
        var handler: @MainActor @Sendable () -> Void { registration.handler }
    }

    private struct CandidateResult {
        let records: [String: ActiveRegistration]
        let discardedOldRegistrations: Bool
    }

    private let backend: CarbonGlobalShortcutBackend
    private var eventHandlerInstalled = false
    private var active: [String: ActiveRegistration] = [:]

    init() {
        backend = CollectionLiveCarbonGlobalShortcutBackend()
    }

    init(backend: CarbonGlobalShortcutBackend) {
        self.backend = backend
    }

    var bindings: [ShortcutBinding] {
        active.values.map(\.binding).sorted { $0.id < $1.id }
    }

    var currentShortcut: GlobalShortcut? {
        active[Self.arrangeBindingID]?.binding.shortcut
    }

    deinit {
        for record in active.values {
            backend.unregister(token: record.token)
        }
        if eventHandlerInstalled {
            backend.removeEventHandler()
        }
    }

    func replaceAll(_ registrations: [ShortcutRegistration]) throws {
        let candidates = try validated(registrations)
        let candidateByID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.binding.id, $0) })

        let unchangedIDs = Set(active.keys).intersection(candidateByID.keys).filter { id in
            active[id]?.binding == candidateByID[id]?.binding
        }
        let changedCandidates = candidates.filter { !unchangedIDs.contains($0.binding.id) }

        if candidates.isEmpty {
            let old = active
            active.removeAll()
            for record in old.values { backend.unregister(token: record.token) }
            removeEventHandlerIfNeeded()
            return
        }

        var installedForTransaction = false
        if !eventHandlerInstalled {
            let signature = Self.signature
            let status = backend.installEventHandler { [weak self] event in
                guard event.signature == signature else { return }
                Task { @MainActor [weak self] in
                    self?.dispatch(identifier: event.identifier)
                }
            }
            guard status == noErr else {
                throw GlobalShortcutCollectionError.handlerInstallationFailed(status: status)
            }
            eventHandlerInstalled = true
            installedForTransaction = true
        }

        let old = active
        let obsoleteIDs = Set(old.keys).subtracting(candidateByID.keys)
        let changedOldIDs = Set(old.keys).subtracting(unchangedIDs).intersection(candidateByID.keys)
        let oldToDiscardIDs = obsoleteIDs.union(changedOldIDs)
        let oldToDiscard = oldToDiscardIDs.compactMap { old[$0] }

        do {
            let transaction = try registerCandidates(
                changedCandidates,
                oldToDiscard: oldToDiscard
            )

            var next: [String: ActiveRegistration] = [:]
            for candidate in candidates {
                if unchangedIDs.contains(candidate.binding.id), let retained = old[candidate.binding.id] {
                    // Keep Carbon's registration token while replacing its closure.
                    next[candidate.binding.id] = ActiveRegistration(
                        registration: candidate,
                        carbonIdentifier: retained.carbonIdentifier,
                        token: retained.token
                    )
                } else if let record = transaction.records[candidate.binding.id] {
                    next[candidate.binding.id] = record
                }
            }

            // Publishing the map before removing obsolete Carbon registrations
            // makes event delivery atomic from the service's point of view.
            active = next
            if !transaction.discardedOldRegistrations {
                for record in oldToDiscard {
                    backend.unregister(token: record.token)
                }
            }
        } catch {
            if installedForTransaction && active.isEmpty {
                removeEventHandlerIfNeeded()
            }
            throw error
        }
    }

    func unregister(id: String) {
        guard active[id] != nil else { return }
        let remaining = active.values
            .filter { $0.binding.id != id }
            .map { $0.registration }
        // Removing an unchanged registration cannot call Carbon registration;
        // retaining the old state is the safest response to an unexpected error.
        try? replaceAll(remaining)
    }

    func unregisterAll() {
        let old = active
        active.removeAll()
        for record in old.values { backend.unregister(token: record.token) }
        removeEventHandlerIfNeeded()
    }

    // MARK: GlobalShortcutManaging compatibility

    func register(_ shortcut: GlobalShortcut, handler: @escaping @MainActor @Sendable () -> Void) throws {
        let arrange = ShortcutRegistration(
            binding: ShortcutBinding(id: Self.arrangeBindingID, shortcut: shortcut),
            handler: handler
        )
        let otherRegistrations = active.values
            .filter { $0.binding.id != Self.arrangeBindingID }
            .map { $0.registration }
        try replaceAll(otherRegistrations + [arrange])
    }

    func unregister() {
        unregister(id: Self.arrangeBindingID)
    }

    func register(_ binding: ShortcutBinding, handler: @escaping @MainActor @Sendable () -> Void) throws {
        let value = ShortcutRegistration(binding: binding, handler: handler)
        let otherRegistrations = active.values
            .filter { $0.binding.id != binding.id }
            .map { $0.registration }
        try replaceAll(otherRegistrations + [value])
    }

    // MARK: Validation and transaction helpers

    private func validated(_ registrations: [ShortcutRegistration]) throws -> [ShortcutRegistration] {
        var seenIDs = Set<String>()
        var seenShortcuts: [GlobalShortcut: String] = [:]

        for registration in registrations {
            let id = registration.binding.id
            guard !id.isEmpty, !id.contains("\0") else {
                throw GlobalShortcutCollectionError.invalidBindingID
            }
            guard seenIDs.insert(id).inserted else {
                throw GlobalShortcutCollectionError.duplicateBindingID(id)
            }
            guard Self.isValid(registration.binding.shortcut) else {
                throw GlobalShortcutError.invalidShortcut
            }
            if let firstID = seenShortcuts[registration.binding.shortcut] {
                throw GlobalShortcutCollectionError.duplicateShortcut(
                    registration.binding.shortcut,
                    firstID: firstID,
                    secondID: id
                )
            }
            seenShortcuts[registration.binding.shortcut] = id
        }
        return registrations.sorted { $0.binding.id < $1.binding.id }
    }

    private func registerCandidates(
        _ candidates: [ShortcutRegistration],
        oldToDiscard: [ActiveRegistration],
    ) throws -> CandidateResult {
        guard !candidates.isEmpty else {
            return CandidateResult(records: [:], discardedOldRegistrations: false)
        }

        do {
            return CandidateResult(
                records: try registerCandidateList(candidates, excluding: Set<UInt32>()),
                discardedOldRegistrations: false
            )
        } catch let firstError as GlobalShortcutCollectionError {
            // Normally Carbon permits candidate-first replacement. A candidate
            // with an old binding's exact combination may require the old token
            // to be removed first; retry through the deterministic rollback path.
            guard case .registrationFailed = firstError,
                  !oldToDiscard.isEmpty else { throw firstError }

            for record in oldToDiscard.sorted(by: { $0.binding.id < $1.binding.id }) {
                backend.unregister(token: record.token)
            }

            do {
                return CandidateResult(
                    records: try registerCandidateList(candidates, excluding: Set(oldToDiscard.map(\.carbonIdentifier))),
                    discardedOldRegistrations: true
                )
            } catch let retryError as GlobalShortcutCollectionError {
                let restored = restoreOld(oldToDiscard)
                if let failedID = restored.failedID {
                    throw GlobalShortcutCollectionError.rollbackFailed(
                        bindingID: failedID,
                        status: restored.status
                    )
                }
                for record in restored.records {
                    active[record.binding.id] = record
                }
                throw retryError
            } catch {
                let restored = restoreOld(oldToDiscard)
                for record in restored.records {
                    active[record.binding.id] = record
                }
                throw error
            }
        } catch {
            throw error
        }
    }

    private func registerCandidateList(
        _ candidates: [ShortcutRegistration],
        excluding excludedIdentifiers: Set<UInt32>
    ) throws -> [String: ActiveRegistration] {
        var records: [String: ActiveRegistration] = [:]
        var usedIdentifiers = Set(active.values.map(\.carbonIdentifier)).subtracting(excludedIdentifiers)

        do {
            for candidate in candidates {
                let identifier = carbonIdentifier(for: candidate.binding.id, used: &usedIdentifiers)
                let result = backend.register(
                    keyCode: candidate.binding.shortcut.keyCode,
                    modifiers: Self.carbonModifiers(for: candidate.binding.shortcut.modifiers),
                    signature: Self.signature,
                    identifier: identifier
                )
                guard result.status == noErr, let token = result.token else {
                    throw GlobalShortcutCollectionError.registrationFailed(
                        bindingID: candidate.binding.id,
                        status: result.status
                    )
                }
                records[candidate.binding.id] = ActiveRegistration(
                    registration: candidate,
                    carbonIdentifier: identifier,
                    token: token
                )
            }
            return records
        } catch {
            for record in records.values {
                backend.unregister(token: record.token)
            }
            throw error
        }
    }

    private func restoreOld(_ records: [ActiveRegistration]) -> (
        records: [ActiveRegistration],
        failedID: String?,
        status: Int32
    ) {
        var restored: [ActiveRegistration] = []
        for record in records.sorted(by: { $0.binding.id < $1.binding.id }) {
            let result = backend.register(
                keyCode: record.binding.shortcut.keyCode,
                modifiers: Self.carbonModifiers(for: record.binding.shortcut.modifiers),
                signature: Self.signature,
                identifier: record.carbonIdentifier
            )
            guard result.status == noErr, result.token != nil else {
                return (restored, record.binding.id, result.status)
            }
            restored.append(ActiveRegistration(
                registration: record.registration,
                carbonIdentifier: record.carbonIdentifier,
                token: result.token!
            ))
        }
        return (restored, nil, noErr)
    }

    private func carbonIdentifier(for id: String, used: inout Set<UInt32>) -> UInt32 {
        if id == Self.arrangeBindingID {
            used.insert(Self.legacyCarbonIdentifier)
            return Self.legacyCarbonIdentifier
        }

        // FNV-1a gives a stable process-independent identifier. Collision
        // probing is deterministic because candidates are sorted by binding ID.
        var value: UInt32 = 2_166_136_261
        for byte in id.utf8 {
            value ^= UInt32(byte)
            value = value &* 16_777_619
        }
        if value < Self.firstCarbonIdentifier { value = Self.firstCarbonIdentifier }
        while used.contains(value) || value == Self.legacyCarbonIdentifier {
            value = value == UInt32.max ? Self.firstCarbonIdentifier : value &+ 1
        }
        used.insert(value)
        return value
    }

    private func dispatch(identifier: UInt32) {
        active.values.first(where: { $0.carbonIdentifier == identifier })?.handler()
    }

    private func removeEventHandlerIfNeeded() {
        guard eventHandlerInstalled, active.isEmpty else { return }
        backend.removeEventHandler()
        eventHandlerInstalled = false
    }

    static func isValid(_ shortcut: GlobalShortcut) -> Bool {
        guard shortcut.keyCode <= 127,
              shortcut.modifiers.rawValue != 0,
              shortcut.modifiers.rawValue & ~knownModifiers.rawValue == 0 else { return false }
        return !physicalModifierKeyCodes.contains(shortcut.keyCode)
    }

    static func carbonModifiers(for modifiers: ShortcutModifiers) -> UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }
}

private final class CollectionLiveHotKeyToken: NSObject {
    let ref: EventHotKeyRef

    init(_ ref: EventHotKeyRef) {
        self.ref = ref
    }
}

/// The singleton service's live adapter is private to its file. Keep this
/// adapter local to the collection service so both services can use the same
/// narrow backend contract without changing the existing implementation.
private final class CollectionLiveCarbonGlobalShortcutBackend: CarbonGlobalShortcutBackend {
    private var eventHandlerRef: EventHandlerRef?
    private var installedHandler: (@Sendable (CarbonHotKeyEvent) -> Void)?

    func installEventHandler(_ handler: @escaping @Sendable (CarbonHotKeyEvent) -> Void) -> Int32 {
        installedHandler = handler
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let userData, let event else {
                    return OSStatus(eventNotHandledErr)
                }
                let backend = Unmanaged<CollectionLiveCarbonGlobalShortcutBackend>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                var id = EventHotKeyID()
                var size = MemoryLayout<EventHotKeyID>.size
                let parameterStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    size,
                    &size,
                    &id
                )
                if parameterStatus == noErr {
                    backend.installedHandler?(CarbonHotKeyEvent(
                        signature: id.signature,
                        identifier: id.id
                    ))
                }
                return OSStatus(noErr)
            },
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
        return Int32(status)
    }

    func removeEventHandler() {
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
        eventHandlerRef = nil
        installedHandler = nil
    }

    func register(
        keyCode: UInt32,
        modifiers: UInt32,
        signature: UInt32,
        identifier: UInt32
    ) -> (status: Int32, token: AnyObject?) {
        let id = EventHotKeyID(signature: signature, id: identifier)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            id,
            GetEventDispatcherTarget(),
            OptionBits(kEventHotKeyExclusive),
            &ref
        )
        guard status == noErr, let ref else {
            return (Int32(status), nil)
        }
        return (Int32(status), CollectionLiveHotKeyToken(ref))
    }

    func unregister(token: AnyObject) {
        if let token = token as? CollectionLiveHotKeyToken {
            UnregisterEventHotKey(token.ref)
        }
    }
}
