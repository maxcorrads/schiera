# TASK-08 — Global shortcut service

## Independent mission

Implement a dependency-free, user-configurable global shortcut using the public Carbon hot-key API, with transactional replacement and testable mappings.

## Read-only inputs

- `docs/PROJECT_SPEC.md`, shortcut preferences
- `docs/ARCHITECTURE.md`, “Global shortcut”
- `docs/CONTRACTS.md`, TASK-08 section
- `docs/FILE_OWNERSHIP.md`

## Exclusive outputs

- `Sources/Schiera/Services/GlobalShortcut/**`
- `Tests/SchieraTests/GlobalShortcut/**`
- `reports/TASK-08.md`

## Required implementation

1. Implement the frozen protocol, error type, concrete service, and display formatter on the main actor.
2. Wrap `InstallEventHandler`, `RegisterEventHotKey`, `UnregisterEventHotKey`, and event-parameter extraction behind an internal injectable backend.
3. Maintain one stable four-character Schiera signature and one hot-key ID. Ignore Carbon events whose signature/ID do not match.
4. Explicitly map Schiera modifiers to Carbon `controlKey`, `optionKey`, `shiftKey`, and `cmdKey`. Reject unknown modifier bits, missing modifiers, and modifier-only/no-key candidates.
5. Register with `kEventHotKeyExclusive`, including the default key code `1` + Control/Option/Command exactly, so conflicts surface as registration errors.
6. Deliver matching pressed events to the stored `@MainActor @Sendable` closure exactly once.
7. Replacement must be transactional:
   - an identical shortcut updates the stored handler without duplicate Carbon registration;
   - preserve the old shortcut and handler when candidate registration fails;
   - after candidate success, remove the old registration and publish the new shortcut;
   - if the Carbon API makes simultaneous registration impractical, use a rollback path that deterministically re-registers the old shortcut before throwing.
8. `unregister()` is idempotent. Teardown registration and handler safely in deinitialization.
9. Format shortcuts in Control, Option, Shift, Command, key order using symbols `⌃⌥⇧⌘`; cover ANSI letters/numbers and provide a stable fallback like `Key 123`.
10. Do not use an event tap, local/global `NSEvent` monitor for activation, Input Monitoring permission, or an external hotkey package.

## Mandatory tests

- Default shortcut maps to key code 1 and correct Carbon modifier mask.
- Every modifier and representative combinations map exactly.
- Missing modifier, invalid key code, and unknown modifier bits are rejected before backend registration.
- Matching Carbon event invokes handler once; wrong signature/ID does not.
- Successful replacement unregisters the old registration once.
- Re-registering the identical shortcut keeps one registration and replaces its handler.
- Failed replacement leaves/recovers the old working shortcut and throws a typed error.
- Handler-installation and registration OSStatus values propagate.
- Repeated unregister and teardown are safe.
- Formatter covers default, all modifiers, letters, numbers, and fallback key codes.

## Verification

After integration:

```sh
xcodebuild -project Schiera.xcodeproj -scheme Schiera -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:SchieraTests/GlobalShortcut test
```

Also compile the live Carbon adapter for arm64 and x86_64-compatible macOS SDK APIs; tests must not perform a real global registration.

## Acceptance

- No extra privacy permission beyond Accessibility is introduced.
- Current registration survives an invalid/conflicting user choice.
- Carbon callback lifetime cannot dereference a released service.
