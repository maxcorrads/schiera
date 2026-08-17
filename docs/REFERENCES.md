# Primary references

- [OpenAI Docs — Follow a goal](https://learn.chatgpt.com/use-cases/follow-goals)
- [Apple — MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)
- [Apple — SettingsLink](https://developer.apple.com/documentation/swiftui/settingslink)
- [Apple — NSScreen.visibleFrame](https://developer.apple.com/documentation/appkit/nsscreen/visibleframe)
- [Apple — NSEvent.mouseLocation](https://developer.apple.com/documentation/appkit/nsevent/mouselocation)
- [Apple — AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions)
- [Apple — Accessibility attributes](https://developer.apple.com/documentation/applicationservices/carbon_accessibility/attributes)
- [Apple — kAXStandardWindowSubrole](https://developer.apple.com/documentation/applicationservices/kaxstandardwindowsubrole)
- [Apple — CGWindowListCopyWindowInfo](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo%28_%3A_%3A%29)
- [Apple — CGWindowListOption.optionOnScreenOnly](https://developer.apple.com/documentation/coregraphics/cgwindowlistoption/optiononscreenonly)

The current Xcode SDK public header `Carbon.framework/Frameworks/HIToolbox.framework/Headers/CarbonEvents.h` is the authoritative local reference for `RegisterEventHotKey`, `InstallEventHandler`, and `UnregisterEventHotKey`. The API is present for 64-bit macOS in the installed SDK and is used to avoid adding a dependency or requesting Input Monitoring permission.
