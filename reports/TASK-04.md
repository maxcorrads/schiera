# TASK-04 checkpoint

## Files changed

- `Sources/Schiera/Services/AccessibilityPermission/MacAccessibilityPermissionService.swift`

## Implementation

- Added the main-actor `AccessibilityPermissionServicing` contract and live `MacAccessibilityPermissionService`.
- Implemented the three-state derivation using the persisted `accessibilityPromptWasRequested` marker.
- `refresh()` always performs a non-prompting trust check; only `request()` persists the marker before performing a prompt-enabled check.
- Added injectable trust, marker-storage, and settings-opening adapters, plus live `UserDefaults` and `NSWorkspace` adapters.
- Added exact Accessibility privacy-pane URL handling with failure-category logging only.

## Validation

- Commands: source inspection completed with `rg`/`sed`.
- Full `xcodebuild` validation is unavailable at this checkpoint because the baseline contains no Xcode project or other task outputs yet; coordinator should run the focused test and final build after integration.

## Assumptions / remaining issues

- `AccessibilityPermissionState` is supplied by TASK-02 per the frozen contracts.
- Adapter protocols are internal so `@testable import Schiera` tests can inject deterministic fakes without expanding the public API.

## Integration follow-up

- Corrected delegated initializers by marking the live `defaults` overload and closure-backed overload `convenience`; the adapter-based initializer remains designated.
- Re-ran the focused test command with `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`, using `-derivedDataPath /tmp/schiera-derived-task04`. Compilation was prevented by the shared project configuration producing duplicate Swift module outputs for `Schiera` and `SchieraTests`; this is outside TASK-04 ownership. No TASK-04 initializer diagnostics remained.
- Corrected `UserDefaultsAccessibilityPromptMarkerStore.init(defaults:)` back to a designated initializer after the integrated compiler identified the accidental `convenience` classification. A fresh warnings-as-errors run reached only the same shared duplicate-output project failure.
- Diagnosed the ordering-test failure: the fake trust checker asserted marker persistence during the service initializer’s expected `prompt=false` check. The fake now asserts only on `prompt=true`; production `request()` ordering remains unchanged and the assertion still verifies persistence before the prompt-enabled trust call.
