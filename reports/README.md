# Task reports

Each task owns exactly one `TASK-XX.md` report with this shape:

```markdown
# TASK-XX report

## Checkpoints

- [time/order] Short progress statement.

## Files changed

- `path`

## Verification

| Command | Result |
| --- | --- |
| `command` | pass/fail and essential output |

## Contract notes

- None, or a precise issue for the coordinator.
```

Do not claim an integrated build passed unless it was run after all fleet outputs were present.
