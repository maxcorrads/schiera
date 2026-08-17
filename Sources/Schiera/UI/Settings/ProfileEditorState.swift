import Foundation
import SwiftUI

/// The profile store is supplied by the preferences layer.  Keeping this
/// adapter separate from the view makes profile selection and edits
/// transactional from the settings UI's point of view: every edit is sent to
/// the store through `upsert` before the published draft is refreshed.
@MainActor
final class ProfileEditorState: ObservableObject {
    let profileStore: any ProfileProviding

    @Published private(set) var selectedProfileID: UUID
    @Published private(set) var draft: ArrangementProfile
    @Published private(set) var errorMessage: String?

    init(profileStore: any ProfileProviding) {
        self.profileStore = profileStore
        self.selectedProfileID = profileStore.activeProfileID
        self.draft = profileStore.activeProfile
    }

    var profiles: [ArrangementProfile] { profileStore.profiles }

    var activeProfileID: UUID { selectedProfileID }
    var activeProfile: ArrangementProfile { draft }
    var layoutShortcuts: [LayoutShortcutBinding] { profileStore.layoutShortcuts }

    func refresh() {
        errorMessage = nil
        reload()
    }

    func selectProfile(_ id: UUID) {
        guard profileStore.profiles.contains(where: { $0.id == id }) else {
            errorMessage = "The selected profile is no longer available."
            reload()
            return
        }
        profileStore.activeProfileID = id
        errorMessage = nil
        reload()
    }

    func selectProfile(id: UUID) { selectProfile(id) }

    @discardableResult
    func addProfile(named name: String = "Profile") -> ArrangementProfile {
        let profile = ArrangementProfile(
            id: UUID(),
            name: name,
            layoutMode: .smart,
            gap: PreferenceConstraints.defaultGap,
            includedTerminalIDs: TerminalCatalog.defaultIncludedIDs,
            focusTargetMode: .activeWindow,
            customization: .default,
            displayBinding: nil,
            shortcut: nil
        ).normalized(knownTerminalIDs: Self.knownTerminalIDs)
        profileStore.upsert(profile)
        profileStore.activeProfileID = profile.id
        errorMessage = nil
        reload()
        return draft
    }

    @discardableResult
    func addProfile(name: String = "Profile") -> ArrangementProfile {
        addProfile(named: name)
    }

    @discardableResult
    func duplicateProfile() -> ArrangementProfile? {
        duplicateProfile(id: selectedProfileID)
    }

    @discardableResult
    func duplicateProfile(id: UUID) -> ArrangementProfile? {
        guard let source = profileStore.profiles.first(where: { $0.id == id }) else {
            errorMessage = "The profile could not be duplicated."
            return nil
        }
        let copy = ArrangementProfile(
            id: UUID(),
            name: "\(source.name) Copy",
            layoutMode: source.layoutMode,
            gap: source.gap,
            includedTerminalIDs: source.includedTerminalIDs,
            focusTargetMode: source.focusTargetMode,
            customization: source.customization,
            displayBinding: source.displayBinding,
            shortcut: source.shortcut
        ).normalized(knownTerminalIDs: Self.knownTerminalIDs)
        profileStore.upsert(copy)
        profileStore.activeProfileID = copy.id
        errorMessage = nil
        reload()
        return draft
    }

    @discardableResult
    func duplicateProfile(_ id: UUID) -> ArrangementProfile? {
        duplicateProfile(id: id)
    }

    @discardableResult
    func renameProfile(_ id: UUID, to name: String) -> Bool {
        guard var profile = profileStore.profiles.first(where: { $0.id == id }) else {
            errorMessage = "The profile could not be renamed."
            return false
        }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Profile names cannot be empty."
            return false
        }
        profile.name = name
        profile = profile.normalized(knownTerminalIDs: Self.knownTerminalIDs)
        profileStore.upsert(profile)
        errorMessage = nil
        reload()
        return true
    }

    @discardableResult
    func renameProfile(id: UUID, name: String) -> Bool {
        renameProfile(id, to: name)
    }

    @discardableResult
    func deleteProfile(_ id: UUID) -> Bool {
        guard profileStore.profiles.count > 1 else {
            errorMessage = "At least one profile is required."
            return false
        }
        guard profileStore.profiles.contains(where: { $0.id == id }) else {
            errorMessage = "The profile could not be deleted."
            return false
        }
        let replacement = profileStore.profiles.first(where: { $0.id != id })
        profileStore.deleteProfile(id: id)
        if profileStore.activeProfileID == id, let replacement {
            profileStore.activeProfileID = replacement.id
        }
        errorMessage = nil
        reload()
        return true
    }

    @discardableResult
    func deleteProfile(id: UUID) -> Bool {
        deleteProfile(id)
    }

    func setLayoutMode(_ mode: LayoutMode) {
        mutate { $0.layoutMode = mode }
    }

    func setGap(_ gap: Double) {
        mutate { $0.gap = gap }
    }

    func setIncludedTerminalIDs(_ ids: Set<String>) {
        mutate { $0.includedTerminalIDs = ids }
    }

    func setTerminal(_ id: String, included: Bool) {
        mutate {
            if included { $0.includedTerminalIDs.insert(id) }
            else { $0.includedTerminalIDs.remove(id) }
        }
    }

    func setTerminalIncluded(_ id: String, _ included: Bool) {
        setTerminal(id, included: included)
    }

    func setFocusTargetMode(_ mode: FocusTargetMode) {
        mutate { $0.focusTargetMode = mode }
    }

    func setCustomization(_ customization: LayoutCustomization) {
        mutate { $0.customization = customization }
    }

    func setDisplayBinding(_ binding: DisplayBinding?) {
        mutate { $0.displayBinding = binding }
    }

    func setShortcut(_ shortcut: GlobalShortcut?) {
        mutate { $0.shortcut = shortcut }
    }

    func setLayoutShortcut(_ shortcut: GlobalShortcut?, for mode: LayoutMode) {
        var bindings = profileStore.layoutShortcuts
        if let index = bindings.firstIndex(where: { $0.mode == mode }) {
            if let shortcut {
                bindings[index].shortcut = shortcut
            } else {
                bindings.remove(at: index)
            }
        } else if let shortcut {
            bindings.append(LayoutShortcutBinding(mode: mode, shortcut: shortcut))
        }
        profileStore.layoutShortcuts = bindings
        errorMessage = nil
        objectWillChange.send()
    }

    private func mutate(_ body: (inout ArrangementProfile) -> Void) {
        var updated = draft
        body(&updated)
        updated = updated.normalized(knownTerminalIDs: Self.knownTerminalIDs)
        profileStore.upsert(updated)
        errorMessage = nil
        reload(fallback: updated)
    }

    private func reload(fallback: ArrangementProfile? = nil) {
        selectedProfileID = profileStore.activeProfileID
        draft = profileStore.profiles.first(where: { $0.id == selectedProfileID })
            ?? fallback
            ?? profileStore.activeProfile
    }

    private static let knownTerminalIDs = Set(TerminalCatalog.applications.map(\.id))
}
