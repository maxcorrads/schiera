import Foundation
import SwiftUI

enum PreferenceConstraints {
    static let defaultGap: Double = 8
    static let minimumGap: Double = 0
    static let maximumGap: Double = 64
}

enum TerminalCatalog {
    static let applications: [TerminalApplicationDefinition] = [
        TerminalApplicationDefinition(id: "terminal", displayName: "Terminal", bundleIdentifiers: ["com.apple.Terminal"], defaultEnabled: true),
        TerminalApplicationDefinition(id: "iterm2", displayName: "iTerm2", bundleIdentifiers: ["com.googlecode.iterm2"], defaultEnabled: true),
        TerminalApplicationDefinition(id: "warp", displayName: "Warp", bundleIdentifiers: ["dev.warp.Warp-Stable", "dev.warp.Warp-Preview", "dev.warp.Warp"], defaultEnabled: true),
        TerminalApplicationDefinition(id: "ghostty", displayName: "Ghostty", bundleIdentifiers: ["com.mitchellh.ghostty"], defaultEnabled: true),
        TerminalApplicationDefinition(id: "alacritty", displayName: "Alacritty", bundleIdentifiers: ["org.alacritty"], defaultEnabled: true),
        TerminalApplicationDefinition(id: "kitty", displayName: "kitty", bundleIdentifiers: ["net.kovidgoyal.kitty"], defaultEnabled: true),
        TerminalApplicationDefinition(id: "wezterm", displayName: "WezTerm", bundleIdentifiers: ["com.github.wez.wezterm"], defaultEnabled: true)
    ]

    static var defaultIncludedIDs: Set<String> {
        Set(applications.filter(\.defaultEnabled).map(\.id))
    }

    static func bundleIdentifiers(forIncludedIDs ids: Set<String>) -> Set<String> {
        applications.filter { ids.contains($0.id) }.reduce(into: Set<String>()) { result, definition in
            result.formUnion(definition.bundleIdentifiers)
        }
    }
}

@MainActor
protocol PreferencesProviding: AnyObject {
    var gap: Double { get set }
    var includedTerminalIDs: Set<String> { get set }
    var shortcut: GlobalShortcut { get set }
    var layoutMode: LayoutMode { get set }
    func reset()
}

extension PreferencesProviding {
    var layoutMode: LayoutMode {
        get { .row }
        set {}
    }
}

@MainActor
final class PreferencesStore: ObservableObject, PreferencesProviding {
    private enum Keys {
        static let gap = "windowGap"
        static let includedTerminalIDs = "includedTerminalIDs"
        static let shortcut = "globalShortcut"
        static let layoutMode = "layoutMode"
    }

    private struct StoredShortcut: Codable {
        let version: Int
        let keyCode: UInt32
        let modifiers: UInt32
    }

    private let defaults: UserDefaults
    private let knownIDs: Set<String>

    @Published var gap: Double {
        didSet {
            let normalized = Self.validatedGap(gap)
            if gap != normalized {
                gap = normalized
                return
            }
            defaults.set(normalized, forKey: Keys.gap)
        }
    }

    @Published var includedTerminalIDs: Set<String> {
        didSet {
            let normalized = includedTerminalIDs.intersection(knownIDs)
            if includedTerminalIDs != normalized {
                includedTerminalIDs = normalized
                return
            }
            if let data = try? PropertyListEncoder().encode(Array(normalized).sorted()) {
                defaults.set(data, forKey: Keys.includedTerminalIDs)
            }
        }
    }

    @Published var shortcut: GlobalShortcut {
        didSet {
            let normalized = Self.validatedShortcut(shortcut)
            if shortcut != normalized {
                shortcut = normalized
                return
            }
            let stored = StoredShortcut(version: 1, keyCode: normalized.keyCode, modifiers: normalized.modifiers.rawValue)
            if let data = try? PropertyListEncoder().encode(stored) {
                defaults.set(data, forKey: Keys.shortcut)
            }
        }
    }

    @Published var layoutMode: LayoutMode {
        didSet {
            defaults.set(layoutMode.rawValue, forKey: Keys.layoutMode)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.knownIDs = Set(TerminalCatalog.applications.map(\.id))
        self._gap = Published(initialValue: Self.readGap(from: defaults))
        self._includedTerminalIDs = Published(initialValue: Self.readIncludedIDs(from: defaults, knownIDs: knownIDs))
        self._shortcut = Published(initialValue: Self.readShortcut(from: defaults))
        self._layoutMode = Published(initialValue: Self.readLayoutMode(from: defaults))
    }

    func reset() {
        gap = PreferenceConstraints.defaultGap
        includedTerminalIDs = TerminalCatalog.defaultIncludedIDs
        shortcut = .defaultSchiera
        layoutMode = .row
    }

    private static func validatedGap(_ value: Double) -> Double {
        guard value.isFinite else { return PreferenceConstraints.defaultGap }
        return min(max(value, PreferenceConstraints.minimumGap), PreferenceConstraints.maximumGap)
    }

    private static let supportedModifierMask = ShortcutModifiers.control.rawValue
        | ShortcutModifiers.option.rawValue
        | ShortcutModifiers.shift.rawValue
        | ShortcutModifiers.command.rawValue

    private static func validatedShortcut(_ value: GlobalShortcut) -> GlobalShortcut {
        guard value.keyCode <= 127,
              value.modifiers.rawValue != 0,
              value.modifiers.rawValue & ~supportedModifierMask == 0 else {
            return .defaultSchiera
        }
        return value
    }

    private static func readGap(from defaults: UserDefaults) -> Double {
        guard let value = defaults.object(forKey: Keys.gap) as? Double, value.isFinite else {
            return PreferenceConstraints.defaultGap
        }
        return validatedGap(value)
    }

    private static func readIncludedIDs(from defaults: UserDefaults, knownIDs: Set<String>) -> Set<String> {
        guard defaults.object(forKey: Keys.includedTerminalIDs) != nil else { return knownIDs }
        guard let data = defaults.data(forKey: Keys.includedTerminalIDs),
              let values = try? PropertyListDecoder().decode([String].self, from: data) else {
            return knownIDs
        }
        return Set(values).intersection(knownIDs)
    }

    private static func readShortcut(from defaults: UserDefaults) -> GlobalShortcut {
        guard let data = defaults.data(forKey: Keys.shortcut),
              let stored = try? PropertyListDecoder().decode(StoredShortcut.self, from: data),
              stored.version == 1 else {
            return .defaultSchiera
        }
        return validatedShortcut(GlobalShortcut(keyCode: stored.keyCode, modifiers: ShortcutModifiers(rawValue: stored.modifiers)))
    }

    private static func readLayoutMode(from defaults: UserDefaults) -> LayoutMode {
        guard let rawValue = defaults.string(forKey: Keys.layoutMode),
              let mode = LayoutMode(rawValue: rawValue) else {
            return .row
        }
        return mode
    }
}
