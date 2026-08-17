# Acceptance matrix

| Criterion | Primary implementation | Automated evidence | Manual evidence |
| --- | --- | --- | --- |
| Debug project builds without relevant warnings | TASK-01 and all code tasks | TASK-12 `verify.sh` build step | — |
| All tests pass | TASK-02 through TASK-10 | TASK-12 `verify.sh` test step | — |
| Permission granted/denied/not requested | TASK-04, TASK-09, TASK-10 | Permission and AppModel unit tests with fakes | `MANUAL_QA` permission scenarios |
| Three windows form `()()()` | TASK-02, TASK-06, TASK-10 | exact three-frame and orchestration tests | three live terminal windows |
| Restore returns original frames | TASK-06 | success, partial failure, single-use snapshot tests | live arrange then restore |
| Pointer display and multi-monitor behavior | TASK-03, TASK-05 | coordinate, negative-origin, display-selection, filtering tests | two-display smoke test |
| Current Space only | TASK-05 | on-screen snapshot correlation tests | windows split across Spaces |
| Required terminal apps configurable | TASK-07, TASK-09 | catalog/default/persistence tests | settings checklist |
| Default and custom global shortcut | TASK-08, TASK-09, TASK-10 | mapping, rollback, dispatch tests | global shortcut smoke test |
| No network/data/analytics | all tasks | TASK-12 repository scan | privacy document review |
| README requirements | TASK-11 | TASK-12 required-section scan | documentation review |
| No critical placeholders/simulation | all tasks | TASK-12 repository scan | final code review |
| Exact commands/results reported | coordinator | `PROGRESS.md` checked by TASK-12 script | final handoff review |

The final manual run is necessary for OS-mediated Accessibility prompts and real third-party terminal behavior. Automated tests must still cover every decision path through injected adapters.
