# File ownership

The paths below are exclusive. An agent may add private helper files only inside an owned directory explicitly marked with `/**`. Shared contract documents are read-only.

| Task | Exclusive paths |
| --- | --- |
| TASK-01 | `Schiera.xcodeproj/**`, `Sources/Schiera/App/SchieraApp.swift`, `Sources/Schiera/Resources/**`, `reports/TASK-01.md` |
| TASK-02 | `Sources/Schiera/Core/**`, `Tests/SchieraTests/Core/**`, `reports/TASK-02.md` |
| TASK-03 | `Sources/Schiera/Services/Screen/**`, `Tests/SchieraTests/Screen/**`, `reports/TASK-03.md` |
| TASK-04 | `Sources/Schiera/Services/AccessibilityPermission/**`, `Tests/SchieraTests/AccessibilityPermission/**`, `reports/TASK-04.md` |
| TASK-05 | `Sources/Schiera/Services/WindowDiscovery/**`, `Tests/SchieraTests/WindowDiscovery/**`, `reports/TASK-05.md` |
| TASK-06 | `Sources/Schiera/Services/LayoutApplication/**`, `Tests/SchieraTests/LayoutApplication/**`, `reports/TASK-06.md` |
| TASK-07 | `Sources/Schiera/Services/Preferences/**`, `Tests/SchieraTests/Preferences/**`, `reports/TASK-07.md` |
| TASK-08 | `Sources/Schiera/Services/GlobalShortcut/**`, `Tests/SchieraTests/GlobalShortcut/**`, `reports/TASK-08.md` |
| TASK-09 | `Sources/Schiera/UI/Settings/**`, `Tests/SchieraTests/Settings/**`, `reports/TASK-09.md` |
| TASK-10 | `Sources/Schiera/App/AppModel.swift`, `Sources/Schiera/App/DependencyContainer.swift`, `Sources/Schiera/UI/MenuBar/**`, `Tests/SchieraTests/App/**`, `reports/TASK-10.md` |
| TASK-11 | `README.md`, `docs/MANUAL_QA.md`, `docs/PRIVACY.md`, `reports/TASK-11.md` |
| TASK-12 | `scripts/**`, `.gitignore`, `.github/workflows/**`, `reports/TASK-12.md` |

No task owns `AGENTS.md`, `GOAL.md`, `docs/PROJECT_SPEC.md`, `docs/ARCHITECTURE.md`, `docs/CONTRACTS.md`, `docs/FILE_OWNERSHIP.md`, `docs/ACCEPTANCE_MATRIX.md`, `docs/REFERENCES.md`, `tasks/**`, or `reports/README.md`; these are coordination inputs.

The coordinator alone creates or updates root `PROGRESS.md` after merging task outputs.
