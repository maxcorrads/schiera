# TASK-05 checkpoint

## Files changed

- `Sources/Schiera/Services/WindowDiscovery/WindowDiscovery.swift`
- `Tests/SchieraTests/WindowDiscovery/WindowDiscoveryTests.swift`

## Implementation

- Added main-actor `WindowDetecting`, `AXWindowHandleRegistry`, and `MacTerminalWindowDetector`.
- Added injectable workspace, Accessibility, trust, and Core Graphics snapshot boundaries plus live adapters.
- Workspace injection uses value snapshots so tests can deterministically represent hidden, terminated, excluded, and disappearing applications without launching processes.
- Discovery filters included/non-hidden/non-terminated apps, AX hidden/role/subrole/minimized state, valid geometry, layer-0 on-screen CG entries, PID/bounds tolerance, target-screen center, and deterministic ordering.
- Registry replacement is atomic per successful scan and clears on Accessibility/window-server failure; matched CG entries are consumed once.

## Validation

- Command: `xcodebuild -project Schiera.xcodeproj -scheme Schiera -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`
- Result: blocked before compilation because the environment denies writes to the default Xcode DerivedData/log directory (`~/Library/Developer/Xcode/DerivedData`).

- Command: `git diff --check`
- Result: passed.

- Follow-up: removed actor-isolated registry default arguments and added actor-safe overloads. `git diff --check` still passes.
- Command: `xcodebuild -project Schiera.xcodeproj -scheme Schiera -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/schiera-task05-derived CODE_SIGNING_ALLOWED=NO build`
- Result: TASK-05 sources compiled; integrated build stopped on unrelated `CarbonGlobalShortcutService.swift` errors from TASK-08.

- Follow-up: fixed the delegated dependency-injected initializer by marking it `convenience`; replaced conditional AXValue casts with CFTypeID validation and typed conversion, and added malformed AX geometry coverage. Fresh build reaches TASK-05 compilation successfully; current integrated failure is unrelated TASK-04 `UserDefaultsAccessibilityPromptMarkerStore` initialization.
- Final follow-up: corrected initializer classification (`init` performs stored-property assignment; delegating overload is `convenience`) and introduced the typed `axValue` adapter. AX values are CFTypeID-validated before conversion, with malformed values returning nil. `git diff --check` passes; fresh build no longer reports WindowDiscovery diagnostics (remaining failures are outside TASK-05).
- Coordinator follow-up: replaced the SDK-incompatible `CFTypeRef as AXValue` conversion with an ownership-preserving `Unmanaged<AXValue>` bridge after CFTypeID validation. `git diff --check` passes and the fresh SDK build emits no TASK-05 diagnostic.
- Test follow-up: converted fake AX handle hashes explicitly to `Int` and replaced AXValue force/optional misuse with deterministic `guard let` creation. `git diff --check` passes.

The WindowDiscovery test suite now includes injected fake-based coverage for app filtering, AX attributes, tolerance/single-entry correlation, layer and center filtering (including negative origins), deterministic output, window-server failure and registry clearing, and scan replacement. Tests do not request Accessibility or depend on installed terminals.

- Command: `xcodebuild -project Schiera.xcodeproj -scheme Schiera -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/schiera-task05-derived CODE_SIGNING_ALLOWED=NO -only-testing:SchieraTests/WindowDiscovery test`
- Result: Xcode progressed through project preparation but the run could not complete in this environment because CoreSimulator/log/provisioning services are unavailable; no Accessibility permission or installed terminal application was required by the added tests.

## Remaining issue

Integrated compilation should be rerun by the coordinator with a writable derived-data path. The service references TASK-02 core value types, which are expected to be present after task convergence.
