# Fleet dispatch

Dispatch TASK-01 through TASK-12 simultaneously from the same commit. Each packet has complete inputs, exclusive paths, acceptance checks, and a report path. No task depends on another task's output to begin or to make implementation decisions.

## Dispatch table

| Task | Work packet |
| --- | --- |
| TASK-01 | Xcode project and menu-bar app shell |
| TASK-02 | Core models and pure horizontal layout |
| TASK-03 | Pointer-screen detection and coordinate conversion |
| TASK-04 | Accessibility permission state and System Settings routing |
| TASK-05 | Terminal window discovery and AX handle registry |
| TASK-06 | Frame application and one-level restore |
| TASK-07 | Terminal catalog and local preferences |
| TASK-08 | Dependency-free global shortcut service |
| TASK-09 | Settings UI and shortcut recorder |
| TASK-10 | App orchestration, menu content, and feedback |
| TASK-11 | README, privacy statement, and manual QA |
| TASK-12 | Deterministic build/test/repository verification automation |

## Coordinator convergence protocol

This protocol is deliberately not a fleet task because it consumes all task outputs and therefore cannot be concurrent with them.

1. Merge all task outputs in any order.
2. Confirm every `reports/TASK-XX.md` exists and contains its local verification results.
3. Run `./scripts/verify.sh` from this directory.
4. Route each compile/test failure back only to the task that owns the failing file. Owners may fix their paths concurrently.
5. Repeat until the script passes twice from a clean DerivedData directory.
6. Execute `docs/MANUAL_QA.md` on a Mac with Accessibility permission and representative terminals.
7. Create `PROGRESS.md` with brief checkpoints plus exact build, test, repository-scan, and manual-check results.
8. Stop only when the matrix in `docs/ACCEPTANCE_MATRIX.md` is satisfied or an unverifiable external limitation is explicitly recorded.

Do not solve integration errors by weakening contracts, deleting tests, adding blanket warning suppressions, or editing another task's files.
