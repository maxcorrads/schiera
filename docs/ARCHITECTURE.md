# Architecture

## Runtime flow

```text
MenuBarContentView / global hotkey
                 |
              AppModel
       +---------+----------+
       |         |          |
 permission   screen     preferences
       |         |          |
       +---- window discovery
                    |
              LayoutService
              /           \
   HorizontalLayout     AX frame control
       Calculator             |
                         one-level restore
```

`AppModel` is the only orchestration layer. Platform services do not reach into SwiftUI, and views do not call Accessibility or Core Graphics directly.

## Components

| Component | Responsibility | Must not do |
| --- | --- | --- |
| Core models | Stable values and result types shared by tasks | Import SwiftUI, Accessibility, or Carbon |
| Horizontal layout | Pure deterministic frame calculation | Enumerate screens/windows or mutate state |
| Screen service | Find pointer screen and convert AppKit to AX coordinates | Cache `visibleFrame` or choose windows |
| Permission service | Refresh/request trust and open System Settings | Enumerate or move windows |
| Window discovery | Resolve visible standard AX terminal windows and register opaque handles | Calculate or apply layouts |
| Layout service | Apply frames, save one snapshot, restore independently | Discover screens/apps or show UI |
| Preferences/catalog | Validate and persist user choices | Register hotkeys or access AX |
| Global shortcut | Register exactly one Carbon hotkey and deliver action | Arrange windows or mutate preferences |
| Settings UI | Edit preferences and explain Accessibility | Call low-level platform APIs directly |
| App/menu orchestration | Wire services, actions, state, and discreet feedback | Reimplement platform filtering/layout math |

## Window discovery boundary

Accessibility window handles never enter pure models. `WindowDescriptor.id` is an ephemeral UUID plus PID. `AXWindowHandleRegistry`, isolated to the main actor, owns the corresponding `AXUIElement`. Discovery replaces the registry contents for every scan. Layout mutation resolves handles from the registry and treats a missing handle as a recoverable failure.

AX candidates must satisfy all of the following:

- running app bundle identifier is included;
- `NSRunningApplication.isHidden == false` and `isTerminated == false`;
- AX application `kAXHiddenAttribute` is absent/false;
- AX role equals `kAXWindowRole`;
- AX subrole equals `kAXStandardWindowSubrole`;
- `kAXMinimizedAttribute` is absent/false;
- position and size exist, are finite, and have positive width/height;
- a Core Graphics layer-0, on-screen snapshot with the same owner PID has bounds equal within 2 points on each component;
- window center is contained by the target screen’s full AX frame.

An AX read failure skips only that app/window. Deduplicate matches so a single CG snapshot cannot admit more than one AX window. Sort output as defined in the product specification.

## Coordinate conversion

AppKit screen frames use a bottom-left-oriented global coordinate system. Accessibility positions use top-left global coordinates relative to the display containing the menu bar.

Given `primaryFrame = NSScreen.screens[0].frame` and an AppKit rectangle `r`:

```text
axX = r.minX
axY = primaryFrame.maxY - r.maxY
axWidth = r.width
axHeight = r.height
```

Convert both `screen.frame` and the freshly read `screen.visibleFrame`. This formula intentionally preserves negative X or Y values in multi-display arrangements.

## Frame mutation and restore

For each target window, the frame controller sets AX position and AX size and may set position again after resizing to counter applications that anchor resize operations. Any AX error is returned for that window only.

`LayoutService` owns at most one snapshot:

- an arrange call with fewer than two windows performs no calculation/mutation and leaves any existing snapshot intact;
- invalid/insufficient geometry performs no mutation and leaves any existing snapshot intact;
- if one or more window moves succeed, replace the snapshot with original frames for successful windows only;
- if every move fails, retain the previous snapshot;
- restore copies and clears the snapshot before attempting mutations, so it is a single-use action even when some windows disappeared.

## Global shortcut

Use the public Carbon global hot-key API from the installed SDK (`RegisterEventHotKey`, `InstallEventHandler`, `UnregisterEventHotKey`). Keep one event handler and one registration. Register with `kEventHotKeyExclusive` on the main actor, convert Schiera modifiers explicitly to Carbon masks, and invoke the stored closure on the main actor.

Registration is transactional: register a different candidate before discarding the current registration where possible. Re-registering the identical shortcut only replaces its in-process handler. If a candidate fails, retain/re-register the old shortcut and surface an error. Tear down both registration and handler on service deinitialization.

## Concurrency and testability

UI and macOS integration services are `@MainActor`. Pure layout calculation is stateless and can run synchronously. Platform calls sit behind narrow protocols/snapshot providers so tests use fakes and never depend on live permissions, displays, windows, or global registrations.

The project uses Xcode file-system-synchronized groups rooted at `Sources/Schiera` and `Tests/SchieraTests`. This is why all agents may add files concurrently without editing `project.pbxproj`.
