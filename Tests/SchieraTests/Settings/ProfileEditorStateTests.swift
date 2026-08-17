import XCTest
@testable import Schiera

@MainActor
final class ProfileEditorStateTests: XCTestCase {
    func testSelectionAndEditsUpsertTheActiveProfile() {
        let store = ProfileEditorStoreFake()
        let state = ProfileEditorState(profileStore: store)

        let second = profile(name: "Second")
        store.upsert(second)
        state.selectProfile(second.id)
        state.setGap(29)
        state.setLayoutMode(.focus)
        state.setTerminal("terminal", included: false)
        state.setFocusTargetMode(.windowUnderPointer)

        XCTAssertEqual(state.activeProfileID, second.id)
        XCTAssertEqual(state.draft.gap, 29)
        XCTAssertEqual(state.draft.layoutMode, .focus)
        XCTAssertFalse(state.draft.includedTerminalIDs.contains("terminal"))
        XCTAssertEqual(state.draft.focusTargetMode, .windowUnderPointer)
        XCTAssertGreaterThanOrEqual(store.upsertCount, 4)
    }

    func testTerminalSelectionMayBeEmptyAndCustomizationAndDisplayPersist() {
        let store = ProfileEditorStoreFake()
        let state = ProfileEditorState(profileStore: store)
        let binding = DisplayBinding(uuid: "display", fallbackDisplayID: 42)
        var customization = LayoutCustomization.default
        customization.focusFraction = 0.70

        state.setIncludedTerminalIDs([])
        state.setCustomization(customization)
        state.setDisplayBinding(binding)

        XCTAssertTrue(state.draft.includedTerminalIDs.isEmpty)
        XCTAssertEqual(state.draft.customization.focusFraction, 0.70)
        XCTAssertEqual(state.draft.displayBinding, binding)
    }

    func testProfileCRUDSelectsNewProfilesAndProtectsLastProfile() {
        let store = ProfileEditorStoreFake()
        let state = ProfileEditorState(profileStore: store)

        let added = state.addProfile(named: "Work")
        XCTAssertEqual(state.draft.name, "Work")
        XCTAssertEqual(state.activeProfileID, added.id)

        let duplicate = state.duplicateProfile(id: added.id)
        XCTAssertEqual(duplicate?.name, "Work Copy")
        XCTAssertEqual(state.renameProfile(added.id, to: "Renamed"), true)
        XCTAssertEqual(store.profiles.first(where: { $0.id == added.id })?.name, "Renamed")

        XCTAssertTrue(state.deleteProfile(added.id))
        XCTAssertTrue(state.deleteProfile(store.activeProfileID))
        XCTAssertEqual(state.deleteProfile(store.activeProfileID), false)
        XCTAssertEqual(state.errorMessage, "At least one profile is required.")
    }

    func testLayoutShortcutsCanBeUpsertedOrRemoved() {
        let store = ProfileEditorStoreFake()
        let state = ProfileEditorState(profileStore: store)
        let shortcut = GlobalShortcut(keyCode: 1, modifiers: .control)

        state.setLayoutShortcut(shortcut, for: .focus)
        XCTAssertEqual(state.layoutShortcuts, [LayoutShortcutBinding(mode: .focus, shortcut: shortcut)])

        state.setLayoutShortcut(nil, for: .focus)
        XCTAssertTrue(state.layoutShortcuts.isEmpty)
    }

    private func profile(name: String) -> ArrangementProfile {
        ArrangementProfile(
            id: UUID(), name: name, layoutMode: .smart,
            gap: PreferenceConstraints.defaultGap,
            includedTerminalIDs: TerminalCatalog.defaultIncludedIDs,
            focusTargetMode: .activeWindow,
            customization: .default, displayBinding: nil, shortcut: nil
        )
    }
}

@MainActor
private final class ProfileEditorStoreFake: ProfileProviding {
    var profiles: [ArrangementProfile]
    var activeProfileID: UUID
    var layoutShortcuts: [LayoutShortcutBinding] = []
    var upsertCount = 0

    init() {
        let initial = ArrangementProfile(
            id: UUID(), name: "Default", layoutMode: .smart,
            gap: PreferenceConstraints.defaultGap,
            includedTerminalIDs: TerminalCatalog.defaultIncludedIDs,
            focusTargetMode: .activeWindow,
            customization: .default, displayBinding: nil, shortcut: nil
        )
        profiles = [initial]
        activeProfileID = initial.id
    }

    var activeProfile: ArrangementProfile {
        profiles.first(where: { $0.id == activeProfileID }) ?? profiles[0]
    }

    func upsert(_ profile: ArrangementProfile) {
        upsertCount += 1
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
    }

    func deleteProfile(id: UUID) {
        profiles.removeAll { $0.id == id }
        if !profiles.contains(where: { $0.id == activeProfileID }), let first = profiles.first {
            activeProfileID = first.id
        }
    }
}
