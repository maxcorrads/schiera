# Schiera fleet rules

This repository starts as a coordination package for implementing Schiera. It intentionally contains no application implementation in the baseline commit.

## Read first

Every implementation agent must read, in this order:

1. `GOAL.md`
2. `docs/PROJECT_SPEC.md`
3. `docs/CONTRACTS.md`
4. `docs/FILE_OWNERSHIP.md`
5. its assigned file in `tasks/`

The shared goal, specification, contracts, and ownership documents are frozen inputs. Do not edit them during fleet work. If a contract is impossible to honor, stop that task and describe the smallest required contract change in the task report; do not silently fork the API.

## Parallel-work rules

- Every `TASK-XX` is dispatchable immediately from the same baseline. Never wait for another task.
- Edit only the paths owned by the assigned task. Ownership includes that task's `reports/TASK-XX.md`.
- Do not create substitute types for contracts owned by another task and do not commit temporary stubs.
- A task may validate its own pure logic with local fakes. A full product build is expected only after all outputs are merged.
- Merge order is arbitrary because owned paths do not overlap. The coordinator, not a fleet task, runs the final convergence loop in `tasks/README.md`.
- Keep a short checkpoint log in the task's report. Include files changed, commands run, results, assumptions, and any remaining issue.

## Engineering rules

- Swift and SwiftUI only; no external packages, vendored code, analytics, telemetry, or network access.
- Use only documented public macOS APIs. Do not call private `CGS*` functions or infer Space identifiers from private preferences.
- Deployment target: macOS 14.0. Required toolchain: Xcode 16 or newer.
- Build as a menu-bar-only app with `LSUIElement = YES` and App Sandbox disabled because the app controls other processes through Accessibility.
- Keep Accessibility and Carbon objects on the main actor unless an adapter proves safe isolation.
- Treat a disappearing application or window as a recoverable per-item failure.
- Use `Logger` only for minimal local diagnostics. Never log window titles or user-entered content.
- Do not add TODO/FIXME placeholders for required behavior.
- Tests must be deterministic and must not require Accessibility permission or installed terminal applications.

## Integrated verification

After all task outputs are merged, the coordinator runs:

```sh
./scripts/verify.sh --final
```

The underlying canonical commands are:

```sh
xcodebuild -project Schiera.xcodeproj -scheme Schiera -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Schiera.xcodeproj -scheme Schiera -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```
