# Schiera product specification

## Product

Schiera is a small native macOS utility that arranges visible terminal windows side by side on the display currently containing the pointer.

It has no main window and no persistent Dock icon. Its only persistent UI is a menu bar extra. It uses no network, collects no data, and has no analytics.

## Platform decisions

- Language/UI: Swift and SwiftUI.
- Minimum OS: macOS 14.0 Sonoma. This supports `MenuBarExtra`, a SwiftUI `Settings` scene, and `SettingsLink` while remaining a reasonable multi-version target.
- Toolchain: Xcode 16 or later.
- Dependencies: Apple frameworks only (`SwiftUI`, `AppKit`, `ApplicationServices`, `CoreGraphics`, `Carbon`, `OSLog`).
- Distribution posture: outside the Mac App Store unless a later distribution review proves Accessibility control compatible with the chosen channel.
- App Sandbox: disabled; Hardened Runtime may remain enabled.
- Bundle identifier for local builds: `app.schiera.Schiera`.
- Language: English for source, documentation, settings, feedback, and all user-facing labels. The product name `Schiera` remains unchanged.

## Required behavior

When the user invokes “Arrange Terminals” or the global shortcut:

1. Refresh Accessibility trust without automatically showing the system prompt.
2. If trust is missing, do not inspect or move windows. Show a concise explanation and actions to request permission and open the Accessibility privacy pane.
3. Locate the `NSScreen` containing `NSEvent.mouseLocation` and obtain its current `visibleFrame` without caching it.
4. Resolve the enabled terminal definitions to bundle identifiers.
5. Discover standard, non-minimized windows belonging to non-hidden matching applications.
6. Keep only windows represented by the current on-screen Core Graphics window list. This is the public-API proxy for excluding windows on other Spaces; do not use private Space APIs.
7. Keep only windows whose center lies in the target screen frame.
8. Sort the windows deterministically by current `minX`, then `minY`, process identifier, and discovery token.
9. If fewer than two remain, change nothing and publish discreet feedback.
10. Calculate equal-width horizontal frames across the target screen’s visible area, with the configured gap between adjacent windows and full visible height.
11. Save each successfully moved window’s original frame in a one-level undo snapshot.
12. Apply each frame independently. If a window disappears or rejects a frame, continue with the remaining windows and report a partial result.

“Restore Previous Layout” attempts one restore using the last successful arrangement snapshot. The snapshot is consumed after the restore attempt. Missing windows are ignored and counted as failures.

## Layout rules

All layout geometry uses Accessibility global screen coordinates: origin at the top-left of the display containing the menu bar, X increasing rightward and Y downward.

For an integral visible width `W`, `N > 0` windows, and integral gap `G >= 0`:

```text
usable = W - G * (N - 1)
base = usable / N
remainder = usable % N
width[i] = base + 1 for i < remainder, otherwise base
```

Remainder points are assigned left-to-right. Each X origin is the preceding origin plus preceding width plus `G`. Every frame uses the complete integral visible height.

- `N == 0` returns an empty frame list.
- A negative or non-finite gap is invalid.
- A non-finite rectangle, non-positive height, or a width that cannot provide at least one point per window after gaps produces `insufficientSpace`; no window is moved.
- Fractional input origins and sizes are floored to integral Accessibility points before calculation.
- Negative screen coordinates are valid and must be preserved.

The term “pixel remainder” in acceptance tests means integral Accessibility points; Retina backing pixels must not be mixed into AX window frames.

## Supported terminal catalog

All definitions are enabled by default. Selection is stored by stable catalog ID, not display name or bundle identifier.

| Catalog ID | Display name | Recognized bundle identifiers |
| --- | --- | --- |
| `terminal` | Terminal | `com.apple.Terminal` |
| `iterm2` | iTerm2 | `com.googlecode.iterm2` |
| `warp` | Warp | `dev.warp.Warp-Stable`, `dev.warp.Warp-Preview`, `dev.warp.Warp` |
| `ghostty` | Ghostty | `com.mitchellh.ghostty` |
| `alacritty` | Alacritty | `org.alacritty` |
| `kitty` | kitty | `net.kovidgoyal.kitty` |
| `wezterm` | WezTerm | `com.github.wez.wezterm` |

## Preferences

- Gap: whole-point value from 0 through 64, default 8.
- Global shortcut: one non-modifier key plus at least one of Control, Option, Shift, and Command.
- Default shortcut: Control + Option + Command + S; virtual key code `1` for the ANSI S key.
- Included terminals: any subset of the catalog; all enabled by default.
- Values persist locally in `UserDefaults` and take effect immediately.
- If a new shortcut cannot be registered, keep the previously working registration and show a validation error.

## Accessibility permission states

Apple’s trust API returns a Boolean rather than a three-state authorization value. Schiera derives the required state as follows:

- `granted`: `AXIsProcessTrustedWithOptions` returns true.
- `notDetermined`: trust is false and Schiera has never recorded an explicit prompt request.
- `denied`: trust is false and Schiera has recorded an explicit prompt request.

The prompt-request marker is local `UserDefaults` state. Revoking a previously granted permission therefore becomes `denied`. Prompting is triggered only by the explicit user action; startup and arrange checks use `kAXTrustedCheckOptionPrompt: false`.

## Menu bar UI

Required items, in this order where practical:

1. “Arrange Terminals”
2. “Restore Previous Layout” (disabled without a snapshot)
3. “Settings…” using `SettingsLink`
4. Accessibility status, with request/open-settings actions when needed
5. A short transient status/feedback row
6. “Quit”

Use a menu bar symbol based on `rectangle.split.3x1`. Missing-permission and partial-failure feedback may temporarily use an exclamation variant and an accessibility label; do not show modal alerts for ordinary outcomes.

## Diagnostics and privacy

Use `Logger(subsystem: "app.schiera.Schiera", category: ...)` for essential local messages only: permission transitions, discovery counts, arrange/restore counts, and registration failures. Never log titles, paths, terminal content, keystrokes, or preference values beyond aggregate counts.

## Known public-API limitation

macOS has no supported public API that directly maps Accessibility windows to Space identifiers. Schiera must correlate standard AX windows with `CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)` using owner PID and approximately equal bounds. This correctly excludes ordinary off-Space windows in normal configurations but may exclude or ambiguously match unusual overlapping, borderless, full-screen, or framework-specific windows. No private `CGS*` workaround is allowed.
