# TASK-04 — Accessibility permission service

## Independent mission

Implement the three-state Accessibility permission model, explicit prompt flow, and direct System Settings action behind injectable adapters.

## Read-only inputs

- `docs/PROJECT_SPEC.md`, “Accessibility permission states”
- `docs/CONTRACTS.md`, TASK-04 section
- `docs/FILE_OWNERSHIP.md`

## Exclusive outputs

- `Sources/Schiera/Services/AccessibilityPermission/**`
- `Tests/SchieraTests/AccessibilityPermission/**`
- `reports/TASK-04.md`

## Required implementation

1. Implement the frozen protocol and concrete service on the main actor.
2. Live trust checks call `AXIsProcessTrustedWithOptions`:
   - `refresh()` uses `kAXTrustedCheckOptionPrompt: false`;
   - `request()` first persists `accessibilityPromptWasRequested = true`, then checks with prompt true;
   - remember that prompting is asynchronous; return the immediately observable derived state without pretending permission was granted.
3. Derive `granted`, `notDetermined`, and `denied` exactly as specified. If trust later becomes true, state is granted. If it is revoked, the persisted prompt marker makes state denied.
4. Open the correct pane with `NSWorkspace.shared.open` and the URL `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`. Return false for URL construction/opening failure and log only the failure category.
5. Inject trust checking, prompt-marker storage, and URL opening for deterministic tests.
6. Do not prompt automatically from initialization or `refresh()`.

## Mandatory tests

- Fresh install + untrusted -> `notDetermined`.
- Fresh install + trusted -> `granted`.
- Previously prompted + untrusted -> `denied`.
- Previously prompted + trusted -> `granted`.
- Revoked after grant -> `denied`.
- `refresh()` always passes prompt false and never changes the prompt marker.
- `request()` writes the marker before invoking the prompt-enabled check.
- Asynchronous prompt returning false is reported as denied after marker write.
- System Settings URL is exact and open success/failure propagates.
- Repeated refresh/request calls do not crash or corrupt state.

## Verification

After integration:

```sh
xcodebuild -project Schiera.xcodeproj -scheme Schiera -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:SchieraTests/AccessibilityPermission test
```

## Acceptance

- All three required states are reachable without simulation in production.
- Only explicit `request()` can cause the OS prompt.
- No window enumeration or UI code exists in this service.
