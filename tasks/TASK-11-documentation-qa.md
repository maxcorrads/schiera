# TASK-11 — User documentation, privacy, and manual QA

## Independent mission

Write truthful user/developer documentation and a reproducible manual acceptance checklist from the frozen specification. Do not claim that unrun checks passed.

## Read-only inputs

- all frozen files in `docs/`
- `AGENTS.md`
- all task packets (to describe the intended repository and commands)

## Exclusive outputs

- `README.md`
- `docs/MANUAL_QA.md`
- `docs/PRIVACY.md`
- `reports/TASK-11.md`

## Required README content

1. What Schiera does, with the exact current-Space/pointer-display behavior.
2. Requirements: macOS 14+, Xcode 16+, Swift/SwiftUI, no external dependencies.
3. Build, test, and run instructions using the canonical `xcodebuild` commands plus opening/running the shared Xcode scheme.
4. Explain Accessibility permission in plain English:
   - why it is necessary;
   - how the three app states are derived;
   - how to request it and open System Settings;
   - that permission may need app restart/recheck after changes.
5. List all supported apps and the bundle variants from the frozen catalog.
6. Describe menu commands, default global shortcut, and configurable settings.
7. State privacy properties: local-only preferences/logging, no network, collection, analytics, or terminal-content logging.
8. Known limitations, including:
   - public AX/CG correlation is a proxy for current Space;
   - unusual/full-screen/non-standard windows may be excluded;
   - some terminals enforce size increments/minimum dimensions;
   - global shortcut conflicts can prevent registration;
   - Accessibility trust is OS-managed and cannot be granted by the app;
   - multi-monitor layout uses the pointer position at invocation time.
9. Architecture summary and contributor verification command.
10. Do not include screenshots, badges, download links, signing/notarization claims, or release artifacts that do not exist.
11. Keep all prose and examples in English and remove machine-specific paths, developer account details, signing-team identifiers, or private environment information.
12. Include a license section only when a root `LICENSE` file exists. Do not choose or invent a license for the repository owner.

## Manual QA document

Create a checkbox-based procedure with prerequisites, cleanup/restoration guidance, and expected results for:

- clean launch with permission not yet requested;
- explicit request and later grant;
- denial and revoked-after-grant;
- menu bar only/no Dock/no main window;
- every menu item and Settings opening;
- default shortcut and a changed shortcut;
- shortcut registration conflict/error recovery;
- gap 0, 8, and another value;
- enabling/disabling terminal catalog entries, including all disabled;
- 0, 1, 2, 3, and many visible terminal windows;
- three-window `()()()` layout;
- restore and second restore unavailable;
- window closed during arrange/restore;
- two monitors, negative-origin arrangement, pointer selection;
- windows on another Space remain untouched;
- hidden/minimized/non-standard windows remain untouched;
- menu bar/Dock area exclusion;
- local diagnostic/privacy inspection and no network entitlement/use.

Do not instruct the tester to use destructive shell commands or reveal private terminal contents in reports.

## Privacy document

Write a concise, release-suitable statement describing data not collected, local `UserDefaults`, minimal unified logging categories, Accessibility scope, and zero network/analytics behavior.

## Verification

Run local link/path/required-heading checks that do not depend on implementation. Record them in `reports/TASK-11.md`. The coordinator later runs `scripts/verify.sh`.

## Acceptance

- All README acceptance topics are present and internally consistent.
- Manual QA has explicit expected outcomes, not vague smoke-test prose.
- No unverified success result is presented as fact.
- Documentation is suitable for a public repository and contains no local/private identifiers.
