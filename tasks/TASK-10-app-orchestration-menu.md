# TASK-10 — App orchestration, menu, and feedback

## Independent mission

Implement the dependency container, application state machine, menu bar content, and discreet feedback. Orchestrate frozen services without duplicating their internals.

## Read-only inputs

- `docs/PROJECT_SPEC.md`, full required action flow and menu order
- `docs/ARCHITECTURE.md`, runtime flow
- `docs/CONTRACTS.md`, TASK-10 section
- `docs/FILE_OWNERSHIP.md`

## Exclusive outputs

- `Sources/Schiera/App/AppModel.swift`
- `Sources/Schiera/App/DependencyContainer.swift`
- `Sources/Schiera/UI/MenuBar/**`
- `Tests/SchieraTests/App/**`
- `reports/TASK-10.md`

## Required implementation

1. Implement `DependencyContainer` to construct exactly one live instance of each service and share one `AXWindowHandleRegistry` between discovery and frame control. Use a weak action relay when constructing `SettingsViewModel`, then bind that relay to `AppModel.arrange()` after model initialization; this avoids a retain cycle and guarantees shortcut changes keep the same action.
2. Implement `AppModel.live()` plus an internal dependency-injected initializer for tests. Inject termination and any feedback clock/scheduler so tests never quit the runner or sleep.
3. `start()` is idempotent:
   - refresh and publish Accessibility state without prompting;
   - register the persisted shortcut to call `arrange()`;
   - if registration fails, publish a concise localized failure while keeping the app usable.
4. `arrange()` follows the twelve-step flow in `PROJECT_SPEC.md` exactly:
   - refresh permission first on every invocation;
   - stop before screen/discovery when not granted;
   - select pointer screen;
   - resolve included bundle IDs from preferences;
   - discover and deterministically receive windows;
   - for fewer than two, do not call layout service;
   - pass target `visibleFrame` and configured gap to layout service;
   - publish exact success/partial/failure feedback and synchronize `canRestore`.
5. `restore()` refreshes permission first, refuses mutation when untrusted, delegates once when trusted, maps all outcomes, and synchronizes `canRestore`.
6. Permission actions delegate, immediately refresh/publish state, and never pretend the asynchronous system prompt has completed.
7. `quit()` uses the injected/live `NSApplication.terminate` action.
8. Build menu content with the required English entries and order. Use `SettingsLink` for “Settings…”. Disable restore when `canRestore` is false. Show permission status at all times and request/open buttons when needed.
9. Show `feedback` as a short, non-modal row with appropriate SF Symbol/accessibility text. Ordinary insufficient-window/partial results must not show `NSAlert` or notifications requiring another permission.
10. Use `Logger` only for aggregate permission/discovery/move/restore/hotkey results; never log titles or content.

## Mandatory tests

With strict fakes/spies, cover:

- `start()` is idempotent, refreshes permission, and registers persisted shortcut once.
- Start behavior for granted, denied, and not-determined states.
- Shortcut callback invokes the same arrange flow as the menu action.
- Every arrange checks permission before any other service.
- Denied/not-determined arrange calls neither screen, discovery, nor layout.
- Missing pointer screen produces `.noTargetScreen` and stops.
- Empty included catalog passes an empty bundle set to discovery and yields insufficient feedback without mutation.
- Discovery failure maps to non-crashing failure feedback.
- Counts 0 and 1 never call layout and produce exact feedback.
- Three windows pass unchanged/in order to layout with exact visible frame and gap, producing `()()()` through the fake outcome path.
- Complete and partial arrange results map counts and `canRestore`.
- Restore checks permission, maps no snapshot/success/partial failure, and updates `canRestore`.
- Permission request/open actions delegate and mirror current state.
- Quit uses injected closure once.
- Required English menu/feedback strings are centralized and verifiable.

## Verification

After integration:

```sh
xcodebuild -project Schiera.xcodeproj -scheme Schiera -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:SchieraTests/App test
```

## Acceptance

- AppModel is the only layer coordinating all services.
- No modal feedback, network call, polling loop, or direct low-level window API is present in views/AppModel.
- Every early-exit path is proven not to mutate windows.
