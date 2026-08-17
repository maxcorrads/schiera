import Foundation

/// Builds the ephemeral choices shown by the menu bar without copying
/// Accessibility titles or other window metadata into user-facing labels.
enum FocusWindowChoiceBuilder {
    static func build(
        from windows: [WindowDescriptor],
        catalog: [TerminalApplicationDefinition] = TerminalCatalog.applications
    ) -> [FocusWindowChoice] {
        var ordinalsByApplication: [String: Int] = [:]

        return windows.map { window in
            let applicationName = displayName(
                for: window.bundleIdentifier,
                in: catalog
            )
            let ordinal = ordinalsByApplication[applicationName, default: 0] + 1
            ordinalsByApplication[applicationName] = ordinal

            return FocusWindowChoice(
                id: window.id,
                label: "\(applicationName) \(ordinal)"
            )
        }
    }

    private static func displayName(
        for bundleIdentifier: String,
        in catalog: [TerminalApplicationDefinition]
    ) -> String {
        catalog.first(where: { $0.bundleIdentifiers.contains(bundleIdentifier) })?.displayName
            ?? "Terminal"
    }
}

struct MenuProfileChoice: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let isActive: Bool

    var label: String { name }

    init(id: UUID, name: String, isActive: Bool = false) {
        self.id = id
        self.name = name
        self.isActive = isActive
    }

    init(profile: ArrangementProfile, isActive: Bool = false) {
        self.init(id: profile.id, name: profile.name, isActive: isActive)
    }
}

enum MenuProfileChoiceBuilder {
    static func build(
        from profiles: [ArrangementProfile],
        activeProfileID: UUID?
    ) -> [MenuProfileChoice] {
        profiles
            .map { MenuProfileChoice(profile: $0, isActive: $0.id == activeProfileID) }
            .sorted(by: orderedBefore)
    }

    static func ordered(_ choices: [MenuProfileChoice]) -> [MenuProfileChoice] {
        choices.sorted(by: orderedBefore)
    }

    private static func orderedBefore(
        _ lhs: MenuProfileChoice,
        _ rhs: MenuProfileChoice
    ) -> Bool {
        if lhs.isActive != rhs.isActive {
            return lhs.isActive && !rhs.isActive
        }

        let lhsName = lhs.name.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let rhsName = rhs.name.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        if lhsName != rhsName {
            return lhsName < rhsName
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

enum SmartLayoutDecisionFormatter {
    static func string(for decision: SmartLayoutDecision) -> String {
        switch (decision.mode, decision.rows) {
        case (.wrappedRows, .two):
            return "Wrapped Rows (2 rows)"
        case (.wrappedRows, .three):
            return "Wrapped Rows (3 rows)"
        case (.wrappedRows, .automatic):
            return "Wrapped Rows"
        default:
            return decision.mode.displayName
        }
    }
}

extension SmartLayoutDecision {
    var menuDescription: String {
        SmartLayoutDecisionFormatter.string(for: self)
    }
}
