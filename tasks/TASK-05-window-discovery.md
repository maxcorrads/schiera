# TASK-05 — Terminal window discovery

## Independent mission

Implement robust Accessibility-based terminal window discovery, public Core Graphics on-screen correlation, and the opaque AX handle registry.

## Read-only inputs

- `docs/PROJECT_SPEC.md`, required behavior and known limitation
- `docs/ARCHITECTURE.md`, “Window discovery boundary”
- `docs/CONTRACTS.md`, TASK-05 section
- `docs/FILE_OWNERSHIP.md`

## Exclusive outputs

- `Sources/Schiera/Services/WindowDiscovery/**`
- `Tests/SchieraTests/WindowDiscovery/**`
- `reports/TASK-05.md`

## Required implementation

1. Implement `AXWindowHandleRegistry` and `MacTerminalWindowDetector` on the main actor.
2. Put all direct AX reads behind small typed helpers/adapters. Convert `AXValue` position/size safely; reject missing, malformed, non-finite, or non-positive geometry.
3. Enumerate only `NSWorkspace.shared.runningApplications` whose exact bundle identifier is in the provided set and which are neither hidden nor terminated.
4. For each included application, create its AX application element and read `kAXWindowsAttribute`. Apply every filter listed in `ARCHITECTURE.md`.
5. Obtain one public window-server snapshot per discovery using:

   ```swift
   CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
   ```

   Retain layer-0 entries with valid owner PID, bounds, and on-screen state. Do not rely on owner name or require Screen Recording.
6. Correlate AX candidate to CG entry by equal PID and component-wise bounds tolerance of at most 2 points. Consume a matched CG entry once. Do not use private window-number or Space APIs.
7. Keep a window only if its center lies within `screen.frame`. Do not clip frames to `visibleFrame` during discovery.
8. Replace the registry atomically for each completed scan, using fresh UUID tokens. If the window server is unavailable, clear the registry and throw the specified error.
9. Sort deterministically by current `minX`, then `minY`, PID, then UUID string.
10. Skip per-app/per-window AX failures and continue. Throw only for service-wide Accessibility/window-server unavailability.
11. Use local aggregate logging only; never log window titles.

## Mandatory tests

Use fake running-app, AX, and CG snapshot providers. Cover:

- each supported bundle identifier can pass when included;
- excluded bundle IDs do not trigger AX enumeration;
- hidden and terminated apps are skipped;
- AX-hidden apps are skipped;
- minimized, sheet/dialog/floating, non-window, malformed, and zero-sized elements are skipped;
- off-screen/off-Space candidates are skipped because no CG match exists;
- layer != 0 CG entries are skipped;
- same PID + exact bounds and <=2-point tolerance match;
- >2-point mismatch does not match;
- one CG entry cannot admit two AX candidates;
- target-screen center filtering with positive and negative display origins;
- deterministic sort order;
- a disappearing window/read failure does not abort siblings;
- window-server failure clears handles and throws;
- a second scan replaces stale registry entries.

## Verification

After integration:

```sh
xcodebuild -project Schiera.xcodeproj -scheme Schiera -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:SchieraTests/WindowDiscovery test
```

## Acceptance

- No private APIs, AppleScript, screen capture, polling loop, or terminal-specific scripting.
- AX handles remain outside core value types.
- Live code tolerates races without forced casts/unwraps.
