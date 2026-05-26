# Performance Acceptance

## Purpose

Peakline now has a repeatable performance and navigation regression check. Use it whenever work touches the interactive paths that were recently stabilized:

- Today to Coach
- Workout to Coach
- Workout to Preview
- Preview mode change
- one-back route dismissal
- root notification refresh
- scene phase and background handling

## Canonical Command

Run:

```bash
Scripts/verify_performance_acceptance.sh
```

That script is the current acceptance gate for performance-sensitive work. Do not rely only on manual Xcode observation when a change touches those paths.

## What The Verifier Runs

The verifier currently:

1. runs `git diff --check`
2. builds the app in Debug
3. runs `GymTrackerTests`
4. runs the focused UI acceptance test
5. scans the combined logs for timing and regression failures

## Current Failure Checks

The verifier fails on these strings:

- `Potential Structural Swift Concurrency Issue: unsafeForcedSync`
- `Gesture: System gesture gate timed out`
- `Unable to simultaneously satisfy constraints`
- `_UIButtonBarButton`
- `_UIModernBarButton`
- `ButtonWrapper.width`
- `UIView-Encapsulated-Layout-Width == 0`

It also fails if:

- `today.route.appear coach appeared in` is above 500ms
- `root.notification.refresh completed in` is above 50ms in the interactive path
- Workout Preview logs more than one `refresh onAppear` for a single open
- Workout to Coach logs multiple adjacent `appended route=coach` events without `path_changed depth=0` between them

## Supporting Test And Instrumentation

Current support for the verifier lives in:

- `Scripts/verify_performance_acceptance.sh`
- `GymTrackerUITests/CoachWorkoutPreviewUITests.swift`
- DEBUG-only acceptance state in `GymTracker/Utilities/PerformanceTracer.swift`
- DEBUG-only acceptance summary exposure in `GymTracker/App/RootTabView.swift`

The UI acceptance flow covers:

- cold launch
- Today to Coach
- Workout to Coach
- Workout to Preview
- one Preview mode change
- one-back dismissal from Coach
- one-back dismissal from Preview

## Current Baseline

The latest passing verifier run reported:

- `performance_acceptance=PASS`
- `todayCoachMax=228`
- `rootNotificationMax=12`
- `previewOnAppearRefreshes=1`
- `failures=none`

Treat that as the current healthy baseline rather than a hard promise for every machine. The enforced thresholds remain the source of truth.

## When To Run It

Run the verifier when changing:

- Today route selection or destination building
- Coach route warm-start behavior
- Workout route navigation
- Workout Preview loading, snapshot, or mode handling
- Root scene phase handling
- Notification refresh behavior
- SwiftData async paths near these surfaces

For documentation-only tasks or clearly unrelated code, the full verifier is optional.

## Debugging Loop

If the verifier fails:

1. inspect the exact failed condition
2. apply the smallest fix for that failed condition
3. rerun the verifier
4. repeat until it passes or the same failure repeats enough times to justify escalating the blocker

Do not silence warnings without fixing their cause.
