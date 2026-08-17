import AppKit
import Combine
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(arrangeTitle) { model.arrange() }

            if !model.profileChoices.isEmpty {
                Menu("Profiles") {
                    ForEach(model.profileChoices) { profile in
                        Button { model.arrange(profileID: profile.id) } label: {
                            Label(
                                profile.label,
                                systemImage: profile.isActive ? "checkmark.circle.fill" : "circle"
                            )
                        }
                    }
                    Divider()
                    SettingsLink { Text("Manage Profiles…") }
                }
            }

            Menu("Arrange As…") {
                ForEach(LayoutMode.allCases) { mode in
                    Button { model.arrange(using: mode) } label: {
                        Label(mode.displayName, systemImage: mode.symbolName)
                    }
                }
            }

            Menu("Focus Window") {
                Button("Refresh Window List") { model.refreshWindowChoices() }
                if model.focusChoices.isEmpty {
                    Text("Refresh to choose a terminal")
                } else {
                    Divider()
                    ForEach(model.focusChoices) { choice in
                        Button(choice.label) { model.arrangeFocusedWindow(choice.id) }
                    }
                }
            }

            Menu("Arrange Selected…") {
                Button("Refresh Window List") { model.refreshWindowChoices() }
                if model.temporaryWindowChoices.isEmpty {
                    Text("Refresh to select terminals")
                } else {
                    Menu("Included Windows") {
                        ForEach(model.temporaryWindowChoices) { choice in
                            let included = !model.excludedTemporaryWindowIDs.contains(choice.id)
                            Button { model.toggleTemporaryWindow(choice.id) } label: {
                                Label(choice.label, systemImage: included ? "checkmark" : "circle")
                            }
                        }
                    }
                    Menu("Priority / Focus") {
                        ForEach(model.temporaryWindowChoices) { choice in
                            let prioritized = model.prioritizedTemporaryWindowIDs.contains(choice.id)
                            Button { model.toggleTemporaryPriority(choice.id) } label: {
                                Label(choice.label, systemImage: prioritized ? "star.fill" : "star")
                            }
                        }
                    }
                    Divider()
                    Button("Arrange Selection") { model.arrangeTemporary() }
                    Button("Arrange Selection as Focus") { model.arrangeTemporary(using: .focus) }
                    Button("Clear Selection") { model.clearWindowChoices() }
                }
            }

            Button("Undo Last Arrangement") { model.restore() }
                .disabled(!model.canRestore)

            Divider()
            SettingsLink { Text("Settings…") }
            permissionSection
            Label(model.feedback.message, systemImage: model.feedback.symbolName)
                .accessibilityLabel(model.feedback.message)
            Divider()
            Button("Quit") { model.quit() }
        }
        .padding(10)
        .frame(minWidth: 280)
        .onAppear { model.refreshMenuState() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshMenuState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
            model.refreshMenuState()
        }
    }

    private var arrangeTitle: String {
        if let name = model.activeProfileName { return "Arrange — \(name)" }
        return "Arrange Terminals"
    }

    @ViewBuilder private var permissionSection: some View {
        switch model.permissionState {
        case .granted:
            Label("Accessibility: Allowed", systemImage: "checkmark.circle")
        case .notDetermined, .denied:
            VStack(alignment: .leading, spacing: 4) {
                Label("Accessibility: Required", systemImage: "exclamationmark.triangle")
                Button("Request Permission") { model.requestAccessibilityPermission() }
                Button("Open Accessibility Settings") { model.openAccessibilitySettings() }
            }
        }
    }
}
