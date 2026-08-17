# TASK-02 — Core models and horizontal layout

## Independent mission

Implement all frozen core value types plus the pure, deterministic horizontal layout calculator. This task owns no macOS enumeration/mutation API and can be completed and tested entirely with geometry values.

## Read-only inputs

- `docs/PROJECT_SPEC.md`, especially layout rules
- `docs/CONTRACTS.md`, sections owned by TASK-02
- `docs/FILE_OWNERSHIP.md`

## Exclusive outputs

- `Sources/Schiera/Core/**`
- `Tests/SchieraTests/Core/**`
- `reports/TASK-02.md`

## Required implementation

1. Implement every TASK-02 type and signature in `CONTRACTS.md` without importing SwiftUI, Accessibility, AppKit, or Carbon.
2. Implement stable modifier raw values and `GlobalShortcut.defaultSchiera` exactly as specified.
3. Implement the exact integral layout algorithm:
   - zero windows returns `[]`;
   - one window returns the full integral frame;
   - gaps occur only between windows;
   - equal base width with remainder assigned to leftmost frames;
   - X positions are contiguous modulo the configured gap;
   - all frames have the full integral height;
   - negative origins are unchanged after flooring;
   - invalid/non-finite inputs and insufficient width throw the specified errors;
   - generated widths are never negative or zero.
4. Keep calculation stateless and `Sendable`.

## Mandatory tests

Use exact frame equality for integral inputs and cover at least:

- 0 windows returns empty;
- 1 window, including a non-zero origin;
- 2 windows with default gap 8;
- 3 windows producing left-to-right `()()()`;
- many windows (at least 20);
- remainder widths where the first windows receive one extra point;
- gaps 0, 8, and 64;
- negative screen X and negative screen Y origins;
- representative multi-monitor visible frames treated independently;
- fractional input is floored deterministically;
- very small width that still fits exactly;
- very small width that cannot fit returns `insufficientSpace`;
- zero/non-finite height and non-finite frame components return `invalidFrame`;
- negative, NaN, and infinite gap return `invalidGap`.

Include invariants in table-driven tests: result count equals input count, first `minX` equals visible `minX`, final `maxX` equals visible `maxX`, and sum(widths)+sum(gaps) equals integral visible width.

## Verification

After integration:

```sh
xcodebuild -project Schiera.xcodeproj -scheme Schiera -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:SchieraTests/Core test
```

Before integration, source inspection and a temporary out-of-repository Swift harness are allowed, but do not commit duplicate contract types or generated artifacts.

## Acceptance

- Mandatory cases pass deterministically.
- No platform state, scaling factor, or backing pixels enter the calculator.
- No TODO, forced unwrap, or silent clamping of invalid gap/geometry.
