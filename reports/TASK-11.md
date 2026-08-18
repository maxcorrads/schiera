# TASK-11 report — documentation, privacy, and manual QA

## Checkpoint

- Files changed: `README.md`, `docs/MANUAL_QA.md`, `docs/PRIVACY.md`, `reports/TASK-11.md`.
- Documentation was written from the frozen specification, architecture, contracts, acceptance matrix, and task packets. No implementation behavior was assumed beyond those inputs.
- Manual macOS acceptance was not run by this task; the checklist explicitly requires the coordinator/user to record each result and any external blocker.

## Local verification

Commands run:

```sh
rg -n "Accessibility|Supported terminals|Known limitations|Architecture|verify\.sh --final" README.md
rg -n "notDetermined|denied|granted|Request Access|Restore Previous Layout|()\\(\\)\\(\\)|two monitors|network|analytics" docs/MANUAL_QA.md
rg -n "UserDefaults|unified logging|Accessibility|network|analytics|terminal content" docs/PRIVACY.md
```

Result: all commands found the required documentation topics (exit status 0). These are static link/content checks only; they do not claim that the app builds or that manual rows pass.

## Remaining verification

The coordinator must run `./scripts/verify.sh --final` after all task outputs are integrated and execute `docs/MANUAL_QA.md` on an available macOS setup.

## Release documentation checkpoint — 2026-08-18

- Added clean, app-only captures of the menu controls and Settings UI under `docs/images/`; the captures contain no terminal windows, window titles, commands, paths, or user content.
- Added a centered screenshot section to `README.md` with descriptive alternative text and relative repository paths.
- Verified both assets as RGBA PNG files, inspected them visually, checked their dimensions, and scanned embedded strings for user names, local paths, or terminal content; no sensitive text was found.
- `./scripts/verify.sh --quick` — exit 0 outside the command sandbox; repository checks, Debug build, and all 153 tests passed with zero failures.

## License checkpoint — 2026-08-18

- The repository owner explicitly selected the MIT License. Added the standard MIT text in `LICENSE` with copyright attribution to Matteo Corradin and linked it from `README.md`.
- `./scripts/verify.sh --quick` — exit 0; repository checks, Debug build, and all 153 tests passed with zero failures after the license change.

## README badges checkpoint — 2026-08-18

- Added centered badges for live CI status, the latest GitHub release, macOS 14+, Swift 5, Xcode 16+, and the MIT License. Dynamic badges link to their corresponding GitHub pages; static platform badges reflect the project configuration.
- Verified all six badge endpoints successfully, then ran `./scripts/verify.sh --quick`: repository checks, Debug build, and all 153 tests passed with zero failures.
