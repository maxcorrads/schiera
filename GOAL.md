# Schiera implementation goal

## Start command

Run this from a Codex chat opened at the repository root:

```text
/goal Implement Schiera from the frozen repository specification. Read GOAL.md and AGENTS.md first, delegate TASK-01 through TASK-12 to separate subagents, start every task from the same baseline without waiting for another task, wait for all results, then run the coordinator convergence loop until every verifiable completion criterion passes.
```

## Objective

Build Schiera, a native Swift and SwiftUI macOS menu bar utility that arranges the visible windows of supported terminal applications horizontally across the usable area of the display containing the pointer.

All source code, code comments, documentation, task reports, settings text, feedback, and user-facing interface copy must be written in English. The product name `Schiera` remains unchanged.

Complete the objective without stopping until:

- every output from TASK-01 through TASK-12 is present;
- the Debug application builds without relevant warnings;
- all automated tests pass;
- repository checks find no critical placeholders, simulated production behavior, private APIs, network functionality, analytics, or external dependencies;
- no credential, signing-team identifier, developer account detail, machine-specific absolute path, or generated local metadata is committed to the public repository;
- the manual acceptance checklist has been executed on the available macOS environment, with any externally blocked row recorded precisely;
- `PROGRESS.md` contains concise checkpoints and the exact final commands and results.

## Required reading

Read these files before changing implementation paths:

1. `AGENTS.md`
2. `docs/PROJECT_SPEC.md`
3. `docs/ARCHITECTURE.md`
4. `docs/CONTRACTS.md`
5. `docs/FILE_OWNERSHIP.md`
6. `docs/ACCEPTANCE_MATRIX.md`
7. `tasks/README.md`

## Parallel execution contract

- Delegate one task file to one subagent.
- Dispatch all twelve tasks immediately. A runtime concurrency limit may queue work, but no task may wait on another task or use another task's output as an input.
- Give each subagent the repository root and its exact `tasks/TASK-XX-*.md` file.
- Require every subagent to follow `AGENTS.md`, preserve frozen contracts, edit only its exclusive paths, and write its own report.
- Do not create integration, review, or cleanup work as a thirteenth fleet task. The primary coordinator owns convergence after all task results return.
- If a contract problem is reported, evaluate it centrally. Do not allow agents to create divergent APIs or overlapping compatibility shims.

## Coordinator checkpoints

Record short checkpoints in `PROGRESS.md`:

1. Baseline committed and all twelve tasks dispatched.
2. All task reports received and file ownership checked.
3. First integrated build and test run completed.
4. Owner-routed fixes completed.
5. Two clean final verification passes completed.
6. Manual acceptance completed or externally blocked rows documented.

## Verification

Run from the repository root:

```sh
./scripts/verify.sh --final
```

The canonical underlying build and test commands are:

```sh
xcodebuild -project Schiera.xcodeproj -scheme Schiera -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Schiera.xcodeproj -scheme Schiera -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

Then execute `docs/MANUAL_QA.md` on a Mac with representative terminal applications and Accessibility authorization available.

## Stop conditions

Stop only when the objective and every verifiable item in `docs/ACCEPTANCE_MATRIX.md` are satisfied. If an item depends on unavailable hardware, installed third-party software, signing identity, or a user-controlled macOS permission, exhaust safe local alternatives and record the exact external blocker; never mark the underlying feature complete based on a mock alone.

Do not weaken tests, suppress relevant warnings, change frozen requirements, or introduce unrelated functionality merely to reach a green build.

This is a public repository. Do not add a software license on the owner's behalf; if no `LICENSE` file exists at release time, record that as an explicit owner decision rather than implying reuse rights.
