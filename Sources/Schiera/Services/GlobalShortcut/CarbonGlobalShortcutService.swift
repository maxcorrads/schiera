import Carbon
import Foundation

private let schieraHotKeySignature: UInt32 = 0x53434852 // “SCHR”
private let schieraHotKeyIdentifier: UInt32 = 1

enum GlobalShortcutError: Error, Equatable, LocalizedError {
    case invalidShortcut
    case registrationFailed(status: Int32)
    case handlerInstallationFailed(status: Int32)

    var errorDescription: String? {
        switch self {
        case .invalidShortcut: return "The shortcut is not valid."
        case let .registrationFailed(status): return "The shortcut could not be registered (status \(status))."
        case let .handlerInstallationFailed(status): return "The shortcut handler could not be installed (status \(status))."
        }
    }
}

struct CarbonHotKeyEvent: Sendable {
    let signature: UInt32
    let identifier: UInt32
}

protocol CarbonGlobalShortcutBackend: AnyObject {
    func installEventHandler(_ handler: @escaping @Sendable (CarbonHotKeyEvent) -> Void) -> Int32
    func removeEventHandler()
    func register(keyCode: UInt32, modifiers: UInt32, signature: UInt32, identifier: UInt32) -> (status: Int32, token: AnyObject?)
    func unregister(token: AnyObject)
}

@MainActor
protocol GlobalShortcutManaging: AnyObject {
    var currentShortcut: GlobalShortcut? { get }
    func register(_ shortcut: GlobalShortcut, handler: @escaping @MainActor @Sendable () -> Void) throws
    func unregister()
}

@MainActor
final class CarbonGlobalShortcutService: GlobalShortcutManaging {
    private static let knownModifiers = ShortcutModifiers([.control, .option, .shift, .command])

    private let backend: CarbonGlobalShortcutBackend
    private var eventHandlerInstalled = false
    private var registrationToken: AnyObject?
    private var handler: (@MainActor @Sendable () -> Void)?
    private(set) var currentShortcut: GlobalShortcut?

    init() {
        backend = LiveCarbonGlobalShortcutBackend()
    }

    init(backend: CarbonGlobalShortcutBackend) {
        self.backend = backend
    }

    deinit {
        // Carbon teardown is safe and idempotent in the live backend. The service is
        // main-actor isolated, so this also prevents a callback racing deallocation.
        if let registrationToken { backend.unregister(token: registrationToken) }
        if eventHandlerInstalled { backend.removeEventHandler() }
    }

    func register(_ shortcut: GlobalShortcut, handler: @escaping @MainActor @Sendable () -> Void) throws {
        guard Self.isValid(shortcut) else { throw GlobalShortcutError.invalidShortcut }

        if currentShortcut == shortcut, registrationToken != nil {
            self.handler = handler
            return
        }

        if !eventHandlerInstalled {
            let status = backend.installEventHandler { [weak self] event in
                guard event.signature == schieraHotKeySignature, event.identifier == schieraHotKeyIdentifier else { return }
                Task { @MainActor [weak self] in self?.handler?() }
            }
            guard status == noErr else { throw GlobalShortcutError.handlerInstallationFailed(status: status) }
            eventHandlerInstalled = true
        }

        let result = backend.register(
            keyCode: shortcut.keyCode,
            modifiers: Self.carbonModifiers(for: shortcut.modifiers),
            signature: schieraHotKeySignature,
            identifier: schieraHotKeyIdentifier
        )
        guard result.status == noErr, let candidate = result.token else {
            // The previous registration and handler have deliberately not been touched.
            if currentShortcut == nil {
                backend.removeEventHandler()
                eventHandlerInstalled = false
            }
            throw GlobalShortcutError.registrationFailed(status: result.status)
        }

        if let old = registrationToken { backend.unregister(token: old) }
        registrationToken = candidate
        currentShortcut = shortcut
        self.handler = handler
    }

    func unregister() {
        if let registrationToken {
            backend.unregister(token: registrationToken)
            self.registrationToken = nil
        }
        handler = nil
        currentShortcut = nil
        if eventHandlerInstalled {
            backend.removeEventHandler()
            eventHandlerInstalled = false
        }
    }

    static func isValid(_ shortcut: GlobalShortcut) -> Bool {
        guard shortcut.keyCode <= 127,
              shortcut.modifiers.rawValue != 0,
              shortcut.modifiers.rawValue & ~knownModifiers.rawValue == 0 else { return false }
        // Physical modifier keys are not usable as the non-modifier key in a hotkey.
        return ![54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(shortcut.keyCode)
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

enum ShortcutDisplayFormatter {
    static func string(for shortcut: GlobalShortcut) -> String {
        var result = ""
        if shortcut.modifiers.contains(.control) { result += "⌃" }
        if shortcut.modifiers.contains(.option) { result += "⌥" }
        if shortcut.modifiers.contains(.shift) { result += "⇧" }
        if shortcut.modifiers.contains(.command) { result += "⌘" }
        result += keyName(shortcut.keyCode)
        return result
    }

    private static func keyName(_ keyCode: UInt32) -> String {
        let names: [UInt32: String] = [0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",17:"T",16:"Y",32:"U",34:"I",31:"O",35:"P",18:"1",19:"2",20:"3",21:"4",23:"5",22:"6",26:"7",28:"8",25:"9",29:"0"]
        return names[keyCode] ?? "Key \(keyCode)"
    }
}

private final class LiveHotKeyToken: NSObject {
    let ref: EventHotKeyRef
    init(_ ref: EventHotKeyRef) { self.ref = ref }
}

private final class LiveCarbonGlobalShortcutBackend: CarbonGlobalShortcutBackend {
    private var eventHandlerRef: EventHandlerRef?
    private var installedHandler: (@Sendable (CarbonHotKeyEvent) -> Void)?

    func installEventHandler(_ handler: @escaping @Sendable (CarbonHotKeyEvent) -> Void) -> Int32 {
        installedHandler = handler
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            let backend = Unmanaged<LiveCarbonGlobalShortcutBackend>.fromOpaque(userData).takeUnretainedValue()
            var id = EventHotKeyID()
            var size = MemoryLayout<EventHotKeyID>.size
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, size, &size, &id)
            if status == noErr { backend.installedHandler?(CarbonHotKeyEvent(signature: id.signature, identifier: id.id)) }
            return OSStatus(noErr)
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandlerRef)
        return Int32(status)
    }

    func removeEventHandler() {
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
        eventHandlerRef = nil
        installedHandler = nil
    }

    func register(keyCode: UInt32, modifiers: UInt32, signature: UInt32, identifier: UInt32) -> (status: Int32, token: AnyObject?) {
        let id = EventHotKeyID(signature: signature, id: identifier)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode), modifiers, id, GetEventDispatcherTarget(), OptionBits(kEventHotKeyExclusive), &ref)
        guard status == noErr, let ref else { return (Int32(status), nil) }
        return (Int32(status), LiveHotKeyToken(ref))
    }

    func unregister(token: AnyObject) {
        if let token = token as? LiveHotKeyToken { UnregisterEventHotKey(token.ref) }
    }
}
