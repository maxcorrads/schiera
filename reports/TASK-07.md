# TASK-07 checkpoint

## Changes

- Added the ordered seven-application `TerminalCatalog` and bundle-ID resolution.
- Added validated, main-actor `PreferencesStore` using injectable `UserDefaults` and stable keys.
- Added independent fallback/clamping for gap, terminal selection, and versioned shortcut storage.

## Validation

- `swiftc -parse` over the core model, preference implementation, and focused tests passed.
- `git diff --check` passed.
- Focused `xcodebuild ... -only-testing:SchieraTests/Preferences test` was attempted; Xcode cancelled before compilation because the sandbox could not create its default DerivedData workspace under `~/Library/Developer`.

## Assumptions and remaining issues

- Terminal selections and shortcuts are encoded as property-list `Data`, preserving an explicitly empty terminal selection.
- No known contract issues.
