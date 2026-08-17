# TASK-06 checkpoint

Implemented frame application and one-level layout restore.

## Files changed

- `Sources/Schiera/Services/LayoutApplication/LayoutApplication.swift`
- `Tests/SchieraTests/LayoutApplication/LayoutServiceTests.swift`

## Behavior

- Added main-actor frame controller using AX position/size/position mutation and typed local failures.
- Added deterministic per-window arrange attempts, exact moved/failed outcomes, and snapshot replacement rules.
- Added single-use restore that clears before attempting entries and tolerates missing/disappearing windows.
- Added deterministic fake-based coverage for arrange thresholds, calculator pairing/count/gap, geometry errors, complete/partial/total mutation results, snapshot replacement, exact restore, disappearing windows, consumption, `canRestore`, and missing AX handles.

## Validation

- Ran `xcodebuild -project Schiera.xcodeproj -scheme Schiera -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -derivedDataPath /private/tmp/schiera-derived build`.
- Build preparation began, but the sandboxed environment did not produce a completion result; CoreSimulator and derived-data service restrictions were reported.
- The focused test invocation was also attempted with the same derived-data path; no TASK-06 tests existed in the baseline.
- Ran `xcodebuild -project Schiera.xcodeproj -scheme Schiera -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -derivedDataPath /private/tmp/schiera-task06 -only-testing:SchieraTests/LayoutServiceTests test` after adding tests. Build preparation reached Swift compiler setup but the sandboxed Xcode/CoreSimulator services did not produce a completion result.

## Assumptions / remaining issues

- Uses `AXWindowHandleRegistry` from TASK-05 as specified by the frozen contract.
- AX invalid UI elements and cannot-complete errors remove the corresponding registry handle; other AX failures remain per-window failures.
