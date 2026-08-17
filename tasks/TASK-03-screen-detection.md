# TASK-03 — Pointer screen and coordinate conversion

## Independent mission

Implement the screen-detection service that chooses the display containing the pointer and returns fresh full/visible frames in Accessibility coordinates.

## Read-only inputs

- `docs/PROJECT_SPEC.md`
- `docs/ARCHITECTURE.md`, “Coordinate conversion”
- `docs/CONTRACTS.md`, TASK-03 section
- `docs/FILE_OWNERSHIP.md`

## Exclusive outputs

- `Sources/Schiera/Services/Screen/**`
- `Tests/SchieraTests/Screen/**`
- `reports/TASK-03.md`

## Required implementation

1. Implement `ScreenCoordinateConverter` with the frozen formula. It must be pure and must not assume the primary frame begins at `(0, 0)`.
2. Implement `MacScreenDetector` using a narrow injectable snapshot provider that supplies:
   - current pointer location in AppKit screen coordinates;
   - ordered screens with `NSScreenNumber`, full frame, and fresh visible frame;
   - the primary/menu-bar screen frame (the first `NSScreen.screens` entry).
3. Match the pointer using `NSMouseInRect(..., flipped: false)` or equivalent half-open containment logic so a shared display edge is assigned deterministically to one screen.
4. Return `nil` if no screen contains the pointer, no primary screen exists, or the selected screen lacks a valid numeric display ID.
5. Never fall back to `NSScreen.main`, because it tracks keyboard focus rather than the pointer.
6. Never cache `NSScreen.visibleFrame`; Dock/menu-bar configuration can change.
7. Preserve negative coordinates and convert both full and visible frames.

## Mandatory tests

- Pointer on a single display.
- Pointer on each of two side-by-side displays.
- Secondary display with negative X origin.
- Display above the primary resulting in negative AX Y.
- Display below the primary.
- Primary frame with a non-zero origin.
- Visible frame excludes menu bar/Dock and converts independently of full frame.
- Pointer exactly on a shared edge resolves deterministically.
- No screens, no containing screen, and missing display ID return `nil`.
- Provider is queried again on each call, proving visible-frame values are not cached.

## Verification

After integration:

```sh
xcodebuild -project Schiera.xcodeproj -scheme Schiera -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:SchieraTests/Screen test
```

## Acceptance

- Service returns only AX-coordinate `ScreenDescriptor` values.
- Tests use snapshots/fakes and work headlessly.
- No screen or application state is mutated.
