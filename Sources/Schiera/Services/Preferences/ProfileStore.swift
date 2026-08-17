import Foundation
import SwiftUI

@MainActor
protocol ProfileProviding: AnyObject {
    var profiles: [ArrangementProfile] { get }
    var activeProfileID: UUID { get set }
    var activeProfile: ArrangementProfile { get }
    var layoutShortcuts: [LayoutShortcutBinding] { get set }

    // CRUD operations are concrete ProfileStore conveniences. Keeping the
    // protocol narrow lets UI fakes provide only the transactional boundary.
    func deleteProfile(id: UUID)
    func upsert(_ profile: ArrangementProfile)
}

@MainActor
final class ProfileStore: ObservableObject, ProfileProviding {
    static let storageKey = "savedProfiles"
    private static let schemaVersion = 1

    private enum Defaults {
        static let name = "Default"
        static let profileName = "Profile"
    }

    private let defaults: UserDefaults
    private let knownTerminalIDs: Set<String>
    private var persistenceSuspended: Bool

    @Published private(set) var profiles: [ArrangementProfile]

    @Published var activeProfileID: UUID {
        didSet {
            persistenceSuspended = false
            guard profiles.contains(where: { $0.id == activeProfileID }) else {
                if let first = profiles.first, first.id != activeProfileID {
                    activeProfileID = first.id
                }
                return
            }
            persist()
        }
    }

    @Published var layoutShortcuts: [LayoutShortcutBinding] {
        didSet {
            persistenceSuspended = false
            let normalized = Self.normalizedLayoutShortcuts(layoutShortcuts)
            if normalized != layoutShortcuts {
                layoutShortcuts = normalized
                return
            }
            persist()
        }
    }

    var activeProfile: ArrangementProfile {
        profiles.first { $0.id == activeProfileID } ?? profiles[0]
    }

    init(defaults: UserDefaults = .standard, seed: ArrangementProfile? = nil) {
        self.defaults = defaults
        self.knownTerminalIDs = Set(TerminalCatalog.applications.map(\.id))

        let fallback = (seed ?? Self.defaultProfile(knownTerminalIDs: knownTerminalIDs))
            .normalized(knownTerminalIDs: knownTerminalIDs)
        let loaded = Self.load(from: defaults, knownTerminalIDs: knownTerminalIDs)
        let sourceProfiles = loaded?.profiles.isEmpty == false ? loaded!.profiles : [fallback]
        let normalizedProfiles = Self.normalizedProfiles(sourceProfiles, knownTerminalIDs: knownTerminalIDs)
        let selectedID = loaded?.activeProfileID.flatMap { id in
            normalizedProfiles.contains(where: { $0.id == id }) ? id : nil
        } ?? normalizedProfiles[0].id

        self.persistenceSuspended = loaded?.isUnsupportedVersion ?? false
        self._profiles = Published(initialValue: normalizedProfiles)
        self._activeProfileID = Published(initialValue: selectedID)
        self._layoutShortcuts = Published(initialValue: Self.normalizedLayoutShortcuts(loaded?.layoutShortcuts ?? []))

        if loaded == nil || loaded?.needsRepair == true {
            persist()
        }
    }

    @discardableResult
    func create(name: String = Defaults.profileName) -> ArrangementProfile {
        let profile = ArrangementProfile(
            id: UUID(),
            name: uniqueName(name),
            layoutMode: .row,
            gap: PreferenceConstraints.defaultGap,
            includedTerminalIDs: TerminalCatalog.defaultIncludedIDs,
            focusTargetMode: .activeWindow,
            customization: .default,
            displayBinding: nil,
            shortcut: nil
        )
        profiles.append(profile)
        persistenceSuspended = false
        persist()
        return profile
    }

    @discardableResult
    func createProfile(named name: String = Defaults.profileName) -> ArrangementProfile {
        create(name: name)
    }

    @discardableResult
    func create(from profile: ArrangementProfile, name: String? = nil) -> ArrangementProfile {
        let copy = ArrangementProfile(
            id: UUID(),
            name: uniqueName(name ?? profile.name),
            layoutMode: profile.layoutMode,
            gap: profile.gap,
            includedTerminalIDs: profile.includedTerminalIDs,
            focusTargetMode: profile.focusTargetMode,
            customization: profile.customization,
            displayBinding: profile.displayBinding,
            shortcut: profile.shortcut
        ).normalized(knownTerminalIDs: knownTerminalIDs)
        profiles.append(copy)
        persistenceSuspended = false
        persist()
        return copy
    }

    @discardableResult
    func duplicate(id: UUID, name: String? = nil) -> ArrangementProfile? {
        guard let profile = profiles.first(where: { $0.id == id }) else { return nil }
        return create(from: profile, name: name)
    }

    @discardableResult
    func duplicateProfile(id: UUID, name: String? = nil) -> ArrangementProfile? {
        duplicate(id: id, name: name)
    }

    @discardableResult
    func rename(id: UUID, to name: String) -> Bool {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return false }
        profiles[index].name = uniqueName(name, excluding: id)
        profiles[index] = profiles[index].normalized(knownTerminalIDs: knownTerminalIDs)
        persistenceSuspended = false
        persist()
        return true
    }

    @discardableResult
    func renameProfile(id: UUID, to name: String) -> Bool {
        rename(id: id, to: name)
    }

    @discardableResult
    func delete(id: UUID) -> Bool {
        guard profiles.count > 1,
              let index = profiles.firstIndex(where: { $0.id == id }) else { return false }
        profiles.remove(at: index)
        if activeProfileID == id {
            activeProfileID = profiles[index == profiles.count ? profiles.count - 1 : index].id
        }
        persistenceSuspended = false
        persist()
        return true
    }

    @discardableResult
    func remove(id: UUID) -> Bool {
        delete(id: id)
    }

    func deleteProfile(id: UUID) {
        _ = delete(id: id)
    }

    func upsert(_ profile: ArrangementProfile) {
        var normalized = profile.normalized(knownTerminalIDs: knownTerminalIDs)
        normalized.name = uniqueName(normalized.name, excluding: normalized.id)
        if let index = profiles.firstIndex(where: { $0.id == normalized.id }) {
            profiles[index] = normalized
        } else {
            profiles.append(normalized)
        }
        persistenceSuspended = false
        persist()
    }

    func upsertLayoutShortcut(_ binding: LayoutShortcutBinding) {
        var candidate = layoutShortcuts.filter { $0.mode != binding.mode && $0.shortcut != binding.shortcut }
        candidate.append(binding)
        layoutShortcuts = candidate
    }

    func removeLayoutShortcut(for mode: LayoutMode) {
        layoutShortcuts.removeAll { $0.mode == mode }
    }

    private func persist() {
        guard !persistenceSuspended else { return }
        let payload = StoredPayload(
            version: Self.schemaVersion,
            activeProfileID: activeProfileID,
            profiles: profiles.map(StoredProfile.init),
            layoutShortcuts: layoutShortcuts
        )
        guard let data = try? PropertyListEncoder().encode(payload) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private func uniqueName(_ requested: String, excluding id: UUID? = nil) -> String {
        let base = normalizedName(requested)
        let used = Set(profiles.filter { $0.id != id }.map { $0.name.lowercased() })
        guard used.contains(base.lowercased()) else { return base }

        let root: String
        if let separator = base.lastIndex(of: " "),
           Int(base[base.index(after: separator)...]) != nil {
            root = String(base[..<separator])
        } else {
            root = base
        }
        var suffix = 2
        while true {
            let suffixText = " \(suffix)"
            let prefixLength = max(1, 48 - suffixText.count)
            let candidate = String(root.prefix(prefixLength)) + suffixText
            if !used.contains(candidate.lowercased()) { return candidate }
            suffix += 1
        }
    }

    private func normalizedName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((trimmed.isEmpty ? Defaults.profileName : trimmed).prefix(48))
    }

    private static func defaultProfile(knownTerminalIDs: Set<String>) -> ArrangementProfile {
        ArrangementProfile(
            id: UUID(),
            name: Defaults.name,
            layoutMode: .row,
            gap: PreferenceConstraints.defaultGap,
            includedTerminalIDs: knownTerminalIDs,
            focusTargetMode: .activeWindow,
            customization: .default,
            displayBinding: nil,
            shortcut: nil
        )
    }

    private static func normalizedProfiles(
        _ profiles: [ArrangementProfile],
        knownTerminalIDs: Set<String>
    ) -> [ArrangementProfile] {
        var result: [ArrangementProfile] = []
        var usedNames = Set<String>()
        for profile in profiles {
            var normalized = profile.normalized(knownTerminalIDs: knownTerminalIDs)
            let base = normalized.name
            var candidate = base
            var suffix = 2
            while usedNames.contains(candidate.lowercased()) {
                let suffixText = " \(suffix)"
                let prefixLength = max(1, 48 - suffixText.count)
                candidate = String(base.prefix(prefixLength)) + suffixText
                suffix += 1
            }
            normalized.name = candidate
            usedNames.insert(candidate.lowercased())
            result.append(normalized)
        }
        return result.isEmpty ? [defaultProfile(knownTerminalIDs: knownTerminalIDs)] : result
    }

    private static func normalizedLayoutShortcuts(_ bindings: [LayoutShortcutBinding]) -> [LayoutShortcutBinding] {
        var result: [LayoutShortcutBinding] = []
        var modes = Set<LayoutMode>()
        var shortcuts = Set<GlobalShortcut>()
        for binding in bindings {
            guard validShortcut(binding.shortcut), !modes.contains(binding.mode), !shortcuts.contains(binding.shortcut) else { continue }
            modes.insert(binding.mode)
            shortcuts.insert(binding.shortcut)
            result.append(binding)
        }
        return result
    }

    private static func validShortcut(_ shortcut: GlobalShortcut) -> Bool {
        let supported = ShortcutModifiers.control.rawValue
            | ShortcutModifiers.option.rawValue
            | ShortcutModifiers.shift.rawValue
            | ShortcutModifiers.command.rawValue
        return shortcut.keyCode <= 127
            && shortcut.modifiers.rawValue != 0
            && shortcut.modifiers.rawValue & ~supported == 0
    }

    private static func load(from defaults: UserDefaults, knownTerminalIDs: Set<String>) -> LoadedPayload? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        guard let payload = try? PropertyListDecoder().decode(StoredPayload.self, from: data) else {
            return LoadedPayload(profiles: [], activeProfileID: nil, layoutShortcuts: [], needsRepair: true, isUnsupportedVersion: false)
        }
        guard payload.version == schemaVersion else {
            return LoadedPayload(profiles: [], activeProfileID: nil, layoutShortcuts: [], needsRepair: false, isUnsupportedVersion: true)
        }

        let profiles = payload.profiles.map(\.profile)
        let normalizedProfiles = normalizedProfiles(profiles, knownTerminalIDs: knownTerminalIDs)
        let normalizedShortcuts = normalizedLayoutShortcuts(payload.layoutShortcuts)
        let validActive = payload.activeProfileID.flatMap { id in
            normalizedProfiles.contains(where: { $0.id == id }) ? id : nil
        }
        let needsRepair = normalizedProfiles != profiles
            || normalizedShortcuts != payload.layoutShortcuts
            || validActive != payload.activeProfileID
        return LoadedPayload(
            profiles: normalizedProfiles,
            activeProfileID: validActive,
            layoutShortcuts: normalizedShortcuts,
            needsRepair: needsRepair,
            isUnsupportedVersion: false
        )
    }
}

private struct LoadedPayload {
    let profiles: [ArrangementProfile]
    let activeProfileID: UUID?
    let layoutShortcuts: [LayoutShortcutBinding]
    let needsRepair: Bool
    let isUnsupportedVersion: Bool
}

private struct StoredPayload: Codable {
    let version: Int
    let activeProfileID: UUID?
    let profiles: [StoredProfile]
    let layoutShortcuts: [LayoutShortcutBinding]
}

private struct StoredProfile: Codable {
    let id: UUID
    let name: String
    let layoutMode: LayoutMode
    let gap: Double
    let includedTerminalIDs: [String]
    let focusTargetMode: FocusTargetMode
    let customization: LayoutCustomization
    let displayBinding: DisplayBinding?
    let shortcut: GlobalShortcut?

    init(_ profile: ArrangementProfile) {
        id = profile.id
        name = profile.name
        layoutMode = profile.layoutMode
        gap = profile.gap
        includedTerminalIDs = profile.includedTerminalIDs.sorted()
        focusTargetMode = profile.focusTargetMode
        customization = profile.customization
        displayBinding = profile.displayBinding
        shortcut = profile.shortcut
    }

    var profile: ArrangementProfile {
        ArrangementProfile(
            id: id,
            name: name,
            layoutMode: layoutMode,
            gap: gap,
            includedTerminalIDs: Set(includedTerminalIDs),
            focusTargetMode: focusTargetMode,
            customization: customization,
            displayBinding: displayBinding,
            shortcut: shortcut
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? container.decode(String.self, forKey: .name)) ?? "Profile"
        layoutMode = (try? container.decode(LayoutMode.self, forKey: .layoutMode)) ?? .row
        gap = (try? container.decode(Double.self, forKey: .gap)) ?? PreferenceConstraints.defaultGap
        includedTerminalIDs = (try? container.decode([String].self, forKey: .includedTerminalIDs)) ?? TerminalCatalog.defaultIncludedIDs.sorted()
        focusTargetMode = (try? container.decode(FocusTargetMode.self, forKey: .focusTargetMode)) ?? .activeWindow
        customization = (try? container.decode(LayoutCustomization.self, forKey: .customization)) ?? .default
        displayBinding = try? container.decodeIfPresent(DisplayBinding.self, forKey: .displayBinding)
        shortcut = try? container.decodeIfPresent(GlobalShortcut.self, forKey: .shortcut)
    }
}
