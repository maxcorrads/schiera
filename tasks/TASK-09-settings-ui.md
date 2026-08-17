# TASK-09 — Settings UI and shortcut recorder

## Independent mission

Implement the native SwiftUI Settings scene content, its view model, and an AppKit-backed shortcut recorder. Bind only to frozen service interfaces.

## Read-only inputs

- `docs/PROJECT_SPEC.md`, preferences, permission, and UI sections
- `docs/CONTRACTS.md`, TASK-09 section
- `docs/FILE_OWNERSHIP.md`

## Exclusive outputs

- `Sources/Schiera/UI/Settings/**`
- `Tests/SchieraTests/Settings/**`
- `reports/TASK-09.md`

## Required implementation

1. Implement `SettingsViewModel`, `SettingsView`, and `ShortcutRecorderView` against the frozen APIs.
2. Use a compact native Settings layout with clear groups:
   - “Layout”: gap control from 0 through 64 whole points with a visible numeric value;
   - “Shortcut”: recorder, formatted current shortcut, and inline registration error;
   - “Included Terminals”: one toggle per catalog entry in catalog order;
   - “Accessibility”: current status, explanation, “Request Access”, and “Open System Settings” when not granted.
3. Persist gap and terminal toggles immediately through `PreferencesStore`.
4. Shortcut recording:
   - use `NSViewRepresentable` or a focused AppKit control to receive key-down events only while recording;
   - never install a global event monitor;
   - accept one non-modifier key plus supported modifiers and require at least one modifier;
   - Escape cancels; Delete/Backspace restores the default;
   - display the draft before commit and include VoiceOver labels/hints;
   - translate AppKit event flags to Schiera stable modifiers, masking unrelated flags.
5. Store the injected shortcut handler and use it for every registration. `commitShortcut` registers first and writes the preference only after success. On failure, restore the draft to the persisted working shortcut and publish a localized inline error.
6. Permission buttons call only `AccessibilityPermissionServicing`. Refresh state when the Settings view becomes active.
7. Keep the window sensibly sized and fully keyboard navigable. Do not introduce a main application window.

## Mandatory tests

Focus unit tests on the view model and a pure/internal event-to-shortcut translator:

- gap and terminal edits update the injected store.
- Terminal toggles can produce an intentionally empty set.
- Successful shortcut commit registers then persists.
- Failed shortcut commit does not persist and restores draft/error.
- Permission refresh/request/open actions delegate exactly once and mirror all three states.
- Event translation covers default combination, each modifier, ignored flags, Escape, Delete, and modifier-only rejection.
- Required English labels are present through constants or view inspection-friendly values.

No snapshot-testing library or UI dependency may be added.

## Verification

After integration:

```sh
xcodebuild -project Schiera.xcodeproj -scheme Schiera -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:SchieraTests/Settings test
```

Perform the keyboard/VoiceOver portion later through the coordinator’s manual checklist; report only checks actually run.

## Acceptance

- Every requested user setting is editable without restarting.
- A registration failure is visible and non-destructive.
- Settings code contains no direct AX, CG window-list, Carbon registration, or network calls.
