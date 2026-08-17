# Schiera

Schiera is a native macOS menu-bar utility that arranges visible windows from selected terminal applications across the usable area of the display containing the pointer. It acts on the current on-screen Space as determined by the public Accessibility and Core Graphics APIs; windows on other Spaces are left untouched.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 16 or later
- Swift and SwiftUI
- Apple frameworks only; no external dependencies

Schiera has no main window and no persistent Dock icon. It is distributed as a source project in this repository; no signing, notarization, or release artifact is implied.

## Build, test, and run

From the repository root, list the shared scheme with:

```sh
xcodebuild -project Schiera.xcodeproj -list
```

Build and test with the canonical commands:

```sh
xcodebuild -project Schiera.xcodeproj -scheme Schiera -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Schiera.xcodeproj -scheme Schiera -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

Alternatively, open `Schiera.xcodeproj` in Xcode, choose the shared `Schiera` scheme, and use Run or Test. A local run may require granting Accessibility access first.

For stable macOS privacy permissions during development, use an Apple Development identity. The shared project contains no signing-team identifier; a developer may place local overrides in the git-ignored `Schiera.xcodeproj/xcuserdata/LocalSigning.xcconfig`. `Config/Schiera.xcconfig` includes that file optionally and otherwise keeps portable ad-hoc defaults.

## Accessibility access

Accessibility access is required because Schiera must inspect terminal windows and set their position and size. Without it, Schiera does not inspect or move windows. macOS provides a Boolean trust result; Schiera presents three app states: `granted` when trust is true, `notDetermined` when trust is false and Schiera has not requested access, and `denied` when trust is false after an explicit request has been recorded. Revoking previously granted access therefore appears as `denied`.

Use the menu or Settings action “Request Access” to make the explicit request, then enable Schiera in System Settings > Privacy & Security > Accessibility. “Open System Settings” takes you to that pane. Because the OS controls the decision, the app cannot grant access itself. After changing the setting, use the app’s recheck/refresh action or restart the app if the status has not updated.

## Supported terminals

All entries are enabled initially and can be selected independently in Settings.

| Catalog ID | App | Bundle identifier(s) |
| --- | --- | --- |
| `terminal` | Terminal | `com.apple.Terminal` |
| `iterm2` | iTerm2 | `com.googlecode.iterm2` |
| `warp` | Warp | `dev.warp.Warp-Stable`, `dev.warp.Warp-Preview`, `dev.warp.Warp` |
| `ghostty` | Ghostty | `com.mitchellh.ghostty` |
| `alacritty` | Alacritty | `org.alacritty` |
| `kitty` | kitty | `net.kovidgoyal.kitty` |
| `wezterm` | WezTerm | `com.github.wez.wezterm` |

## Menu and settings

The menu provides “Arrange Terminals”, a one-shot “Arrange As…” submenu, “Restore Previous Layout”, “Settings…”, Accessibility status/actions, transient feedback, and “Quit”. Restore is enabled only after an arrangement has successfully moved at least one window. The default global shortcut is Control + Option + Command + S; it can be changed in Settings, which also controls the default arrangement, whole-point gap (0–64), and included terminal applications. Shortcut changes that conflict with another registration are rejected while the previously working shortcut remains active.

Four arrangements are available:

- **Row** places every terminal side by side at full visible height. It remains the default for compatibility and works well with two or three windows on a wide display.
- **Wrapped Rows** keeps a row-like, wide-window shape while flowing 3–6 terminals over two rows and larger sets over three rows.
- **Balanced Grid** creates equal-sized cells in near-square rows and columns. An incomplete final row is centered.
- **Focus** gives the active terminal window 60% of the usable width and stacks the remaining terminals evenly in the right column. Activate the desired terminal immediately before invoking Focus; if macOS does not expose a matching focused window, deterministic screen order is used.

The three multi-row arrangements use the display's public `visibleFrame` plus a small internal safety edge. This preserves the menu-bar/Dock exclusion even when a terminal rounds requested sizes to its own character-cell increments.

“Arrange Terminals” and the global shortcut use the persisted default from Settings. “Arrange As…” applies a selected arrangement once without changing that default. Restore works identically for every arrangement.

## Privacy

Preferences and minimal diagnostic logging stay on the Mac. Schiera has no network functionality, data collection, analytics, or terminal-content logging. Accessibility is used only to inspect and arrange matching windows after the user grants macOS permission. See [the privacy statement](docs/PRIVACY.md).

## Known limitations

- Public Accessibility/Core Graphics correlation is a proxy for the current Space; macOS exposes no supported direct mapping from an Accessibility window to a Space.
- Unusual, full-screen, borderless, overlapping, or otherwise non-standard windows may be excluded or ambiguously matched.
- Some terminals enforce size increments or minimum dimensions and may reject or adjust a requested frame.
- A global shortcut conflict can prevent a new shortcut from registering.
- Accessibility trust is OS-managed and cannot be granted by Schiera.
- On multiple monitors, the pointer position at invocation time selects the target display.

## Architecture and contributor verification

The app is organized into pure core geometry, pointer-screen detection, permission, window discovery, layout/restore, preferences/catalog, Carbon shortcut, Settings, and menu-bar orchestration layers. `AppModel` is the orchestration boundary; platform services do not call SwiftUI directly, and views do not call low-level window APIs.

Contributors should run the repository verification command from the root:

```sh
./scripts/verify.sh --final
```

The final mode performs repository checks and two isolated build/test passes. Manual OS-mediated checks are documented in [MANUAL_QA.md](docs/MANUAL_QA.md).
