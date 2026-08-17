# TASK-06 — Frame application and one-level restore

## Independent mission

Implement the service that applies calculated frames through Accessibility and owns the single previous-layout snapshot.

## Read-only inputs

- `docs/PROJECT_SPEC.md`
- `docs/ARCHITECTURE.md`, “Frame mutation and restore”
- `docs/CONTRACTS.md`, TASK-06 section
- `docs/FILE_OWNERSHIP.md`

## Exclusive outputs

- `Sources/Schiera/Services/LayoutApplication/**`
- `Tests/SchieraTests/LayoutApplication/**`
- `reports/TASK-06.md`

## Required implementation

1. Implement the frozen frame-controller and layout-service APIs on the main actor.
2. `AccessibilityWindowFrameController` resolves the handle from `AXWindowHandleRegistry`; a missing handle throws a typed local error.
3. Use `AXValueCreate` and `AXUIElementSetAttributeValue` safely for `kAXPositionAttribute` and `kAXSizeAttribute`. Apply position, size, then position again. Propagate AX failure as a per-window error and remove invalid handles when appropriate.
4. `LayoutService.arrange`:
   - returns `.insufficientWindows` and performs zero calculator/controller calls for counts 0 or 1;
   - asks the calculator for exactly `windows.count` frames;
   - maps calculation errors to `.invalidGeometry` and performs no mutation;
   - independently attempts every window/frame pair;
   - records original descriptor frames for successful mutations only;
   - replaces the prior snapshot only if at least one mutation succeeds;
   - returns exact moved/failed counts.
5. `restore()` copies and clears its snapshot before attempting frames, tries every stored entry independently, and returns exact restored/failed counts. With no snapshot it returns `.nothingToRestore`.
6. `canRestore` reflects snapshot availability synchronously after every call.
7. Do not rediscover windows, recalculate screen geometry, present UI, or persist snapshots across launches.

## Mandatory tests

- 0 and 1 window never call calculator/controller and preserve an existing snapshot.
- 2, 3, and many windows are paired with calculator frames in deterministic order.
- Default/custom gap is passed unchanged to calculator.
- Calculation failure causes zero frame changes and preserves existing undo.
- Complete arrange success captures every original frame.
- Partial arrange success captures only successfully moved windows.
- Total arrange failure retains the previous snapshot.
- A later successful arrange replaces the previous snapshot (one level only).
- Restore uses exact original frames.
- Missing/disappearing windows do not prevent sibling restore.
- Restore consumes snapshot even on partial/total failure.
- Second restore returns `.nothingToRestore`.
- `canRestore` transitions are exact.
- AX adapter propagates missing handle and set-position/set-size errors without crashing.

## Verification

After integration:

```sh
xcodebuild -project Schiera.xcodeproj -scheme Schiera -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:SchieraTests/LayoutApplication test
```

## Acceptance

- Restore behavior is entirely covered with fake frame controllers.
- No mutation occurs for fewer than two windows or invalid geometry.
- Per-window failures never abort remaining operations.
