import XCTest
@testable import Schiera

@MainActor
final class PreferencesStoreTests: XCTestCase {
    private func makeDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testCatalogIsOrderedAndComplete() {
        XCTAssertEqual(TerminalCatalog.applications.map(\.id), ["terminal", "iterm2", "warp", "ghostty", "alacritty", "kitty", "wezterm"])
        XCTAssertEqual(TerminalCatalog.applications.map(\.displayName), ["Terminal", "iTerm2", "Warp", "Ghostty", "Alacritty", "kitty", "WezTerm"])
        XCTAssertEqual(TerminalCatalog.applications.flatMap(\.bundleIdentifiers).count, 9)
        XCTAssertEqual(TerminalCatalog.bundleIdentifiers(forIncludedIDs: TerminalCatalog.defaultIncludedIDs).count, 9)
    }

    func testFreshStoreUsesDefaultsAndEmptySelectionRoundTrips() {
        let defaults = makeDefaults()
        let store = PreferencesStore(defaults: defaults)
        XCTAssertEqual(store.gap, 8)
        XCTAssertEqual(store.includedTerminalIDs, TerminalCatalog.defaultIncludedIDs)
        XCTAssertEqual(store.shortcut, .defaultSchiera)
        XCTAssertEqual(store.layoutMode, .row)

        store.includedTerminalIDs = []
        XCTAssertEqual(PreferencesStore(defaults: defaults).includedTerminalIDs, [])
    }

    func testGapIsClampedAndNonFiniteValuesUseDefault() {
        let defaults = makeDefaults()
        let store = PreferencesStore(defaults: defaults)
        store.gap = 64
        XCTAssertEqual(PreferencesStore(defaults: defaults).gap, 64)
        store.gap = -5
        XCTAssertEqual(store.gap, 0)
        store.gap = 100
        XCTAssertEqual(store.gap, 64)
        store.gap = .infinity
        XCTAssertEqual(store.gap, 8)
    }

    func testSubsetAndUnknownIDsRoundTrip() {
        let defaults = makeDefaults()
        let store = PreferencesStore(defaults: defaults)
        store.includedTerminalIDs = ["terminal", "unknown"]
        XCTAssertEqual(PreferencesStore(defaults: defaults).includedTerminalIDs, ["terminal"])
        XCTAssertEqual(TerminalCatalog.bundleIdentifiers(forIncludedIDs: ["terminal", "unknown"]), ["com.apple.Terminal"])
    }

    func testShortcutRoundTripsAndInvalidValuesFallBackIndependently() {
        let defaults = makeDefaults()
        let store = PreferencesStore(defaults: defaults)
        store.gap = 17
        store.includedTerminalIDs = ["kitty"]
        let custom = GlobalShortcut(keyCode: 12, modifiers: [.shift, .command])
        store.shortcut = custom
        let reloaded = PreferencesStore(defaults: defaults)
        XCTAssertEqual(reloaded.shortcut, custom)
        XCTAssertEqual(reloaded.gap, 17)
        XCTAssertEqual(reloaded.includedTerminalIDs, ["kitty"])

        defaults.set(Data([0, 1, 2]), forKey: "globalShortcut")
        let corrupt = PreferencesStore(defaults: defaults)
        XCTAssertEqual(corrupt.shortcut, .defaultSchiera)
        XCTAssertEqual(corrupt.gap, 17)
        XCTAssertEqual(corrupt.includedTerminalIDs, ["kitty"])
    }

    func testLayoutModeRoundTripsAndInvalidValueFallsBackIndependently() {
        let defaults = makeDefaults()
        let store = PreferencesStore(defaults: defaults)
        store.gap = 17

        for mode in LayoutMode.allCases {
            store.layoutMode = mode
            XCTAssertEqual(PreferencesStore(defaults: defaults).layoutMode, mode)
        }

        defaults.set("future-layout", forKey: "layoutMode")
        let reloaded = PreferencesStore(defaults: defaults)
        XCTAssertEqual(reloaded.layoutMode, .row)
        XCTAssertEqual(reloaded.gap, 17)
    }

    func testResetPersistsAllDefaultsAndSuitesAreIsolated() {
        let first = makeDefaults("first-\(UUID().uuidString)")
        let second = makeDefaults("second-\(UUID().uuidString)")
        let store = PreferencesStore(defaults: first)
        store.gap = 1
        store.includedTerminalIDs = []
        store.reset()
        XCTAssertEqual(PreferencesStore(defaults: first).gap, 8)
        XCTAssertEqual(PreferencesStore(defaults: first).includedTerminalIDs, TerminalCatalog.defaultIncludedIDs)
        XCTAssertEqual(PreferencesStore(defaults: first).shortcut, .defaultSchiera)
        XCTAssertEqual(PreferencesStore(defaults: first).layoutMode, .row)
        XCTAssertEqual(PreferencesStore(defaults: second).includedTerminalIDs, TerminalCatalog.defaultIncludedIDs)
    }
}
