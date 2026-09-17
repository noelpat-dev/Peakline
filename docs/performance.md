# Performance Acceptance

Peakline treats first useful interaction as a product requirement. The canonical gate is:

```bash
Scripts/verify_performance_acceptance.sh
```

The latest integrated results and exact test configuration live in the dated [verification record](verification-2026-09-17.md). This document owns the stable measurement contract.

That record contains focused replacement checks only: the canonical verifier and the five-sample route matrix have not been rerun against the current working tree, so route timing is not yet accepted and R21 remains unresolved. No budget below is relaxed while that run is outstanding.

## Budgets

| Path | Budget |
| --- | ---: |
| Warm/root route to stable frame | 300 ms |
| Deep or data-backed route to stable frame | 500 ms |
| Interactive notification refresh | 50 ms |
| Check-In rating response | 100 ms |

Coach and hydrated Workout Preview are data-backed deep routes. A route must not be reclassified, a fixture reduced, or a stable-frame marker moved earlier to conceal a regression.

## What the verifier establishes

The script serialises work on the iPhone 17 simulator and runs:

1. `git diff --check`
2. a Debug build
3. the complete `GymTrackerTests` target
4. focused, boot-isolated route and root-tab UI tests
5. a combined-log audit for timing failures and known interaction/concurrency warnings

It protects:

- readiness-led startup and stable root presentation
- Today → Coach and Today/Workout → Preview
- populated data-rich Nutrition, Progress, Hydration, Sleep, and Preview routes
- root-tab responsiveness and navigation-state preservation
- one route mutation per action
- Preview warm-cache reuse, one on-appear refresh, and no source/cache publication while mounted
- History snapshot protection through active scrolling
- workout creation, rating, completion, Substitute, and Summary presentation invariants
- notification refresh cost
- structural concurrency, gesture-gate, and constraint-warning regressions

## Measurement rules

- Use one simulator destination and no competing build, UI-test, or recording session.
- Restart the simulator for isolated route samples.
- Keep the Debug configuration, production instrumentation, and large-history/saved-food fixtures unchanged.
- Report every sample, median, maximum, and failure count. Do not cherry-pick a fastest run.
- Keep XCTest's cross-process `PRIMARY_QUICK_ACTION_UI_METRIC` separate from the production `NavigationInteraction` stable-frame metric; the latter owns the budget.
- Cache hits, `onAppear`, and screenshots are supporting evidence, not substitutes for a stable useful and interactive frame.
- Use traces or Instruments when a failure needs attribution; do not select a fix from a single noisy sample.

## Focused commands

During implementation, a single route can be reproduced with:

```bash
xcodebuild \
  -project GymTracker.xcodeproj \
  -scheme GymTracker \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO \
  test \
  -only-testing:GymTrackerUITests/CoachWorkoutPreviewUITests/testPerformanceAcceptanceDataRichProgressRoute
```

Focused runs do not replace the final canonical verifier. When a gate fails, inspect the exact route and protected interval, make one evidence-led correction, and rerun affected coverage before the integrated gate.
