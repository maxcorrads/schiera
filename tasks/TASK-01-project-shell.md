# TASK-01 — Xcode project and app shell

## Independent mission

Create the native macOS Xcode project, target metadata, resources, and minimal SwiftUI entry point. Start immediately from the coordination baseline. Do not wait for any source service to exist and do not create stubs for types owned by other tasks.

## Read-only inputs

- `docs/PROJECT_SPEC.md`
- `docs/CONTRACTS.md`, especially “App entry point”
- `docs/FILE_OWNERSHIP.md`

## Exclusive outputs

- `Schiera.xcodeproj/**`
- `Sources/Schiera/App/SchieraApp.swift`
- `Sources/Schiera/Resources/**`
- `reports/TASK-01.md`

## Required implementation

1. Create one macOS application target named `Schiera` and one XCTest unit-test target named `SchieraTests`.
2. Use Xcode file-system-synchronized root groups for `Sources/Schiera` and `Tests/SchieraTests`. All Swift files added by other agents must enter the correct target without later `project.pbxproj` edits. Keep the resource directory in the app target only.
3. Create a shared `Schiera` scheme with Build and Test actions.
4. Set:
   - `MACOSX_DEPLOYMENT_TARGET = 14.0`
   - `PRODUCT_BUNDLE_IDENTIFIER = app.schiera.Schiera`
   - `PRODUCT_NAME = Schiera`
   - Swift language mode compatible with Swift 5 source
   - `ENABLE_APP_SANDBOX = NO`
   - `ENABLE_HARDENED_RUNTIME = YES`
   - warnings as errors for project-owned Swift code
   - automatic Info.plist generation
   - `INFOPLIST_KEY_LSUIElement = YES`
5. Link only Apple frameworks required by the specification: SwiftUI/AppKit via SDK, ApplicationServices, CoreGraphics, Carbon, and OSLog. Add no package references.
6. Add a small original symbol asset only if needed; prefer the SF Symbol `rectangle.split.3x1` and avoid binary artwork.
7. Implement `SchieraApp` exactly against the frozen entry-point contract:
   - one `@StateObject` from `AppModel.live()`;
   - `MenuBarExtra` titled “Schiera” with the required system image and `MenuBarContentView`;
   - a `Settings` scene with `SettingsView(model: model.settingsViewModel)`;
   - call idempotent `model.start()` once without creating a main `WindowGroup`.
8. Ensure the app has no normal main window and no Dock/application-switcher icon.

## Verification

Before integration, run checks that do not require other tasks:

```sh
xcodebuild -project Schiera.xcodeproj -list
plutil -lint Schiera.xcodeproj/project.pbxproj
rg -n 'MACOSX_DEPLOYMENT_TARGET|PRODUCT_BUNDLE_IDENTIFIER|LSUIElement|ENABLE_APP_SANDBOX' Schiera.xcodeproj/project.pbxproj
```

After all outputs are present, the canonical build/test commands in `AGENTS.md` must pass. Missing cross-task symbols before merge are expected and must not be “fixed” with placeholders.

## Acceptance

- Project and shared scheme are parseable by Xcode 16+.
- App and test synchronized groups point to the agreed directories.
- No external dependency or network capability is configured.
- No `WindowGroup` or Dock icon is introduced.
- Report contains exact local command results and notes that integrated compilation is coordinator-owned.
