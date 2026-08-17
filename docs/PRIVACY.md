# Schiera privacy statement

Schiera is local-only. It does not send information over the network, collect telemetry, use analytics, or contact a server. It does not record terminal titles, paths, commands, keystrokes, or terminal content.

User choices—including profile names, layout and focus options, gaps and margins, selected terminal catalog entries, display bindings, and keyboard shortcuts—are stored locally in the app’s `UserDefaults`. Display bindings contain only the public display identity needed to match the selected monitor; they do not include screen contents.

The in-app diagnostics view derives local status and aggregate counts. Unified logging is limited to aggregate events and generic failures such as window counts, discovery failures, and shortcut-registration failures. Neither diagnostics nor logs contain window titles, terminal contents, commands, paths, keystrokes, or other user-entered terminal content.

When the user grants macOS Accessibility access, Schiera uses that permission to inspect and reposition matching visible terminal windows. The app does not grant or change the permission, and it does not inspect or move windows while trust is absent. Current-Space filtering uses the public on-screen Core Graphics window list as a proxy because macOS has no supported public Space identifier mapping for Accessibility windows.

No data is synchronized to iCloud or another service. The app requests no network capability and includes no analytics SDK.
