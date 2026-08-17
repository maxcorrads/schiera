import AppKit
import SwiftUI

enum ShortcutEventTranslation: Equatable {
    case shortcut(GlobalShortcut)
    case cancel
    case reset
    case rejected
}

enum ShortcutEventTranslator {
    static func translate(keyCode: UInt32, modifierFlags: NSEvent.ModifierFlags) -> ShortcutEventTranslation {
        if keyCode == 53 { return .cancel }
        if keyCode == 51 || keyCode == 117 { return .reset }

        let modifierMask: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
        let flags = modifierFlags.intersection(modifierMask)
        let modifierKeyCodes: Set<UInt32> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        guard keyCode <= 127, !modifierKeyCodes.contains(keyCode), !flags.isEmpty else {
            return .rejected
        }

        var modifiers: ShortcutModifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return .shortcut(GlobalShortcut(keyCode: keyCode, modifiers: modifiers))
    }

    static func translate(_ event: NSEvent) -> ShortcutEventTranslation {
        translate(keyCode: UInt32(event.keyCode), modifierFlags: event.modifierFlags)
    }
}

struct ShortcutRecorderView: View {
    @Binding var shortcut: GlobalShortcut
    var onCommit: ((GlobalShortcut) -> Void)?

    @State private var recording = false

    init(shortcut: Binding<GlobalShortcut>) {
        self._shortcut = shortcut
    }

    init(shortcut: Binding<GlobalShortcut>, onCommit: ((GlobalShortcut) -> Void)?) {
        self._shortcut = shortcut
        self.onCommit = onCommit
    }

    var body: some View {
        ShortcutRecorderControl(shortcut: $shortcut, recording: $recording) { value in
            onCommit?(value)
        }
        .frame(width: 190, height: 30)
        .accessibilityLabel("Global shortcut")
        .accessibilityHint(recording ? "Press a modifier and key. Escape cancels." : "Activate to record a shortcut")
    }
}

private struct ShortcutRecorderControl: NSViewRepresentable {
    @Binding var shortcut: GlobalShortcut
    @Binding var recording: Bool
    let onCommit: (GlobalShortcut) -> Void

    func makeNSView(context: Context) -> RecorderNSView {
        let view = RecorderNSView()
        view.onStart = { recording = true }
        view.onResult = { result in
            switch result {
            case .shortcut(let value):
                shortcut = value
                recording = false
                onCommit(value)
            case .cancel:
                recording = false
            case .reset:
                shortcut = .defaultSchiera
                recording = false
                onCommit(.defaultSchiera)
            case .rejected:
                break
            }
        }
        return view
    }

    func updateNSView(_ nsView: RecorderNSView, context: Context) {
        nsView.recording = recording
        nsView.shortcut = shortcut
        nsView.needsDisplay = true
    }
}

private final class RecorderNSView: NSView {
    var shortcut = GlobalShortcut.defaultSchiera
    var recording = false
    var onStart: (() -> Void)?
    var onResult: ((ShortcutEventTranslation) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Global shortcut")
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Global shortcut")
    }

    override func mouseDown(with event: NSEvent) {
        startRecording()
    }

    override func keyDown(with event: NSEvent) {
        if !recording, event.keyCode == 36 || event.keyCode == 49 {
            startRecording()
            return
        }
        guard recording else {
            super.keyDown(with: event)
            return
        }
        onResult?(ShortcutEventTranslator.translate(event))
        needsDisplay = true
    }

    override func accessibilityPerformPress() -> Bool {
        startRecording()
        return true
    }

    private func startRecording() {
        recording = true
        onStart?()
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
        (recording ? NSColor.controlAccentColor.withAlphaComponent(0.18) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.stroke()

        let text = recording ? "Type shortcut…" : ShortcutDisplayFormatter.string(for: shortcut)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.labelColor
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }
}
