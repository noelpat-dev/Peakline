# Performance Acceptance Goal

Current file: `PERFORMANCE_ACCEPTANCE_GOAL.md`

## Purpose

Peakline now has a repeatable performance and navigation regression check. Use it whenever work touches the interactive paths that were recently stabilized:

- Today to Coach
- Today to Workout using the prepared first-frame payload
- Workout to Coach
- Workout to Preview
- Preview mode change
- sustained Preview Exercise Order scrolling
- one-back route dismissal
- root notification refresh
- scene phase and background handling
- readiness-gated startup presentation and reveal
- root-tab switching between Today, Workout, Splits, History, and Settings

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
- an active Workout Preview route misses the startup warm cache, shows a bootstrap/hydration shell, or takes more than 500 ms from tap to hydrated first frame
- Check-In takes more than 500 ms from tap to a stable native sheet, a rating response exceeds 100 ms, it presents twice, or it traverses a live SwiftData model during presentation
- a guarded navigation request is duplicated, a warm route exceeds 300 ms to its first stable frame, or a deep/data-backed route exceeds 500 ms
- a root-tab request takes more than 300 ms to reach the selected tab's stable frame
- workout creation performs a synchronous save before the live logger's first frame
- Workout to Coach logs multiple adjacent `appended route=coach` events without `path_changed depth=0` between them
- History logs `history.display_snapshot` between `history.scroll begin` and `history.scroll end`
- Preview logs source-data fetching, signature work, render-snapshot creation, source-catalog publication, or cache publication between `workout_preview.render_snapshot route_mounted` and `route_dismissed`
- workout completion leaves rating or celebration content mounted after Summary navigation, or Substitute requires a second tap to present
- Saved Foods mounts from a prepared value catalog rather than a route-time `@Query`, or its native reveal/reverse-swipe/delete-confirmation regression flow fails

## Supporting Test And Instrumentation

Current support for the verifier lives in:

- `Scripts/verify_performance_acceptance.sh`
- `GymTrackerUITests/CoachWorkoutPreviewUITests.swift`
- DEBUG-only acceptance state in `GymTracker/Utilities/PerformanceTracer.swift`
- DEBUG-only acceptance summary exposure on the persistent startup root in `GymTracker/App/AppStartupView.swift`

The UI acceptance flow covers:

- cold launch
- fast readiness before the animation ceiling
- slow preparation settling into truthful stage progress
- Today to Coach
- Workout to Coach
- Workout to Preview
- one Preview mode change
- sustained Preview scrolling with stable detailed rows and dedicated reorder handles
- one-back dismissal from Coach
- one-back dismissal from Preview
- Coach and Weekly Review content surviving inactive/background lifecycle transitions
- Coach hero and its prepared first explanation appearing together without an empty lower viewport
- repeated native root-tab selection while preserving each tab's navigation state

## Current Baseline

The 21 August 2026 warm-route architecture pass completed a Debug build and all 180 unit/reliability tests. Boot-isolated iPhone 17 simulator samples retained the unchanged thresholds and reported:

- default Today-to-Coach: 219 ms
- default Coach-to-Preview: 283 ms
- default root-tab maximum: 147 ms
- data-rich Sleep: 46 ms
- data-rich Nutrition: 113 ms
- data-rich Progress: 178 ms
- data-rich Hydration: 296 ms
- data-rich Workout/Preview: 174 ms + 387 ms
- Preview warm-cache hits: 1–2; mounted Preview refreshes: 0

The data-rich fixture inserts thousands of SwiftData objects during its launch, unlike a real accumulated-history store. Its root-tab pass is correctness coverage, while the unchanged 300 ms cold root gate remains enforced by an independently booted default fixture. Each performance route is boot-isolated so one route's post-frame observation cannot contaminate the next sample.

Treat these aggregate values as the current healthy baseline rather than a hard promise for every machine; the enforced thresholds remain the source of truth.

The 22 August 2026 motion validation then completed Debug and strict-concurrency builds, passed all 186 unit/reliability tests, and passed focused cached-History and Logger set-completion/rest-timer UI flows. After removing synchronous Today signature work from `onDisappear` and moving Coach/History reveal work behind their stable first frames, its canonical acceptance run reported:

- `performance_acceptance=PASS`
- Today-to-Coach: 178 ms
- Coach-to-Preview: 209 ms
- warmed root transition in the route flow: 186 ms
- dedicated root-tab sequence: 290 ms
- Preview warm-cache hits: 2
- mounted Preview refreshes: 0

During integration, pre-fix samples ranged from 553–607 ms for Today-to-Coach and 530–867 ms for root transitions; these failures identified lifecycle work that was then removed from the transition path. The final green samples retain the unchanged 300 ms warm/root and 500 ms deep-route budgets.

The persistent DEBUG summary includes startup phase durations, per-route and per-root-tab timings, `previewWarmCacheHits`, and mounted refresh counts because current Xcode releases may omit individual app console lines from `xcodebuild` output. The verifier accepts either the original warm-cache trace line or the maximum positive count across root/route summaries; it does not remove the warm-cache requirement or weaken the 300/500 ms budgets.

The 22 August 2026 physical-device layout follow-up passed the canonical verifier after Today-to-Workout began reusing its prepared first-frame payload, Coach mounted its first prepared explanation with the hero, and History stopped measuring duplicate attendance-layout alternatives. The final boot-isolated sample reported Today-to-Coach at 206 ms, Coach-to-Preview at 234 ms, and a 189 ms root-tab maximum (History 189 ms), with two Preview warm-cache hits, zero mounted Preview refreshes, and all 190 unit/reliability tests passing. Earlier same-session root samples at 319–361 ms demonstrated simulator variance and motivated the single-layout History optimization; the 300/500 ms thresholds remain unchanged.

## When To Run It

Run the verifier when changing:

- Today route selection or destination building
- Coach route warm-start behavior
- Workout route navigation
- Workout Preview loading, snapshot, or mode handling
- Root scene phase handling
- Root tab selection, tab content appearance, or tab-level refresh scheduling
- Notification refresh behavior
- Startup presentation, preload, or reveal gating
- SwiftData async paths near these surfaces

For documentation-only tasks or clearly unrelated code, the full verifier is optional.

## Debugging Loop

If the verifier fails:

1. inspect the exact failed condition
2. apply the smallest fix for that failed condition
3. rerun the verifier
4. repeat until it passes or the same failure repeats enough times to justify escalating the blocker

Do not silence warnings without fixing their cause.
