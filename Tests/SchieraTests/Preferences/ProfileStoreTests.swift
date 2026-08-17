import Foundation
import XCTest
@testable import Schiera

@MainActor
final class ProfileStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "ProfileStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeSeed(
        id: UUID = UUID(),
        name: String = "Seed",
        mode: LayoutMode = .focus
    ) -> ArrangementProfile {
        ArrangementProfile(
            id: id,
            name: name,
            layoutMode: mode,
            gap: 14,
            includedTerminalIDs: ["terminal", "unknown"],
            focusTargetMode: .windowUnderPointer,
            customization: LayoutCustomization(
                wrappedRows: .three,
                focusFraction: 0.7,
                focusSide: .trailing,
                edgeMargin: 20
            ),
            displayBinding: DisplayBinding(uuid: "display-a", fallbackDisplayID: 42),
            shortcut: GlobalShortcut(keyCode: 12, modifiers: [.shift, .command])
        )
    }

    func testFreshStoreUsesNormalizedSeedAndPersistsIt() {
        let defaults = makeDefaults()
        let seed = makeSeed(name: "  Seed  ")
        let store = ProfileStore(defaults: defaults, seed: seed)

        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertEqual(store.activeProfileID, seed.id)
        XCTAssertEqual(store.activeProfile.name, "Seed")
        XCTAssertEqual(store.activeProfile.includedTerminalIDs, ["terminal"])
        XCTAssertNotNil(defaults.data(forKey: ProfileStore.storageKey))

        let reloaded = ProfileStore(defaults: defaults)
        XCTAssertEqual(reloaded.profiles, store.profiles)
        XCTAssertEqual(reloaded.activeProfileID, seed.id)
    }

    func testDefaultStoreAlwaysHasOneProfileAndSafeDefaults() {
        let store = ProfileStore(defaults: makeDefaults())
        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertEqual(store.activeProfile.name, "Default")
        XCTAssertEqual(store.activeProfile.layoutMode, .row)
        XCTAssertEqual(store.activeProfile.gap, PreferenceConstraints.defaultGap)
        XCTAssertEqual(store.activeProfile.includedTerminalIDs, TerminalCatalog.defaultIncludedIDs)
        XCTAssertEqual(store.activeProfile.customization, .default)
        XCTAssertNil(store.activeProfile.shortcut)
    }

    func testCreateDuplicateRenameAndDeleteKeepNamesUsefulAndUnique() {
        let store = ProfileStore(defaults: makeDefaults(), seed: makeSeed(name: "Work"))
        let second = store.create(name: " work ")
        XCTAssertEqual(second.name, "work 2")

        let duplicate = store.duplicate(id: second.id)
        XCTAssertEqual(duplicate?.name, "work 3")
        XCTAssertTrue(store.rename(id: second.id, to: "Work"))
        XCTAssertEqual(store.profiles.first(where: { $0.id == second.id })?.name, "Work 2")
        XCTAssertFalse(store.rename(id: UUID(), to: "Missing"))

        XCTAssertTrue(store.delete(id: second.id))
        XCTAssertTrue(store.delete(id: store.profiles[0].id))
        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertFalse(store.delete(id: store.profiles[0].id))
    }

    func testUpsertNormalizesAndPreservesActiveProfile() {
        let defaults = makeDefaults()
        let store = ProfileStore(defaults: defaults)
        let id = store.activeProfileID
        let invalid = ArrangementProfile(
            id: id,
            name: "   ",
            layoutMode: .row,
            gap: .infinity,
            includedTerminalIDs: ["unknown"],
            focusTargetMode: .activeWindow,
            customization: LayoutCustomization(
                wrappedRows: .automatic,
                focusFraction: .nan,
                focusSide: .leading,
                edgeMargin: .infinity
            ),
            displayBinding: nil,
            shortcut: GlobalShortcut(keyCode: 255, modifiers: [])
        )

        store.upsert(invalid)
        XCTAssertEqual(store.activeProfileID, id)
        XCTAssertEqual(store.activeProfile.name, "Profile")
        XCTAssertEqual(store.activeProfile.gap, PreferenceConstraints.defaultGap)
        XCTAssertEqual(store.activeProfile.includedTerminalIDs, [])
        XCTAssertEqual(store.activeProfile.customization, .default)
        XCTAssertNil(store.activeProfile.shortcut)
    }

    func testLayoutShortcutsRejectInvalidAndDuplicateModesOrKeys() {
        let store = ProfileStore(defaults: makeDefaults())
        let first = GlobalShortcut(keyCode: 1, modifiers: [.command])
        let second = GlobalShortcut(keyCode: 2, modifiers: [.command])
        store.layoutShortcuts = [
            LayoutShortcutBinding(mode: .row, shortcut: first),
            LayoutShortcutBinding(mode: .row, shortcut: second),
            LayoutShortcutBinding(mode: .focus, shortcut: first),
            LayoutShortcutBinding(mode: .smart, shortcut: GlobalShortcut(keyCode: 200, modifiers: [.command]))
        ]
        XCTAssertEqual(store.layoutShortcuts, [LayoutShortcutBinding(mode: .row, shortcut: first)])

        store.upsertLayoutShortcut(LayoutShortcutBinding(mode: .focus, shortcut: second))
        XCTAssertEqual(store.layoutShortcuts.count, 2)
        store.removeLayoutShortcut(for: .row)
        XCTAssertEqual(store.layoutShortcuts, [LayoutShortcutBinding(mode: .focus, shortcut: second)])

        let reloaded = ProfileStore(defaults: UserDefaults(suiteName: "unused-\(UUID().uuidString)")!)
        XCTAssertTrue(reloaded.layoutShortcuts.isEmpty)
    }

    func testCorruptPayloadFallsBackToSeedWithoutCrashing() {
        let defaults = makeDefaults()
        defaults.set(Data([0x01, 0x02, 0x03]), forKey: ProfileStore.storageKey)
        let seed = makeSeed(name: "Safe Seed")
        let store = ProfileStore(defaults: defaults, seed: seed)

        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertEqual(store.activeProfile.name, "Safe Seed")
        XCTAssertEqual(store.activeProfileID, seed.id)
    }

    func testUnsupportedSchemaDoesNotOverwriteExistingData() throws {
        let defaults = makeDefaults()
        let original = Data("future-schema".utf8)
        let payload: [String: Any] = [
            "version": 999,
            "activeProfileID": UUID().uuidString,
            "profiles": [],
            "layoutShortcuts": []
        ]
        defaults.set(try PropertyListSerialization.data(fromPropertyList: payload, format: .binary, options: 0), forKey: ProfileStore.storageKey)
        let store = ProfileStore(defaults: defaults, seed: makeSeed())

        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertEqual(defaults.data(forKey: ProfileStore.storageKey), try PropertyListSerialization.data(fromPropertyList: payload, format: .binary, options: 0))
        XCTAssertNotEqual(defaults.data(forKey: ProfileStore.storageKey), original)
    }
}
