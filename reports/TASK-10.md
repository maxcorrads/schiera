# TASK-10 checkpoint

Implemented app orchestration, dependency wiring, menu-bar content, feedback mapping, permission actions, and injected termination in:

- `Sources/Schiera/App/AppModel.swift`
- `Sources/Schiera/App/DependencyContainer.swift`
- `Sources/Schiera/UI/MenuBar/MenuBarContentView.swift`

Validation: attempted `xcodebuild ... build` with a repository-local derived-data path. The environment stopped during Xcode build preparation because CoreSimulator services were unavailable; no compiler diagnostics were emitted. The default derived-data location was also not writable, so `/tmp/schiera-derived` was used.

Assumptions: neighboring task implementations provide the frozen service initializers and `SettingsViewModel` signature documented in `CONTRACTS.md`. No contract changes or external dependencies were introduced.

Follow-up checkpoint: added `Tests/SchieraTests/App/AppModelTests.swift` with main-actor spies covering start idempotence, shortcut callback, permission gates, target/discovery failures, empty/0/1/3 window paths, exact layout arguments, complete/partial and restore outcomes, permission actions, quit injection, and centralized feedback strings. `xcrun swiftc -parse` succeeds for all TASK-10 source and test files. Full XCTest execution remains dependent on the integrated Xcode build environment.

Actor-isolation fix: the dependency-injected `AppModel` initializer now requires an explicit termination closure. `AppModel.live()` supplies the real `NSApplication` termination action; tests continue to inject a spy closure. This removes the main-actor AppKit reference from a default argument.
