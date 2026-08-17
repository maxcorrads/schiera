import CoreGraphics
import XCTest
@testable import Schiera

final class MenuChoiceModelsTests: XCTestCase {
    func testFocusChoicesUseCatalogNamesAndPerApplicationOrdinals() {
        let firstTerminal = window(
            bundleIdentifier: "com.apple.Terminal",
            title: "secret-password",
            processIdentifier: 101
        )
        let secondTerminal = window(
            bundleIdentifier: "com.apple.Terminal",
            title: "another-private-title",
            processIdentifier: 202
        )
        let iTerm = window(
            bundleIdentifier: "com.googlecode.iterm2",
            title: "sensitive window title",
            processIdentifier: 303
        )

        let choices = FocusWindowChoiceBuilder.build(from: [firstTerminal, secondTerminal, iTerm])

        XCTAssertEqual(choices.map(\.label), ["Terminal 1", "Terminal 2", "iTerm2 1"])
        XCTAssertEqual(choices.map(\.id), [firstTerminal.id, secondTerminal.id, iTerm.id])
    }

    func testFocusChoiceLabelsNeverContainTitleProcessIdentifierOrUUID() {
        let identifier = WindowIdentifier(
            token: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            processIdentifier: 987_654
        )
        let descriptor = WindowDescriptor(
            id: identifier,
            bundleIdentifier: "com.apple.Terminal",
            title: "Do not show this title",
            frame: CGRect(x: 0, y: 0, width: 100, height: 100)
        )

        let label = FocusWindowChoiceBuilder.build(from: [descriptor])[0].label

        XCTAssertFalse(label.contains("Do not show this title"))
        XCTAssertFalse(label.contains("987654"))
        XCTAssertFalse(label.contains(identifier.token.uuidString))
        XCTAssertEqual(label, "Terminal 1")
    }

    func testUnknownBundleUsesGenericPrivacySafeLabel() {
        let descriptor = window(bundleIdentifier: "unknown.bundle", title: "private")

        XCTAssertEqual(FocusWindowChoiceBuilder.build(from: [descriptor])[0].label, "Terminal 1")
    }

    func testProfilesPutActiveFirstThenSortByNameAndStableID() {
        let aID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let bID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let cID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let profiles = [
            profile(id: cID, name: "zeta"),
            profile(id: aID, name: "Alpha"),
            profile(id: bID, name: "alpha")
        ]

        let choices = MenuProfileChoiceBuilder.build(from: profiles, activeProfileID: bID)

        XCTAssertEqual(choices.map(\.id), [bID, aID, cID])
        XCTAssertEqual(choices.map(\.name), ["alpha", "Alpha", "zeta"])
        XCTAssertEqual(choices.map(\.isActive), [true, false, false])
    }

    func testProfileOrderingHandlesMissingActiveProfileAndDuplicateNames() {
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000020")!
        let choices = MenuProfileChoiceBuilder.build(
            from: [profile(id: secondID, name: "Same"), profile(id: firstID, name: "Same")],
            activeProfileID: UUID()
        )

        XCTAssertEqual(choices.map(\.id), [firstID, secondID])
        XCTAssertTrue(choices.allSatisfy { !$0.isActive })
    }

    func testSmartDecisionDescriptionIsStableAndIncludesForcedRowCount() {
        XCTAssertEqual(
            SmartLayoutDecisionFormatter.string(for: SmartLayoutDecision(mode: .row, rows: .automatic)),
            "Row"
        )
        XCTAssertEqual(
            SmartLayoutDecision(mode: .wrappedRows, rows: .two).menuDescription,
            "Wrapped Rows (2 rows)"
        )
        XCTAssertEqual(
            SmartLayoutDecisionFormatter.string(for: SmartLayoutDecision(mode: .wrappedRows, rows: .three)),
            "Wrapped Rows (3 rows)"
        )
        XCTAssertEqual(
            SmartLayoutDecisionFormatter.string(for: SmartLayoutDecision(mode: .balancedGrid, rows: .automatic)),
            "Balanced Grid"
        )
    }

    private func window(
        bundleIdentifier: String,
        title: String?,
        processIdentifier: Int32 = 1
    ) -> WindowDescriptor {
        WindowDescriptor(
            id: WindowIdentifier(token: UUID(), processIdentifier: processIdentifier),
            bundleIdentifier: bundleIdentifier,
            title: title,
            frame: CGRect(x: 0, y: 0, width: 100, height: 100)
        )
    }

    private func profile(id: UUID, name: String) -> ArrangementProfile {
        ArrangementProfile(
            id: id,
            name: name,
            layoutMode: .smart,
            gap: 8,
            includedTerminalIDs: TerminalCatalog.defaultIncludedIDs,
            focusTargetMode: .activeWindow,
            customization: .default,
            displayBinding: nil,
            shortcut: nil
        )
    }
}
