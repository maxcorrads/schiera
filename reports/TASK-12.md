# TASK-12 checkpoint

## Files changed

- `.gitignore`
- `scripts/verify.sh`
- `reports/TASK-12.md`

## Checks run

- `zsh -n scripts/verify.sh` — passed.
- `./scripts/verify.sh --help` — passed; usage documents `--quick` and `--final`.
- Regression checks — passed: `CGPoint`/`CGSize` do not match the private-CGS pattern; `CGSSetWindowLevel` does match; a clean hygiene input returns grep status 1 (no finding); a synthetic private-key credential returns status 0 (finding).
- The public scan now passes `--` before its credential pattern and treats grep statuses other than 0 (finding) and 1 (clean) as scan errors.

The complete verifier intentionally cannot pass until the Xcode project, source, reports, and documentation owned by the other tasks are present. The coordinator should run `./scripts/verify.sh --final` after merging all task outputs.

## Assumptions and remaining issues

- The verifier uses only macOS standard tools and `xcodebuild`; no network or package-manager access is required.
- Build/test failures are reported with their exact `xcodebuild` exit status while allowing all repository checks to finish.
- Temporary DerivedData is created below a validated `mktemp -d` directory and only that child is removed by cleanup.
- Private-CGS matching requires an identifier boundary, `CGS`, and an uppercase symbol character, avoiding false positives for public `CGPoint` and `CGSize`.
