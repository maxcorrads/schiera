# TASK-07 — Terminal catalog and preferences

## Independent mission

Implement the supported-terminal catalog and validated local preference persistence. This task does not register shortcuts or present UI.

## Read-only inputs

- `docs/PROJECT_SPEC.md`, catalog and preferences sections
- `docs/CONTRACTS.md`, TASK-07 section
- `docs/FILE_OWNERSHIP.md`

## Exclusive outputs

- `Sources/Schiera/Services/Preferences/**`
- `Tests/SchieraTests/Preferences/**`
- `reports/TASK-07.md`

## Required implementation

1. Implement `TerminalCatalog` with exactly the stable IDs, display names, and bundle-identifier variants in `PROJECT_SPEC.md`. Keep the catalog order identical to the table.
2. All catalog definitions are enabled by default. `bundleIdentifiers(forIncludedIDs:)` ignores unknown catalog IDs and returns the union for known selected definitions.
3. Implement `PreferencesStore` on the main actor with the frozen keys and published values.
4. Persist locally and immediately using an injectable `UserDefaults` instance:
   - gap as `Double`;
   - included terminal IDs as an encoded string collection;
   - shortcut as versioned `Codable` data or an equivalent explicit dictionary.
5. Validate on read and write:
   - finite gap clamped to 0...64, default 8 if not decodable/non-finite;
   - included IDs intersect the known catalog, while an intentionally empty set remains empty;
   - shortcut requires a non-modifier key code and at least one supported modifier; invalid data falls back to default.
6. Distinguish “key absent” from “stored empty terminal set” so users may disable every terminal.
7. `reset()` restores and persists all documented defaults.
8. Do not synchronize to iCloud, call `synchronize()`, log user selections, or access the network.

## Mandatory tests

- Catalog contains all seven required applications and every listed bundle ID, in order, without duplicates.
- Default included IDs and resolved bundle-ID union are exact.
- Unknown IDs are ignored; explicitly empty selection stays empty after round trip.
- Fresh defaults yield gap 8, all terminals, and default shortcut.
- Gap 0, 8, 64 and ordinary values round-trip.
- Out-of-range gap clamps; NaN/infinity/corrupt type falls back safely.
- Custom terminal subset round-trips and stale IDs are removed.
- Default and custom shortcut round-trip.
- Corrupt/unknown-version/invalid shortcut falls back without resetting valid gap or terminal values.
- `reset()` persists defaults.
- Two stores using isolated suites do not leak state.

## Verification

After integration:

```sh
xcodebuild -project Schiera.xcodeproj -scheme Schiera -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:SchieraTests/Preferences test
```

## Acceptance

- No preferences leave `UserDefaults`.
- No application-specific choices are hardcoded outside `TerminalCatalog`.
- Invalid storage never crashes initialization.
