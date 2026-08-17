# TASK-08 checkpoint

Implemented the Carbon global shortcut service and formatter.

## Files changed

- `Sources/Schiera/Services/GlobalShortcut/CarbonGlobalShortcutService.swift`
- `reports/TASK-08.md`

## Validation

- Reviewed the frozen shortcut and architecture contracts.
- Confirmed all shortcut validation occurs before backend registration.
- Confirmed replacement, identical-registration, event filtering, and idempotent unregister paths are implemented.
- `xcodebuild ... -derivedDataPath /private/tmp/schiera-task08-derived ... build` completed and produced build intermediates; the focused test invocation could not create the default DerivedData location under sandbox restrictions.
- Added `Tests/SchieraTests/GlobalShortcut/CarbonGlobalShortcutServiceTests.swift`, covering modifier masks, pre-registration validation, event filtering, transactional replacement, status propagation, teardown, and formatter mappings with a deterministic fake backend.
- A focused test run with `-derivedDataPath /private/tmp/schiera-task08-tests2` reached test preparation but the sandbox/Xcode services did not produce a usable result bundle; coordinator should rerun the canonical command during convergence.
- After the Carbon fixes, a fresh `xcodebuild ... -derivedDataPath /private/tmp/schiera-task08-final ... build -quiet` no longer reports TASK-08 errors. The build remains blocked by unrelated existing errors in TASK-03/04/05/09 sources (initializer delegation, AXValue casts, and a let-bound settings preference).
- Updated the three event-delivery tests to await the service's intentional MainActor hop after the fake Carbon callback. This preserves strict event filtering and prevents assertions racing the scheduled handler task. Focused test execution was retried with `/private/tmp/schiera-task08-runtime`; Xcode services emitted environment warnings and did not provide a usable final result because integrated unrelated target failures remain.

## Assumptions / remaining issues

- The injectable backend uses opaque token objects so tests can model Carbon registrations without invoking the live API.
- Live Carbon event extraction is isolated in the backend and forwards only the hot-key ID signature and identifier.
