import AppKit
import Combine
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var model: SettingsViewModel
    @ObservedObject private var preferences: PreferencesStore

    init(model: SettingsViewModel) {
        self.model = model
        preferences = model.preferences
    }

    var body: some View {
        Form {
            if let editor = model.profileEditor {
                ProfileSettingsSections(editor: editor, model: model)
            } else {
                legacyLayoutSection
                includedTerminalsSection
            }

            Section("Default Shortcut") {
                HStack {
                    ShortcutRecorderView(shortcut: $model.shortcutDraft) { value in
                        model.commitShortcut(value)
                    }
                    Spacer()
                    Text(ShortcutDisplayFormatter.string(for: model.shortcutDraft))
                        .foregroundStyle(.secondary)
                }
                Text("Fallback shortcut for the active profile.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let error = model.shortcutError {
                    errorText(error, prefix: "Shortcut error")
                }
            }

            Section("General") {
                Toggle("Launch at Login", isOn: launchAtLoginBinding)
                if model.launchAtLoginStatus == .requiresApproval {
                    Text("Approval is required in System Settings → Login Items.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Open Login Items Settings") { model.openLoginItemsSettings() }
                }
                if let error = model.launchAtLoginError {
                    errorText(error, prefix: "Launch at login error")
                }
            }

            Section("Accessibility") {
                Text(permissionDescription).foregroundStyle(.secondary)
                if model.permissionState != .granted {
                    Button("Request Access") { model.requestPermission() }
                    Button("Open System Settings") { model.openAccessibilitySettings() }
                }
            }

            Section("Diagnostics") {
                if let diagnostics = model.diagnosticsSnapshot {
                    LabeledContent("Accessibility", value: diagnostics.permission.rawValue)
                    LabeledContent("Launch at Login", value: diagnostics.launchAtLogin.rawValue)
                    LabeledContent("Global shortcut", value: diagnostics.shortcutRegistered ? "Registered" : "Not registered")
                    LabeledContent("Profiles", value: "\(diagnostics.profiles.count)")
                    LabeledContent("Last detected windows", value: "\(diagnostics.totalWindowCount)")
                } else {
                    Text("Diagnostics are unavailable.").foregroundStyle(.secondary)
                }
                Text("Only aggregate local status is shown; window titles and terminal content are never collected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .frame(minHeight: 680)
        .padding()
        .navigationTitle("Schiera Settings")
        .onAppear { model.refreshPermission() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshPermission()
        }
    }

    private var legacyLayoutSection: some View {
        Section("Layout") {
            Picker("Default arrangement", selection: $preferences.layoutMode) {
                ForEach(LayoutMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.symbolName).tag(mode)
                }
            }
            Stepper(value: gapBinding, in: 0...64, step: 1) {
                LabeledContent("Gap", value: "\(Int(preferences.gap)) pt")
            }
        }
    }

    private var includedTerminalsSection: some View {
        Section("Included Terminals") {
            ForEach(TerminalCatalog.applications) { application in
                Toggle(application.displayName, isOn: Binding(
                    get: { preferences.includedTerminalIDs.contains(application.id) },
                    set: { enabled in
                        if enabled { preferences.includedTerminalIDs.insert(application.id) }
                        else { preferences.includedTerminalIDs.remove(application.id) }
                    }
                ))
            }
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { model.launchAtLoginStatus == .enabled || model.launchAtLoginStatus == .requiresApproval },
            set: { model.setLaunchAtLoginEnabled($0) }
        )
    }

    private var permissionDescription: String {
        switch model.permissionState {
        case .granted: return "Accessibility access is granted."
        case .notDetermined: return "Accessibility access is required to arrange terminal windows."
        case .denied: return "Accessibility access was denied. Enable Schiera in System Settings to arrange windows."
        }
    }

    private var gapBinding: Binding<Double> {
        Binding(get: { preferences.gap }, set: { preferences.gap = $0 })
    }

    private func errorText(_ error: String, prefix: String) -> some View {
        Text(error)
            .foregroundStyle(.red)
            .font(.callout)
            .accessibilityLabel("\(prefix): \(error)")
    }
}

private struct ProfileSettingsSections: View {
    @ObservedObject var editor: ProfileEditorState
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        Group {
            profileSection
            arrangementSection
            displaySection
            terminalsSection
            profileShortcutSection
            layoutShortcutsSection
        }
    }

    private var profileSection: some View {
        Section("Profile") {
            Picker("Active profile", selection: profileSelection) {
                ForEach(editor.profiles) { profile in Text(profile.name).tag(profile.id) }
            }
            TextField("Name", text: profileName)
            HStack {
                Button("Add") { _ = editor.addProfile(named: "Profile"); changed() }
                Button("Duplicate") { _ = editor.duplicateProfile(); changed() }
                Button("Delete", role: .destructive) {
                    _ = editor.deleteProfile(editor.activeProfileID)
                    changed()
                }
                .disabled(editor.profiles.count <= 1)
            }
            if let error = editor.errorMessage {
                Text(error).foregroundStyle(.red).font(.callout)
            }
        }
    }

    private var arrangementSection: some View {
        Section("Arrangement") {
            Picker("Mode", selection: layoutMode) {
                ForEach(LayoutMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.symbolName).tag(mode)
                }
            }
            Text(editor.draft.layoutMode.detail).font(.callout).foregroundStyle(.secondary)

            Stepper(value: gap, in: 0...64, step: 1) {
                LabeledContent("Gap", value: "\(Int(editor.draft.gap)) pt")
            }

            if editor.draft.layoutMode == .wrappedRows || editor.draft.layoutMode == .smart {
                Picker("Rows", selection: wrappedRows) {
                    ForEach(WrappedRowCount.allCases) { row in Text(row.displayName).tag(row) }
                }
            }

            if editor.draft.layoutMode == .focus {
                Picker("Focus target", selection: focusTarget) {
                    ForEach(FocusTargetMode.allCases) { target in Text(target.displayName).tag(target) }
                }
                Picker("Focus side", selection: focusSide) {
                    ForEach(FocusSide.allCases) { side in Text(side.displayName).tag(side) }
                }
                HStack {
                    Text("Focus width")
                    Slider(value: focusFraction, in: 0.50...0.75, step: 0.05)
                    Text("\(Int(editor.draft.customization.focusFraction * 100))%")
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                }
            }

            Stepper(value: edgeMargin, in: 0...64, step: 1) {
                LabeledContent("Screen margin", value: "\(Int(editor.draft.customization.edgeMargin)) pt")
            }
        }
    }

    private var displaySection: some View {
        Section("Target Display") {
            Text(editor.draft.displayBinding == nil ? "Follow the pointer at invocation." : "Bound to the selected display; falls back to the pointer if disconnected.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Bind to Display Under Pointer") { model.bindActiveProfileToPointerDisplay() }
                if editor.draft.displayBinding != nil {
                    Button("Follow Pointer") { model.clearActiveProfileDisplayBinding() }
                }
            }
        }
    }

    private var terminalsSection: some View {
        Section("Included Terminals") {
            ForEach(TerminalCatalog.applications) { application in
                Toggle(application.displayName, isOn: Binding(
                    get: { editor.draft.includedTerminalIDs.contains(application.id) },
                    set: { editor.setTerminal(application.id, included: $0); changed() }
                ))
            }
        }
    }

    private var profileShortcutSection: some View {
        Section("Profile Shortcut") {
            HStack {
                ShortcutRecorderView(shortcut: profileShortcut) { value in
                    editor.setShortcut(value)
                    changed()
                }
                Spacer()
                if let value = editor.draft.shortcut {
                    Text(ShortcutDisplayFormatter.string(for: value)).foregroundStyle(.secondary)
                    Button("Clear") { editor.setShortcut(nil); changed() }
                } else {
                    Text("Not assigned").foregroundStyle(.secondary)
                }
            }
        }
    }

    private var layoutShortcutsSection: some View {
        Section("Layout Shortcuts") {
            ForEach(LayoutMode.allCases) { mode in
                layoutShortcutRow(for: mode)
            }
        }
    }

    private func layoutShortcutRow(for mode: LayoutMode) -> some View {
        HStack {
            Label(mode.displayName, systemImage: mode.symbolName)
                .frame(width: 130, alignment: .leading)
            ShortcutRecorderView(shortcut: layoutShortcut(for: mode)) { value in
                editor.setLayoutShortcut(value, for: mode)
                changed()
            }
            if editor.layoutShortcuts.contains(where: { $0.mode == mode }) {
                Button("Clear") {
                    editor.setLayoutShortcut(nil, for: mode)
                    changed()
                }
            }
        }
    }

    private var profileSelection: Binding<UUID> {
        Binding(
            get: { editor.selectedProfileID },
            set: { editor.selectProfile($0); changed() }
        )
    }

    private var profileName: Binding<String> {
        Binding(
            get: { editor.draft.name },
            set: { _ = editor.renameProfile(editor.activeProfileID, to: $0); changed() }
        )
    }

    private var layoutMode: Binding<LayoutMode> {
        Binding(get: { editor.draft.layoutMode }, set: { editor.setLayoutMode($0); changed() })
    }

    private var gap: Binding<Double> {
        Binding(get: { editor.draft.gap }, set: { editor.setGap($0); changed() })
    }

    private var focusTarget: Binding<FocusTargetMode> {
        Binding(get: { editor.draft.focusTargetMode }, set: { editor.setFocusTargetMode($0); changed() })
    }

    private var wrappedRows: Binding<WrappedRowCount> {
        customizationBinding(\.wrappedRows)
    }

    private var focusSide: Binding<FocusSide> {
        customizationBinding(\.focusSide)
    }

    private var focusFraction: Binding<Double> {
        customizationBinding(\.focusFraction)
    }

    private var edgeMargin: Binding<Double> {
        customizationBinding(\.edgeMargin)
    }

    private var profileShortcut: Binding<GlobalShortcut> {
        Binding(
            get: { editor.draft.shortcut ?? GlobalShortcut(keyCode: 17, modifiers: [.control, .option, .command]) },
            set: { editor.setShortcut($0); changed() }
        )
    }

    private func layoutShortcut(for mode: LayoutMode) -> Binding<GlobalShortcut> {
        Binding(
            get: {
                editor.layoutShortcuts.first(where: { $0.mode == mode })?.shortcut
                    ?? suggestedShortcut(for: mode)
            },
            set: { editor.setLayoutShortcut($0, for: mode); changed() }
        )
    }

    private func suggestedShortcut(for mode: LayoutMode) -> GlobalShortcut {
        let keyCode: UInt32
        switch mode {
        case .smart: keyCode = 1
        case .row: keyCode = 15
        case .wrappedRows: keyCode = 13
        case .balancedGrid: keyCode = 5
        case .focus: keyCode = 3
        }
        return GlobalShortcut(keyCode: keyCode, modifiers: [.control, .option, .shift, .command])
    }

    private func customizationBinding<Value>(_ keyPath: WritableKeyPath<LayoutCustomization, Value>) -> Binding<Value> {
        Binding(
            get: { editor.draft.customization[keyPath: keyPath] },
            set: { value in
                var customization = editor.draft.customization
                customization[keyPath: keyPath] = value
                editor.setCustomization(customization)
                changed()
            }
        )
    }

    private func changed() { model.profileDidChange() }
}
