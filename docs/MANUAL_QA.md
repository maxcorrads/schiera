# Schiera manual acceptance checklist

Run this checklist on macOS 14 or later with a debug build, a representative selection of supported terminals, and two displays when available. Record the date, macOS version, build revision, and one concise result per row. Do not include terminal contents, window titles, paths, or personal data in reports. A row blocked by unavailable hardware, software, or permission must say exactly what was unavailable; do not mark it passed.

## Prerequisites and cleanup

- [ ] Build and launch Schiera from the shared Xcode scheme; confirm the menu-bar item appears.
- [ ] Prepare disposable terminal windows with no sensitive content. Keep at least four windows available for the count tests.
- [ ] Note the initial positions so restoration can be checked. Close or restore test windows afterward and quit Schiera.
- [ ] If changing Accessibility authorization, use System Settings and record the resulting state; do not use destructive shell commands.

## Permission and launch

- [ ] Clean launch before any request: expected result is a menu-bar-only app, status `notDetermined`, and no terminal inspection or movement.
- [ ] Choose “Request Access”: expected result is the macOS Accessibility prompt/settings route, with no claim that access was already granted.
- [ ] Grant access in System Settings, return to Schiera, and refresh or restart: expected result is `granted` and arrange is available.
- [ ] Change Accessibility access while Schiera is running, then click its menu-bar icon without opening Schiera Settings: expected result is that the menu status refreshes immediately.
- [ ] Test denial: decline the request or leave Schiera disabled; expected result is `denied`, with request/open-settings actions still available and no window mutation.
- [ ] After a granted test, revoke Schiera in System Settings and refresh/restart: expected result is `denied`, not `granted`.
- [ ] Confirm there is no Dock icon, main window, or unexpected application window.

## Menu, Settings, and shortcut

- [ ] Verify menu order and behavior: Arrange Terminals, Arrange As…, Restore Previous Layout (disabled initially), Settings…, Accessibility status/actions, transient feedback, Quit.
- [ ] Open “Settings…”: expected result is the Settings scene, with a default-arrangement picker plus Layout, Shortcut, Included Terminals, and Accessibility controls with English labels.
- [ ] Verify default shortcut Control + Option + Command + S invokes the same arrangement flow as the menu command.
- [ ] Record a different key plus at least one supported modifier: expected result is immediate display and operation of the new shortcut.
- [ ] Attempt a shortcut already owned by another application: expected result is an inline registration error and the previously working shortcut remains active.
- [ ] Correct the conflict or restore the prior shortcut: expected result is successful registration without duplicate invocations.

## Preferences and terminal selection

- [ ] Set gap to 0, arrange two windows, and verify no space between frames.
- [ ] Set gap to 8, arrange three windows, and verify the configured gap is present.
- [ ] Set another value in 0–64, relaunch, and verify it persists and takes effect immediately.
- [ ] Disable one catalog entry and verify its windows are untouched while selected entries are eligible.
- [ ] Disable every catalog entry: expected result is no windows moved and concise insufficient-window feedback.
- [ ] Re-enable the required entries and verify selection persists after relaunch.

## Arrangement and restore

- [ ] With 0 visible matching windows, invoke Arrange: expected result is no mutation and insufficient-window feedback.
- [ ] With 1 window, invoke Arrange: expected result is no mutation and insufficient-window feedback.
- [ ] With 2 windows, verify equal-width horizontal placement across the target visible area.
- [ ] With 3 windows, verify left-to-right `()()()` ordering, equal-width remainder distribution, configured gaps, and full visible height.
- [ ] With many windows (at least 4), verify deterministic left-to-right ordering and no overlap.
- [ ] Choose Balanced Grid for 3 windows: expected result is a two-by-two grid with equal cells and the final window centered in the second row.
- [ ] Choose Balanced Grid for 4 or more windows: expected result is balanced, equal-sized rows and columns with horizontal and vertical gaps, a small safety edge inside the visible frame, and no overlap with the Dock.
- [ ] Choose Wrapped Rows with 3–6 windows: expected result uses two full-width rows; repeat with 7 or more windows and expect three rows.
- [ ] Activate a specific terminal window, then invoke Focus with at least 3 windows: expected result is that active terminal at approximately 60% width and the remaining terminals evenly stacked in the right column. Repeat with a different active terminal.
- [ ] Set each arrangement as the default in Settings and invoke the global shortcut: expected result is the selected default. Use Arrange As… with another mode and verify the persisted default does not change.
- [ ] Arrange successfully, then choose Restore: expected result is original frames restored and Restore becomes unavailable.
- [ ] Choose Restore again: expected result is no operation and “nothing to restore” feedback.
- [ ] Close one target during arrange or restore: expected result is the remaining operations continue, with an accurate partial/failure count and no crash.

## Displays and filtering

- [ ] With two monitors, place the pointer on each in turn and arrange: expected result is only windows whose centers are on the pointer’s display move.
- [ ] Use a display with a negative global X or Y origin: expected result is frames preserve that origin and exclude its menu-bar/Dock area.
- [ ] Move the pointer before each invocation: expected result is invocation-time pointer selection, not keyboard-focus selection.
- [ ] Put windows on another Space: expected result is those windows remain untouched.
- [ ] Hide an application, minimize a window, or use a non-standard/full-screen window: expected result is it remains untouched or is reported as an ordinary skipped/partial case.
- [ ] Verify arranged windows occupy the visible frame rather than the menu-bar or Dock area; multi-row layouts should retain their additional internal safety edge after terminal size rounding.

## Privacy and diagnostics

- [ ] Inspect the app’s local preferences only: expected result is documented values in local `UserDefaults`, with no iCloud synchronization.
- [ ] Inspect local unified logs at an aggregate level: expected result is only documented categories/counts and no titles, paths, content, or keystrokes.
- [ ] Inspect the project capabilities/entitlements: expected result is no network entitlement, analytics SDK, external package, or network request.
- [ ] Review [PRIVACY.md](PRIVACY.md) and confirm observed behavior matches it.
