# TASK-12 — Verification automation and repository hygiene

## Independent mission

Create deterministic local verification scripts and ignore rules that validate the frozen repository structure, privacy/dependency constraints, build, tests, reports, and documentation. The script may be authored before the implementation exists and must become useful immediately after merge.

## Read-only inputs

- `AGENTS.md`
- `docs/PROJECT_SPEC.md`
- `docs/FILE_OWNERSHIP.md`
- `docs/ACCEPTANCE_MATRIX.md`
- all task packets

## Exclusive outputs

- `scripts/**`
- `.gitignore`
- `.github/workflows/**` (optional; only if it exactly reuses the local script)
- `reports/TASK-12.md`

## Required implementation

1. Maintain and, where necessary, extend the baseline `.gitignore` for Xcode user data, DerivedData, build products, SwiftPM caches if Xcode creates them, logs, and macOS metadata. Do not ignore source, project, reports, or `PROGRESS.md`.
2. Create executable `scripts/verify.sh` using portable macOS `zsh` or Bash with strict error handling.
3. Resolve paths relative to the script/repository, not the caller’s current directory.
4. Create an isolated DerivedData directory under `mktemp -d`, validate the resolved path before cleanup, and clean only that directory on exit. Never target `$HOME`, `~`, `/`, or the repository with recursive deletion.
5. Run, in a clearly labeled order:
   - project/scheme listing;
   - `plutil` validation for the project and any property lists;
   - structural checks for expected source/test roots;
   - check that all twelve task reports and root `PROGRESS.md` exist for final mode;
   - README required-section checks;
   - forbidden dependency/project-reference checks;
   - source-only scan for network APIs/imports, analytics SDK names, private `CGS` APIs, critical `TODO`/`FIXME`, `fatalError`, and placeholder/mock production behavior;
   - public-repository scan for credentials, signing-team identifiers, developer account details, machine-specific absolute home paths, `.DS_Store`, and other generated local metadata;
   - Debug build with `CODE_SIGNING_ALLOWED=NO` and isolated DerivedData;
   - full unit-test run with the same settings;
   - second build/test pass from a newly created DerivedData directory when invoked with `--final`.
6. Provide `--quick` (single build/test, reports/PROGRESS optional) and `--final` modes. Default to `--quick` during development and document both in script help.
7. Preserve and display exact `xcodebuild` exit status. Do not hide warnings/errors through over-filtering; use `tee` only if pipeline status is preserved.
8. Verify no `XCRemoteSwiftPackageReference`, `packageProductDependencies`, network entitlements, or app sandbox setting contradicting the spec exists.
9. Do not require Homebrew, `xcpretty`, `jq`, Python packages, or network access.
10. An optional GitHub workflow must call `./scripts/verify.sh --quick` rather than duplicate logic and must not be required for local completion.

## Local verification while independent

Before other outputs exist:

```sh
zsh -n scripts/verify.sh
./scripts/verify.sh --help
```

Exercise expected early failures in a disposable copy or via non-mutating checks; do not add files owned by other tasks just to make the script green.

## Integrated acceptance

After merge, the coordinator must be able to run:

```sh
./scripts/verify.sh --final
```

and receive two clean build/test passes plus all repository checks. The script itself must emit a concise final summary with commands and pass/fail state suitable for copying into `PROGRESS.md`.
