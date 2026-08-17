# TASK-01 checkpoint

## Files changed

- `Schiera.xcodeproj/project.pbxproj`
- `Schiera.xcodeproj/project.xcworkspace/**`
- `Schiera.xcodeproj/xcshareddata/xcschemes/Schiera.xcscheme`
- `Sources/Schiera/App/SchieraApp.swift`
- `Sources/Schiera/Resources/.gitkeep`

## Implementation

- Created the `Schiera` macOS application target and `SchieraTests` XCTest target.
- Configured Xcode 16 synchronized filesystem root groups for `Sources/Schiera` and `Tests/SchieraTests`.
- Added the shared `Schiera` scheme with Build and Test actions.
- Set macOS 14 deployment, bundle identifiers, generated Info.plists, `LSUIElement`, disabled App Sandbox, enabled Hardened Runtime, Swift 5 mode, and warnings-as-errors settings.
- Added the menu-bar-only SwiftUI app entry point with `MenuBarExtra`, `Settings`, and guarded one-time `AppModel.start()` lifecycle call. No `WindowGroup` is present.
- No package references, network capabilities, or binary artwork were added.

## Validation

- `xcodebuild -project Schiera.xcodeproj -list` — passed; targets `Schiera` and `SchieraTests`, shared scheme `Schiera` listed.
- `plutil -lint Schiera.xcodeproj/project.pbxproj` — passed (`OK`).
- `rg -n 'MACOSX_DEPLOYMENT_TARGET|PRODUCT_BUNDLE_IDENTIFIER|LSUIElement|ENABLE_APP_SANDBOX' Schiera.xcodeproj/project.pbxproj` — passed; required settings present.

Integrated compilation and tests are coordinator-owned and were not run because source contracts owned by the other tasks are not yet present.

## Convergence follow-up

- Audited `PBXNativeTarget.fileSystemSynchronizedGroups`: the app target contains only `Sources/Schiera`, while `SchieraTests` contains only `Tests/SchieraTests`; neither synchronized root is attached to the other target.
- The test target's existing dependency on the app is a normal test-host dependency and does not add app sources to the test target.
- Fixed the project-level `PRODUCT_NAME = Schiera` inheritance that could give the test bundle the app's Swift module name. Both test configurations now explicitly set `PRODUCT_NAME = SchieraTests` and `SWIFT_MODULE_NAME = SchieraTests`; the app remains `Schiera`.
- `plutil -lint Schiera.xcodeproj/project.pbxproj` — passed (`OK`).
- `xcodebuild -project Schiera.xcodeproj -list` — passed; both targets and the shared scheme remain parseable.
- Static membership check confirms distinct synchronized roots and no cross-target source phase entries.

The reported Xcode 26.5 `SWBBuildService` clang `-dM` pipe deadlock is an external toolchain issue, not caused by target membership. A project-scoped workaround sometimes used for that toolchain is disabling explicit Swift module generation (`SWIFT_ENABLE_EXPLICIT_MODULES = NO`) for the affected configuration; it was not applied because it changes build semantics and is unnecessary for this project shell.

## Final lifecycle audit

- `MenuBarExtra` content is menu-hosted and may not receive view `onAppear` until the menu is opened. Startup was moved to `SchieraApp.init()`, where the single `@StateObject` model is started before menu interaction; `start()` remains idempotent in the frozen app contract.
- `rg -n 'WindowGroup|onAppear|model.start|StateObject|MenuBarExtra|Settings' Sources/Schiera/App/SchieraApp.swift` — confirms one `@StateObject`, one initialization-time `model.start()` call, required scenes, and no `WindowGroup` or menu-content lifecycle dependency.
- Integrated build was attempted with `xcodebuild ... -derivedDataPath /private/tmp/schiera-dd build`; this environment stopped at Xcode 26.5's `clang -v -E -dM` external-tool invocation before Swift compilation. No project or machine preference workaround was applied.
