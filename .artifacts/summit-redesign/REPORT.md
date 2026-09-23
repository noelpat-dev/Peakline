# Summit redesign — integration report

23 September 2026. Integration branch: `summit/integration` at `b466984`, based on clean `main` commit `57ae2d9`. The dirty main checkout, its splash-owned files, and the WIP snapshot branch were not edited or merged by this task. This report and the screenshots are the only outputs written under the main checkout.

## Branches and merge order

| Wave | Branch and stream commit | Files owned by the stream | Integration merge |
| --- | --- | --- | --- |
| 1 | `summit/foundation-tokens` `38c4628` | `GymTracker/App/RootTabView.swift`; `GymTracker/Views/Shared/AppTheme.swift` | `ff75260` |
| 1 | `summit/foundation-horizon` `db4a08b` | `GymTracker/Views/Shared/ProgressArcView.swift` | `37f3a04` |
| 1 | `summit/foundation-trail` `a9971d9` | `GymTracker/Views/Shared/FitnessCard.swift` | `9109230` |
| 2 | `summit/screen-secondary` `b0500da` | `GymTracker/Views/Coach/CoachView.swift`; `GymTracker/Views/Sleep/SleepDashboardView.swift` | `a7f1b7d` |
| 2 | `summit/screen-workout` `eeec06e` | `GymTracker/Views/Workout/StartWorkoutView.swift`; `WorkoutPreviewExerciseCard.swift`; `WorkoutPreviewView.swift` | `5280f52` |
| 2 | `summit/screen-splits` `6aa942a` | `GymTracker/Views/Splits/SplitProgrammeCard.swift`; `SplitTrainingDayCard.swift`; `SplitsView.swift` | `23d1470` |
| 2 | `summit/screen-today` `dc42f11` | `GymTracker/Views/Shared/TodayDashboardComponents.swift`; `GymTracker/Views/Today/TodayView.swift` | `1bc0a98` |

The root integrated shared token call sites, supplied the Workout first-frame split type in `GymTracker/Services/WeeklyReviewBuilder.swift`, aligned the deferred Workout route, corrected mode-specific route data and fallback duration, refined Today accessibility text layout, and added focused UI assertions for the no-evidence state. It delayed the Preview Exercise Order section by 50 ms so its detailed rows do not compete with the initial route mount; row-frame tracking remains enabled when the rows appear. It also made the Today native-menu UI-test helper wait for menu actions without swiping the menu away. It updated `docs/design-system.md` with the Summit visual language and the Today description in `docs/architecture.md`; the splash-owned Startup motion section and architecture line 41 were left alone. The final diff from `57ae2d9` changes 21 tracked files, with no new source files, packages, or fonts.

## Visual validation

The interactive `today-v2-mockup.html` was opened through a temporary localhost server. Its new-user, before-training, after-training, clear, storm, day, and night states were inspected. The iPhone 17 simulator used in-memory launch fixtures; screenshots contain synthetic data. The visual structure follows the reference's condensed instruments, layered ridge, trail spine, route waypoints, and restrained monochrome controls.

| Surface or state | Light | Dark |
| --- | --- | --- |
| Today, base camp | [light](screens/today-base-camp-light.png) | [dark](screens/today-base-camp-dark.png) |
| Today, before training | [light](screens/today-before-training-light.png) | [dark](screens/today-before-training-dark.png) |
| Today, sleep data | — | [dark](screens/today-sleep-data-dark.png) |
| Workout root | [light](screens/workout-root-light.png) | [dark](screens/workout-root-dark.png) |
| Workout preview | [light](screens/workout-preview-light.png) | [dark](screens/workout-preview-dark.png) |
| Splits | [light](screens/splits-light.png) | [dark](screens/splits-dark.png) |
| Coach | [light](screens/coach-light.png) | [dark](screens/coach-dark.png) |
| Sleep | [empty](screens/sleep-empty-light.png) | [populated](screens/sleep-populated-dark.png) |

With Reduce Motion enabled in iOS Settings, the Today ridge appeared fully drawn without the intro sequence: [Reduce Motion capture](screens/today-reduce-motion-dark.png). The setting started off and was restored to off. At `accessibility-medium` Dynamic Type, the Today signals display as readable rows and the `today-review-plan` action remained accessible and opened Preview: [Today capture](screens/today-accessibility-medium-dark.png), [Preview capture](screens/workout-preview-accessibility-medium-dark.png). The content size started at `large` and was restored to `large`; simulator appearance started dark and was restored to dark.

There is no existing launch fixture with a workout completed **today**, so the app's after-workout Today state was not visually verified. The reference's after-training state was inspected. SwiftUI `#Preview` declarations for the shared components compiled in Debug; live Xcode Preview rendering was not run.

## Spec choices and remaining gaps

- The Today header shows the date alone because the current Today snapshot does not expose programme week/day. This follows the spec's stated fallback.
- Base Camp uses “Sleep recorded” for its sleep signal rather than “Health connected”: the available sleep-session data cannot prove Apple Health authorization. Checklist values announce complete/not complete to accessibility users. The no-evidence readiness value says “Not available” instead of manufacturing a score.
- The PR ridge flag has `prDayIndex == nil` until Wave 3 supplies history-backed PR data. Alpenglow therefore appears only where an actual achievement exists.
- The Splits mini elevation profile estimates relative exercise volume from target sets and midpoint reps, because the split card has no historical per-exercise volume series.
- The storm sky and warning state are implemented visually. The mockup's storm-day route rescheduling and recovery walk require Wave 3 data/route work.
- The after-workout altimeter gain, cairn streak, and milestone data are Wave 3 features. The mockup uses made-up sample values; the app does not display those as real achievements.

## Verification

| Check | Exact command or action | Result |
| --- | --- | --- |
| Integration Debug build | `xcodebuild -project GymTracker.xcodeproj -scheme GymTracker -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -jobs 2 build` | Passed after the Dynamic Type layout fix; log `/tmp/peakline-summit-dynamic-build.log`. The final source built again in the final performance verifier. |
| Unit suite | `xcodebuild -project GymTracker.xcodeproj -scheme GymTracker -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO test -only-testing:GymTrackerTests` | 230 passed, 0 failed inside the integration verifier. |
| Diff integrity | `git diff --check` | Passed; integration worktree clean. |
| Visual install and fixture launch | `xcrun simctl install booted <Debug-iphonesimulator/GymTracker.app>`; `xcrun simctl launch --terminate-running-process booted com.noel.GymTracker -UITestInMemoryStore -UITestAppearance dark -UITestInitialTab today -UITestCoachFatigueFixture` (plus base-camp and sleep fixture variants) | Passed; the surfaces above were inspected in Simulator and saved with `xcrun simctl io booted screenshot`. |
| Reduce Motion | Settings → Accessibility → Motion → Reduce Motion; relaunch Today with fixture | Passed visual check; restored to off. |
| Dynamic Type | `xcrun simctl ui booted content_size accessibility-medium`; relaunch Today, activate `today-review-plan`; `xcrun simctl ui booted content_size large` | Passed; labels readable and primary action opened Preview; restored to large. |
| Zero-evidence readiness UI | `xcodebuild -project GymTracker.xcodeproj -scheme GymTracker -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO test '-only-testing:GymTrackerUITests/CoachWorkoutPreviewUITests/testReadinessV2ShowsProvisionalCoverageAndMissingSignals' '-only-testing:GymTrackerUITests/CoachWorkoutPreviewUITests/testReadinessV2CheckInSaveRefreshesScoreImmediately'` | The zero-evidence test passed; the companion Check In test failed before the menu-helper correction. Log: `/tmp/peakline-summit-readiness-ui.log`. |
| Check In and Preview reorder UI | `xcodebuild -project GymTracker.xcodeproj -scheme GymTracker -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO -jobs 2 test '-only-testing:GymTrackerUITests/CoachWorkoutPreviewUITests/testReadinessV2CheckInSaveRefreshesScoreImmediately' '-only-testing:GymTrackerUITests/CoachWorkoutPreviewUITests/testWorkoutPreviewReordersByDroppingOnRowAndLoggerKeepsThatOrder'` | Passed: 2 UI tests, 0 failures after the menu-helper and cancellable Preview-mount changes. Log: `/tmp/peakline-summit-final-focused-ui.log`. |
| Reviewer | GPT-6 Luna max read-only integration review, then focused follow-up after corrections | No concrete remaining issue in the final integration diff; reviewer did not run Xcode or Simulator. |
| WIP trial merge | `git merge-tree 57ae2d9 wip/pre-summit-2026-09-23 summit/integration` | Rechecked at final `b466984`: exit 0 with no conflict markers; output `/tmp/peakline-summit-final-trial-merge.txt`. This is a textual merge check, not a build of the WIP branch. |
| Performance acceptance | `Scripts/verify_performance_acceptance.sh` | Final source: failed (exit 65) at the first UI route test. Navigation completed, Coach → Preview measured 306 ms, and Today → Coach measured 544–545 ms against the 500 ms limit. Build and 230 unit tests passed before this UI failure. Log: `/tmp/peakline-summit-final-verifier.log`. |
| Remaining performance UI cases | Exact `xcodebuild` command below, run serially after the verifier stopped | 8 of 9 passed. Data-rich Today → Preview failed at 340 ms against the 300 ms warm-route limit. Log: `/tmp/peakline-summit-remaining-performance-ui.log`. |
| Data-rich Preview comparison | `xcodebuild -project GymTracker.xcodeproj -scheme GymTracker -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO -jobs 2 test '-only-testing:GymTrackerUITests/CoachWorkoutPreviewUITests/testPerformanceAcceptanceDataRichPreviewRoute'` | Integration repeat failed at 651 ms (`/tmp/peakline-summit-preview-route-repeat.log`); clean `57ae2d9` baseline failed at 430 ms (`/tmp/peakline-summit-baseline-preview-route.log`). Both exceed 300 ms. |

The remaining-case command was:

```sh
xcodebuild -project GymTracker.xcodeproj -scheme GymTracker -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO -jobs 2 test '-only-testing:GymTrackerUITests/CoachWorkoutPreviewUITests/testPerformanceAcceptanceRootTabTransitionsRemainResponsive' '-only-testing:GymTrackerUITests/CoachWorkoutPreviewUITests/testDataRichRootTabsRemainPopulated' '-only-testing:GymTrackerUITests/CoachWorkoutPreviewUITests/testPerformanceAcceptanceDataRichReadinessRoute' '-only-testing:GymTrackerUITests/CoachWorkoutPreviewUITests/testPerformanceAcceptanceDataRichSleepRoute' '-only-testing:GymTrackerUITests/CoachWorkoutPreviewUITests/testPerformanceAcceptanceDataRichNutritionRoute' '-only-testing:GymTrackerUITests/CoachWorkoutPreviewUITests/testPerformanceAcceptanceDataRichProgressRoute' '-only-testing:GymTrackerUITests/CoachWorkoutPreviewUITests/testPerformanceAcceptanceDataRichExerciseProgressDetailAndPointSelection' '-only-testing:GymTrackerUITests/CoachWorkoutPreviewUITests/testPerformanceAcceptanceDataRichHydrationRoute' '-only-testing:GymTrackerUITests/CoachWorkoutPreviewUITests/testPerformanceAcceptanceDataRichPreviewRoute'
```

The clean `57ae2d9` baseline ran the same performance script: build passed, 230 unit tests passed, then `testPerformanceAcceptanceRoutes` failed after 92.708 seconds because Today → Coach did not open. A focused baseline retry failed at that same tap after 82.682 seconds. Baseline logs: `/tmp/peakline-summit-baseline-verifier.log` and `/tmp/peakline-summit-baseline-route-retry.log`. The baseline never reached Coach → Preview, so it supplies no comparable Preview route timing.

A focused integration retry of `testPerformanceAcceptanceRoutes` reached the complete route journey, then failed its in-app summary because Coach → Preview took 634 ms against the 500 ms deep-route limit. The same summary recorded Today → Coach 466 ms, Workout → Coach 91 ms, and Workout root-tab selection 184 ms. This was measured before the deferred Exercise Order adjustment; log: `/tmp/peakline-summit-route-retry.log`.

With Exercise Order deferred, the same focused route test again completed navigation and recorded Coach → Preview at **503 ms**, Today → Coach at **711 ms**, Workout → Coach at 99 ms, and Workout root-tab selection at 265 ms. The in-app summary still failed the 500 ms Coach → Preview and Today → Coach limits. This run also had slower startup snapshots (1506/873 ms versus 942/589 ms in the preceding run), so the route timings show material run-to-run variation. The result does not establish performance acceptance. Log: `/tmp/peakline-summit-focused-final.log`.

The final verifier run after the cancellable mount and menu-helper review recorded Coach → Preview at **306 ms** and Today → Coach at **544–545 ms**. It therefore confirms the Preview route can meet its limit, but the overall acceptance remains failed. An earlier integration verifier attempt failed at the initial Today → Coach tap after 80.032 seconds (`/tmp/peakline-summit-integration-verifier.log`).

For the data-rich Today → Preview route, integration measured **340 ms**, then **651 ms** on a direct repeat; the clean baseline measured **430 ms** on its direct run. All exceed the 300 ms warm-route limit. The request-to-appearance timer ends at the destination's `.onAppear`; its `stable_frame` label is the project's instrumentation name, not proof of a committed display frame. A trial return to Today's older lazy section stack did not improve the data-rich Preview result (630 ms), so that unproven layout change was reverted and is absent from `b466984`.

### Performance comparison by UI test

| Test in verifier order | Baseline `57ae2d9` | Summit integration |
| --- | --- | --- |
| `testPerformanceAcceptanceRoutes` | Failed: Today → Coach did not open (92.708 s); retry same failure (82.682 s) | Final verifier: failed 544–545 ms Today → Coach, while Coach → Preview was 306 ms; earlier focused runs had 634 ms Preview before adjustment and 503 ms Preview / 711 ms Today → Coach after adjustment |
| `testPerformanceAcceptanceRootTabTransitionsRemainResponsive` | Not reached | Direct run passed; max root-tab transition 219 ms |
| `testDataRichRootTabsRemainPopulated` | Not reached | Direct run passed |
| `testPerformanceAcceptanceDataRichReadinessRoute` | Not reached | Direct run passed; Today → Coach 225 ms |
| `testPerformanceAcceptanceDataRichSleepRoute` | Not reached | Direct run passed; Today → Sleep 116 ms |
| `testPerformanceAcceptanceDataRichNutritionRoute` | Not reached | Direct run passed; Today → Nutrition 294 ms |
| `testPerformanceAcceptanceDataRichProgressRoute` | Not reached | Direct run passed; Today → Progress 305 ms, within its deep-route limit |
| `testPerformanceAcceptanceDataRichExerciseProgressDetailAndPointSelection` | Not reached | Direct run passed; Progress detail 51 ms |
| `testPerformanceAcceptanceDataRichHydrationRoute` | Not reached | Direct run passed; Today → Hydration 193 ms |
| `testPerformanceAcceptanceDataRichPreviewRoute` | Verifier did not reach it; direct baseline failed at 430 ms | Direct integration runs failed at 340 and 651 ms against warm-route 300 ms |

The script's log and thresholds are the acceptance source; a passing build or unit suite does not imply performance acceptance.

## Wave 3 readiness and open risks

Wave 3 is ready to brief after the user makes `wip/pre-summit-2026-09-23` build. Its unregistered new Swift files currently prevent that branch from compiling, even though the textual trial merge has no conflicts. It should cover History as a summit log, Progress, Nutrition, “Summit reached” celebration overlay, metres climbed, cairn streak, history-backed PR ridge flags, and storm-day route adjustment. Assign a single writer to `StartupCoordination.swift` and measure route timing after its data changes.

Do not merge `summit/integration` into `main` or delete worktrees until the user reviews this result. The main checkout retains its original uncommitted work and the separate splash session remains outside this integration branch.

## Fix round 1

23 September 2026. `summit/integration` is now at `00ba1b2`, after the round-1 fixes and a test-only route-tap stabilization. It remains separate from `main`; the existing dirty main checkout was not merged or altered by these source changes. Four GPT-6 Luna max workers owned disjoint files, and the root merged their commits, ran the simulator checks serially, and reviewed the combined result. A read-only Luna reviewer found no material source issue in the final Coach layout or the combined round-1 diff.

### Changes

| Review item | Result |
| --- | --- |
| P1 1 — horizon intro | Three ridge strokes and the PR flag now use animatable progress; static sky, fills, week labels, and tick do not redraw for every stroke frame. Playback starts after the startup reveal, runs once per launch, and completes immediately if Today disappears. Reduce Motion keeps the completed ridge static. The 100 ms frame sequence below shows the back, middle, and front strokes appearing in order. |
| P1 2 — first action | The horizon is displayed at about 200 pt high while retaining its 332 pt geometry. Conditions has the headline, two-line advice, one readiness/gauge row, and coverage row. Route shows two stops, a single-line `+ N more` summary, then Start. The full Start Push button fits above the floating tab bar at default Dynamic Type. |
| P1 3–4 — chrome | An opaque `backgroundPrimary` top safe area covers content while scrolling. The profile control has one centered plain-person glyph, a 38 pt outline, and a 44 pt hit target; its identifier and menu remain. |
| P1 5 — Today → Coach | The completed direct route runs measured 517–518 ms and 575–576 ms against 500 ms. Earlier `b466984` integration runs measured 544–545 ms and 711 ms. The gap is within the observed run variation and did not regress beyond that earlier range, but the formal performance gate still fails. The read-only route review found no demonstrated, safely removable first-frame cost. The route timer spans selection through destination `.onAppear`, so these totals do not isolate layout work. No speculative performance change was added. |
| P2 6–11 — screen cleanup | Removed the duplicated Conditions logging row and four unused Today components; zero-load days have flat front-ridge points; Base Camp titles reflect pending/completed tasks and no longer show an orphan “Not available” line; Recovery and confidence status use monochrome `TrailSignTag`; Workout root shows four stops and `+ N more` before Start. |
| P2 12 — focused logic tests | Added four tests covering all five readiness mappings, zero-load ridge points, two-stop route presentation/overflow, and the six time-of-day boundaries. |

### Screenshots

All captures are from the iPhone 17 simulator and contain synthetic fixture data. The first-screen and scrolled pairs were inspected in both appearances; the remaining captures are dark.

| State | Capture |
| --- | --- |
| Today fixture, Start visible | [dark](screens/round1/today-fixture-dark.png) · [light](screens/round1/today-fixture-light.png) |
| Today scrolled below opaque status area | [dark](screens/round1/today-scrolled-dark.png) · [light](screens/round1/today-scrolled-light.png) |
| Post-splash horizon intro | [100 ms contact sheet](screens/round1/intro-sequence-contact.png) · [frames](screens/round1/intro-sequence/) |
| Reduce Motion, static ridge | [capture](screens/round1/reduce-motion.png) |
| `accessibility-medium` Today | [capture](screens/round1/accessibility-medium.png) |
| Base Camp | [capture](screens/round1/base-camp.png) |
| Workout root, four stops | [capture](screens/round1/workout-root.png) |
| Recovery Preview | [capture](screens/round1/preview-recovery.png) |
| Coach, final tag layout | [capture](screens/round1/coach.png) |

At `accessibility-medium`, the Start button is lower on the scrollable page; `today-review-plan` opened the prepared Preview in the focused UI test. The simulator's content size was restored to `large`, Reduce Motion to off, and appearance to dark.

For the visual captures, the root installed the Debug app with `xcrun simctl install booted /Users/noelpatricks/Library/Developer/Xcode/DerivedData/GymTracker-aujpfpesomjdjtbgzwvgylqfaxgt/Build/Products/Debug-iphonesimulator/GymTracker.app`, launched fixture states with `xcrun simctl launch --terminate-running-process booted com.noel.GymTracker -UITestInMemoryStore -UITestAppearance dark -UITestInitialTab today -UITestCoachFatigueFixture` (and the corresponding light/Base Camp/Workout variants), then used `xcrun simctl io booted screenshot` with the paths above. Reduce Motion was enabled in Settings → Accessibility → Motion and confirmed by `xcrun simctl spawn booted defaults read com.apple.Accessibility ReduceMotionEnabled` returning `1`; it was restored with `xcrun simctl spawn booted defaults write com.apple.Accessibility ReduceMotionEnabled -bool NO` and confirmed as `0`.

### Validation and remaining acceptance gap

The final source passed the Debug build (`/tmp/peakline-summit-round1-final-build3.log`) and 234 unit tests with no failures (`/tmp/peakline-summit-round1-final-unit-tests.log`). The full verifier also passed its diff, build, and 234-unit-test stages before its UI route failure (`/tmp/peakline-summit-round1-final-verifier-stable.log`). One earlier build command included the unsupported `-parallelizeTargets NO` argument and exited 65 before compiling; the corrected build below passed.

The medium-text Review Plan test passed (`/tmp/peakline-summit-round1-final-medium-review-ui.log`). In the three-case focused UI run, Check In and Preview reorder passed, while the zero-evidence case failed at an intermittent Today → Coach tap (`/tmp/peakline-summit-round1-final-focused-ui.log`). That case passed alone both before and after the test-only tap adjustment (`/tmp/peakline-summit-round1-final-zero-evidence-retry.log`, `/tmp/peakline-summit-round1-final-zero-evidence-stable.log`). The adjustment waits for the splash to disappear and targets the visible signal-coverage row; it does not change app code or performance thresholds.

The Luna reviewer also checked that final test-only change: the new target is text inside the same readiness button, the splash wait fails if the overlay remains, and all Coach and readiness assertions are retained. No material issue was found; the reviewer did not run Simulator.

`Scripts/verify_performance_acceptance.sh` failed at the cold-boot Today → Coach tap even after that adjustment. Its iPhone 17 test left a rendered Today screen and never produced a route summary. A clean-main baseline and an earlier `b466984` verifier had failed at the same tap. In contrast, two direct runs on `00ba1b2` completed the full journey and failed only the Today → Coach 500 ms budget:

| Direct route run | Today → Coach | Coach → Preview | Workout tab | Workout → Coach | Result |
| --- | ---: | ---: | ---: | ---: | --- |
| A — `/tmp/peakline-summit-round1-final-route-a.log` | 517–518 ms | 358 ms | 281 ms | 86 ms | UI summary failed Today → Coach |
| B — `/tmp/peakline-summit-round1-final-route-b.log` | 575–576 ms | 401 ms | 153 ms | 81 ms | UI summary failed Today → Coach |

Thus there are **no two consecutive passing route runs**, and full performance acceptance remains open. The data-rich Today → Preview baseline issue from the prior report was not rerun in this fix round; its last clean-main measurement was 430 ms against a 300 ms warm-route limit. App-side tracing in this round placed manual Today → Coach appearance at 562–566 ms and 684 ms, with selection-state mutation near 0 ms; an attempted process sample captured idle time and was inconclusive. A phase-level trace of destination mount and first frame would be needed before a further source change can be attributed to this gap.

Commands used for final validation (run from the integration worktree; UI commands were serial):

```sh
xcodebuild -project GymTracker.xcodeproj -scheme GymTracker -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -jobs 2 build > /tmp/peakline-summit-round1-final-build3.log 2>&1
xcodebuild -project GymTracker.xcodeproj -scheme GymTracker -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO -jobs 2 test -only-testing:GymTrackerTests > /tmp/peakline-summit-round1-final-unit-tests.log 2>&1
xcrun simctl ui booted content_size accessibility-medium
xcodebuild -project GymTracker.xcodeproj -scheme GymTracker -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO -jobs 2 test '-only-testing:GymTrackerUITests/CoachWorkoutPreviewUITests/testReviewTodayPlanOpensPreparedPreviewWithoutStartingLogger' > /tmp/peakline-summit-round1-final-medium-review-ui.log 2>&1
xcrun simctl ui booted content_size large
xcodebuild -project GymTracker.xcodeproj -scheme GymTracker -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO -jobs 2 test '-only-testing:GymTrackerUITests/CoachWorkoutPreviewUITests/testReadinessV2ShowsProvisionalCoverageAndMissingSignals' '-only-testing:GymTrackerUITests/CoachWorkoutPreviewUITests/testReadinessV2CheckInSaveRefreshesScoreImmediately' '-only-testing:GymTrackerUITests/CoachWorkoutPreviewUITests/testWorkoutPreviewReordersByDroppingOnRowAndLoggerKeepsThatOrder' > /tmp/peakline-summit-round1-final-focused-ui.log 2>&1
xcodebuild -project GymTracker.xcodeproj -scheme GymTracker -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO -jobs 2 test '-only-testing:GymTrackerUITests/CoachWorkoutPreviewUITests/testReadinessV2ShowsProvisionalCoverageAndMissingSignals' > /tmp/peakline-summit-round1-final-zero-evidence-stable.log 2>&1
xcodebuild -project GymTracker.xcodeproj -scheme GymTracker -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO -jobs 2 test '-only-testing:GymTrackerUITests/CoachWorkoutPreviewUITests/testPerformanceAcceptanceRoutes' > /tmp/peakline-summit-round1-final-route-a.log 2>&1
xcodebuild -project GymTracker.xcodeproj -scheme GymTracker -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO -jobs 2 test '-only-testing:GymTrackerUITests/CoachWorkoutPreviewUITests/testPerformanceAcceptanceRoutes' > /tmp/peakline-summit-round1-final-route-b.log 2>&1
Scripts/verify_performance_acceptance.sh > /tmp/peakline-summit-round1-final-verifier-stable.log 2>&1
git diff b466984 HEAD --check
git merge-tree 57ae2d9 wip/pre-summit-2026-09-23 summit/integration > /tmp/peakline-summit-round1-final-trial-merge.txt
```

`git diff b466984 HEAD --check` passed. The trial merge exited 0 and produced no conflict markers; it was not built. The `summit/integration` worktree is clean. The original main working-tree changes and untracked files remain in place, and no merge into `main` was made.

## Fix round 2

23 September 2026. Three GPT-6 Luna max workers made disjoint changes, merged by the root into `summit/integration` at `f7368d0`. The branch remains separate from `main`. A read-only Luna review found no additional issue in the visual or accessibility fixes; performance acceptance remains open.

### Changes and screenshots

| Item | Result |
| --- | --- |
| Header and sky | The 200 pt horizon crop is retained. Back and middle ridges clear the wordmark/date band, and sky symbols sit visibly to the left of the profile button. Dark captures show a rayed sun for clear day, two clouds plus faint sun for changeable day, rain/clouds/bolt for storm day, and moon/stars for clear night. The light capture confirms the header clearance. No ridge crosses the header text; the sky is well beyond the required 16 pt profile clearance. |
| Accessibility advice | The two-line limit applies only below accessibility Dynamic Type sizes. At `accessibility-medium`, the complete advice ends in “prioritize clean reps.” |
| Coach and Base Camp | The Evidence icon uses the monochrome secondary treatment. Base Camp checklist details explain each action rather than repeating its title. |
| Post-reveal timing | Added DEBUG-only `os_signpost` intervals around the root reveal callback, readiness refresh, and synchronous warm-route projections. No startup scheduling or route behavior was changed because profiling did not identify a safe app-side cost to remove. |

All captures are from the iPhone 17 simulator. Weather/night variants use synthetic `-UITestCoachFatigueFixture` data plus DEBUG launch arguments `-SummitCondition=clear|changeable|storm` and `-SummitTime=day|night`. These arguments override **horizon artwork only**, so the readiness text remains fixture-derived. The Coach screenshot was exported from a passing focused UI-test attachment; its temporary capture code was removed afterward.

| State | Screenshot |
| --- | --- |
| Clear day, dark | [capture](screens/round2/clear-day-dark.png) |
| Changeable day | [dark](screens/round2/changeable-day-dark.png) · [light](screens/round2/changeable-day-light.png) |
| Storm day, dark | [capture](screens/round2/storm-day-dark.png) |
| Clear night, dark | [capture](screens/round2/clear-night-dark.png) |
| Full accessibility advice | [capture](screens/round2/accessibility-medium-advice.png) |
| Base Camp and Coach Evidence | [Base Camp](screens/round2/base-camp.png) · [Coach](screens/round2/coach-evidence.png) |
| Intro, about 100 ms per frame | [contact sheet](screens/round2/intro-sequence-contact.png) · [full frames](screens/round2/intro-sequence/) |

The intro frames span video times 12.900–14.387 s in roughly 100 ms steps. Ridge pixels changed at every step from first motion through the last drawing frame; there were no three consecutive identical frames while drawing. Final static frames were excluded from the contact sheet.

### Post-reveal profiling and remaining gap

`xctrace` Time Profiler with `os_signpost` was attempted with app-path launch, simulator all-process recording, attach to the simulator PID, and installed bundle-ID launch. Each printed “Starting recording” but exceeded its 8–18 s limit without writing samples; the trace contained only `RunIssues.storedata`, and `xctrace export` reported a missing template. App-path launch was the wrong simulator target, but the other attempts used the iPhone 17 UDID and the final one used the installed bundle ID. No usable Instruments trace was produced.

Simulator unified-log signposts and a targeted `/usr/bin/sample` capture provide bounded evidence instead. In a fixture launch, startup local preparation took 581.7 ms, including 296.6 ms of snapshot preparation, **before** the reveal. In the reveal window, the root callback took 1.8 ms, its nested readiness refresh 0.2 ms, two Today snapshot publications 5.1 and 6.7 ms, and notification refresh 0.3 ms. No warm-route signpost interval was observed in that launch. The 2-second main-thread sample started 149 ms after the root reveal signpost: 176 of 261 samples were in the run-loop wait; the largest active stack had 69 samples in UIKit update processing, including 51 in Core Animation transaction flush, 41 in RenderBox display, 20 in surface allocation, and one in the Summit ridge path. Counts are nested samples, **not measured durations or proof of a rendering cause**. Evidence: `/tmp/peakline-summit-round2-final-signposts.json`, `/tmp/peakline-summit-round2-post-reveal.sample.txt`, and `/tmp/peakline-summit-round2-sample-run.log`.

The next performance step is a working Time Profiler/Animation Hitches capture across the reveal and the failing destination's first frame, with route-specific signposts around destination construction and appearance. That would distinguish render transaction pressure from route preparation before moving work or simplifying drawing. No thresholds or test timing were changed.

### Validation

The final Debug build passed (`/tmp/peakline-summit-round2-final-build.log`), as did 234 unit tests (`/tmp/peakline-summit-round2-final-unit-tests.log`). The focused Coach readiness UI test passed both normally and with the temporary screenshot attachment. The route acceptance test completed its in-app journey twice, but neither summary passed:

| Run | Today → Coach (500 ms) | Coach → Preview (500 ms) | Workout → Coach (300 ms) | Summary |
| --- | ---: | ---: | ---: | --- |
| A — `/tmp/peakline-summit-round2-route-a.log` | 492 ms | 624 ms | 73 ms | Failed Coach → Preview |
| B — `/tmp/peakline-summit-round2-route-b.log` | 224 ms | 532 ms | 71 ms | Failed Coach → Preview |
| Full verifier — `/tmp/peakline-summit-round2-verifier.log` | 492 ms | 497 ms | 387 ms | Failed Workout → Coach |

`Scripts/verify_performance_acceptance.sh` passed its build and 234-unit-test stages, then failed that UI summary. Thus there are **no two consecutive passing route runs**; full performance acceptance is not met. The verifier's prior clean-main cold-boot tap failure did not occur in this run. The data-rich Today → Preview baseline gap was outside this fix round and was not rerun.

`git diff 00ba1b2 HEAD --check` passed and the integration worktree is clean. The trial `git merge-tree 57ae2d9 wip/pre-summit-2026-09-23 summit/integration` exited 0 with no conflict markers; it was not built. The iPhone 17 simulator was left at dark appearance, `large` text, and Reduce Motion off (`0`). No source changes were made in the dirty main checkout and no branch was merged into `main`.

## Wave 3A — build-ahead handoff

### Isolation and delivered branches

Wave 3A started from summit/integration at f7368d01205064e308fe3616057374554f00535d. Its integration branch and worktree are summit/wave3a at /Users/noelpatricks/Developer/Peakline-wt/wave3a. The main checkout and every round-2 branch/worktree were read-only throughout. This report was copied into and updated in the isolated Wave 3A worktree because writing the report in the main checkout would violate that boundary.

| Stream | Branch and commit | Files delivered |
| --- | --- | --- |
| Scaffold/root | summit/wave3a, b107465 | GymTracker/Models/SummitModels.swift; GymTracker/Views/Shared/SummitGalleryView.swift; registration of the new Swift/test files in GymTracker.xcodeproj/project.pbxproj; DEBUG -SummitGallery entry in GymTracker/App/GymTrackerApp.swift |
| Engine | summit/w3a-engine, d973d7b | GymTracker/Services/SummitProgressService.swift; GymTracker/Services/SummitSnapshotBuilder.swift; GymTrackerTests/SummitProgressServiceTests.swift; GymTrackerTests/SummitSnapshotBuilderTests.swift; permitted helper in GymTracker/Services/TrainingAnalyticsService.swift |
| Log and range | summit/w3a-log-range, 8c8b865 | GymTracker/Views/Shared/SummitLogViews.swift; GymTracker/Views/Shared/SummitRangeView.swift |
| Trails | summit/w3a-trails, 09aaf56 | GymTracker/Views/Shared/SummitTrailViews.swift; GymTracker/Views/Shared/SummitIcons.swift |
| Icons | summit/w3a-icons, c936201 | GymTracker/Views/Shared/SummitAppIconPicker.swift; AppIconNight, AppIconAlpenglow, and AppIconEverest appiconsets; screens/wave3a/icon-topo-proposal.png |
| Moments | summit/w3a-moments, 1e7d709 | GymTracker/Views/Shared/SummitMomentViews.swift |

Root merged the streams in this order: engine (6326590), log and range (107ee0f), trails (fd44360), icons (2a0e909), moments (09162a4). Root then committed the contract/integration corrections e729ee6, f0fc6e5, 41f75c7, e4b417e, f823588, and a58eaae. The root's alternate-icon project-setting edit in e4b417e came after the scaffold commit, later than the orchestrator's stated project-file timing; no worker edited that file. Stream worktrees remain present and clean. No merge into summit/integration, main, or the WIP branch was made.

### Shared contract and behaviour

SummitModels.swift defines the typed peak/camp/route/icon catalog, pure input and snapshot values, and preview and empty fixtures. Root added SummitBodyweightInput and SummitWeightFormatting when implementation showed that the existing model did not carry all data and there was no shared kg/lb formatter. SummitSetInput has a distinct set ID so the three best sets are individual sets, not repetitions of one session. SummitProgressService caps the Uhuru altitude at 5,895 m, reports the current descent camp after Lava Tower as Barranco (3,960 m), and uses a two-session weekly cairn target. For weighted bodyweight work, effective load includes the bodyweight factor plus added load; PRs and best sets carry a bodyweight flag, and Range speaks/displays BW or BW+ appropriately. The gallery fixture's weighted pull-up sets use that flag. The app icon picker takes unlocks from the engine and the alternate icon names are registered in Debug and Release project settings.

SetLog has no historical per-set unit field. The current extraction uses the supplied unit system for historical loads; a future unit change may therefore misstate older loads until a source of per-set units or a migration rule is available. The new data engine is not wired into startup and the new screens are not reachable from normal app navigation in this wave.

### Compile record

Every command used the same guarded helper, /tmp/peakline-w3a-compile.sh, with exactly one Wave 3A compile slot. It checked for round-2 performance processes immediately before building and waited/rechecked in 60-second intervals whenever one was present. For each row, the expanded compile command was:

    nice -n 10 xcodebuild -project GymTracker.xcodeproj -scheme GymTracker -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/peakline-dd-w3a-STREAM -jobs 4 ACTION

Replace STREAM and ACTION with the row values below. The helper removed only its own /tmp/peakline-dd-w3a-STREAM build cache after the command. The first overlapping cold builds encountered limited local disk space; later builds were serialized. No simulator test, xctrace, or performance verifier was run by Wave 3A.

| Worktree STREAM | ACTION | Outcome and evidence |
| --- | --- | --- |
| scaffold | build | Passed; /tmp/peakline-w3a-scaffold-build.log |
| engine, first attempt | build-for-testing | Failed from no space left during overlapping cold compiles; cache cleaned |
| engine, final | build-for-testing | Passed; /tmp/peakline-w3a-engine-final.log |
| log-range, first attempt | build | Failed from no space left during overlapping cold compiles; cache cleaned |
| log-range, final | build | Passed; streamed terminal result |
| trails, first attempt | build | Failed from no space left during overlapping cold compiles; cache cleaned |
| trails, retry | build | Passed; /tmp/peakline-w3a-trails-build.log |
| trails, final | build | Passed; /tmp/peakline-w3a-trails-build-final.log |
| moments, first attempt | build | Failed during the initial compile; cache cleaned |
| moments, second attempt | build | Failed: SummitPRFlag(color:) called an unavailable initializer; /tmp/peakline-w3a-moments-build.log |
| moments, final | build | Passed after using the existing fill initializer; /tmp/peakline-w3a-moments-final-build.log |
| icons | build | Passed; streamed terminal result |
| integrated, first | build-for-testing | Passed; /tmp/peakline-w3a-integrated-build-for-testing.log |
| integrated, after review fixes | build-for-testing | Passed; /tmp/peakline-w3a-integrated-post-review.log |
| integrated, after fixture correction | build-for-testing | Passed; /tmp/peakline-w3a-integrated-final.log (TEST BUILD SUCCEEDED, line 12945) |

The two new test classes and the full test target were compiled by build-for-testing. Tests were compiled, not run. Step 3 remains deferred until Noel explicitly says round 2 has finished.

### Board choices and visual scope

The Log content keeps History's existing heading and month controls in the future host, rather than duplicating them. Its lower-route text uses “LOWER ROUTE · CAIRN KEPT” from the brief where the board says “STORM DAY.” The month ridge is drawn from entries supplied for the displayed month; the host must fetch all of that month rather than relying on startup's small recent-history window.

The moment view draws a dedicated altitude tape because the existing AltimeterView range does not reach the next preview milestone. Its Share preview uses a mountain symbol; the share action renders the actual postcard image. The milestone animation is keyed to its identity and resolves to its final state with Reduce Motion. These behaviours still need simulator inspection.

ExpeditionView accepts an optional recentSessionsPerWeek. A missing or invalid value shows an unknown summit window, so next-round wiring must supply real frequency. The camp icon stroke is size/16 at 36 pt as the brief specifies, visibly heavier than the board's sample stroke. The dimmed route sign is drawn locally because TrailSignTag has no dimmed state.

The Night app icon uses a cubic approximation of the board's moon arc. Picker thumbnails are drawn in Canvas because appiconsets are not guaranteed ordinary Image resources. Three alternate icons are opaque 1024 × 1024 PNGs. The topographic proposal is a separate visual artifact; the current primary AppIcon was not replaced. No gallery screenshot or runtime share-sheet proof was attempted while round 2 owned the simulator.

### Review and merge trials

A GPT-6 Luna Max read-only reviewer inspected the whole Wave 3A diff for the metres calculation, accessibility, Reduce Motion, one-shot animation, and permitted-file boundary. It found two P2 issues: the cairn “climbs needed” count used one session instead of the specified two-session weekly target, and bodyweight PR/best-set numbers omitted effective bodyweight load and clear BW/BW+ presentation. Root fixed both in f823588 and added focused assertions. The reviewer rechecked the changes and found no remaining concrete blocker. This is code review, not simulator verification.

A read-only git merge-tree trial against summit/integration at e9052eb49208426fbb0da16e2034fba3765ce7f1 found no conflict markers. A second trial against wip/pre-summit-2026-09-23 at 21d07f5ed9ef83e0e36ab8783174c8f4688ef644 found exactly one changed-in-both conflict: GymTracker.xcodeproj/project.pbxproj. The WIP branch adds Config/Peakline.xcconfig references in the PBXFileReference area where Wave 3A registers its new files. No other conflict marker appeared. The trial outputs are /tmp/peakline-w3a-merge-integration-final.txt and /tmp/peakline-w3a-merge-wip-final.txt. No trial merge was committed.

### Next-round wiring plan

| New piece | Existing entry point | Required data and action |
| --- | --- | --- |
| SummitLogContent and SummitMonthRidgeView | GymTracker/Views/History/HistoryView.swift, historyScreenContent around line 595, with month controls around 597 and calendar/filter/list around 626–654 | Keep the existing month navigation and filter behaviour; supply SummitSnapshot.log filtered to the displayed month, its month ridge, unitSystem, and a full-month history fetch. |
| SummitRangeView | GymTracker/Views/Progress/ProgressView.swift, Progress Charts DashboardSection around line 96 and navigation destinations around 181 | Add a destination from the charts area, passing snapshot.lifts and unitSystem. |
| SummitReachedView and SummitPostcardView | GymTracker/Views/Workout/WorkoutLoggerView.swift, motivationOverlay around line 380, which currently wraps WorkoutCelebrationOverlay | Detect a peak crossing after completion, then supply SummitMoment with peak, previous threshold, total gained, PRs, set and duration counts, first session date, session count, and next milestone. Keep Done immediate and PR presentation non-blocking. Wire onShare to SummitPostcardShareButton and onDone to dismissal. |
| SummitRouteForkView | GymTracker/Views/Today/TodayView.swift, todayRouteSection around line 1215 and planned-route presentation around 1250 | Call SummitProgressService.routePlan with readinessScore.category and routePresentation.dayName; connect lower-route and normal-preview callbacks. |
| ExpeditionView and CairnDetailView | GymTracker/Views/Today/TodayView.swift, new navigation from the Today altitude/cairn presentation | Today currently has no AltimeterView/CairnView navigation entry points, so add them and pass snapshot.expedition, reached dates, recent session frequency, and CairnState. |
| SummitAppIconPicker | GymTracker/Views/Settings/SettingsView.swift, appearance section around line 203 / AppearanceSettingsView around 525 | Pass total lifetime metres to the engine unlock calculation and present the picker within appearance settings. |
| SummitSnapshotBuilder | GymTracker/App/StartupCoordination.swift, StartupModelProjections.make around line 700 and StartupSnapshotBuilder.makePure around 1024 | Project SwiftData models (sessions, sets, exercises, bodyweight logs/profile) to values on the ModelContext boundary, then run the pure builder off main and measure its route cost. The current completed-workout fetchLimit 40 and history fetchLimit 120 cannot supply lifetime metres; use a full-history or durable incremental aggregate. Supply a persistent expedition start/choice and recent session frequency. No schema change was made in this wave. |
| SummitGalleryView | GymTracker/App/GymTrackerApp.swift, DEBUG -SummitGallery launch hook | Use for the deferred Step 3 inspection; it already lists the new top-level views with preview/empty, light/dark, and kg/lb switches. |

After Noel says round 2 has finished, Step 3 is to run only the new Summit test classes on the iPhone 17 simulator and capture each gallery view in dark and light at default and accessibility-medium text, with Reduce Motion on and off, under screens/wave3a/. The iPhone 17 simulator remained exclusively with round 2 during this build-ahead step.
