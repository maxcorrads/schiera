# TASK-02 checkpoint

Implemented the frozen core value types and deterministic horizontal layout calculator.

Files changed:

- `Sources/Schiera/Core/CoreModels.swift`
- `Sources/Schiera/Core/HorizontalLayoutCalculator.swift`
- `Tests/SchieraTests/Core/HorizontalLayoutCalculatorTests.swift`

Validation:

- Added coverage for empty/single/multiple layouts, remainder distribution, gaps, negative and fractional coordinates, small widths, invariants, and invalid geometry/gaps.
- Attempted `xcodebuild -project Schiera.xcodeproj -scheme Schiera -derivedDataPath /tmp/schiera-task02-derived -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:SchieraTests/Core test`; the command reached build-graph preparation but did not complete in the available validation window. A default-derived-data attempt was blocked by sandbox permission to the user’s standard Xcode DerivedData location.
- Resolved Xcode test compilation ambiguity by explicitly using `CGFloat.infinity` and `CGFloat.nan` in invalid-geometry fixtures.
- Corrected fractional-width and insufficient-space fixtures: flooring a 20.9-point width produces 10/9-point frames with a one-point gap, while a four-point frame can fit two one-point windows and a one-point gap; two points is the rejecting case because only one point remains after the gap.

Assumptions: fractional nonnegative gaps are floored to integral Accessibility points, matching the integral geometry requirement; configured preferences provide whole-point gaps.
