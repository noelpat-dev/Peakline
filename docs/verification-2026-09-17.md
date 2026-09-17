# Verification Record — 17 September 2026

This record covers the integrated repository-cleanup and interaction-quality work (R01–R21) in the local working tree. Nothing has been committed, pushed, or published.

## Tested tree

| Item | Value |
| --- | --- |
| Branch | `main` |
| Base HEAD | `5dbdcb113992a49f2e5cbf09421fe5d818b550f0` |
| Working tree | Dirty; every integrated change is an uncommitted local edit |
| Simulator | iPhone 17, `C381D448-CD21-4A18-84E5-D68B23F2A640` (Booted) |
| Delivery state | Not committed, not pushed, not published |

## Checks that passed

Logs: `/private/tmp/peakline-flash-validation/logs/`.

| Check | Result | Log |
| --- | --- | --- |
| Clean Debug simulator build | `** BUILD SUCCEEDED **`, 204 s (03:36:40 → 03:40:04) | `01_build_clean_debug.log` |
| Focused unit tests | 21 tests, 0 failures: `InteractionQualityTests` 12, `MotionBlueprintTests` 5, `PerformanceAcceptanceStateTests` 4 | `02_unit_focused.log` |
| Preview edge-autoscroll reorder UI test | `testWorkoutPreviewEdgeAutoscrollReordersOffScreenExerciseToBottom` passed | `03_ui_coach_preview_reorder.log` |
| Immediate nonblocking Continue UI test | `testContinueAdvancesImmediatelyWithNonblockingFeedback` passed | `04_ui_continue_nonblocking.log` |
| History mounted/re-entry UI test | `testHistoryStaysMountedAndInteractiveAcrossTabReentry` passed | `05_ui_history_remount.log` |
| `git diff --check` | Clean (exit 0) | `git_diff_check.log` |
| Verifier shell syntax | `bash -n Scripts/verify_performance_acceptance.sh` (exit 0) | `bash_n_verifier.log` |

Repeated non-blocking build warning: `Metadata extraction skipped. No AppIntents.framework dependency found.` (GymTracker target, `01_build_clean_debug.log`). It does not affect the build result.

## Interactive (computer-use) evidence

Synthetic UI-test store, Dark appearance, on the simulator above:

- Today, Preview, Logger, and History were inspected as rendered.
- Preview: the accessible Move Down action changed Lat Pulldown from position 1 to 2.
- Logger: the session started with Close Grip Weighted Pull-Up first, matching the reordered Preview order.
- Logger: Continue advanced exercise 1 → 2 immediately, with inline non-blocking feedback.
- History: the goal sheet opened and dismissed, and a row in the first usable frame opened its detail and returned.

Product media, visually inspected:

- [Today](media/peakline-today-dark.png), [Preview](media/peakline-preview-dark.png), [Logger](media/peakline-logger-dark.png), [History](media/peakline-history-dark.png)
- [QuickTime demonstration](media/peakline-demo.mp4) — H.264, 31.15 s, Today → Preview → Logger → History.

## Physical-device delivery

Noel's iPhone was paired with Developer Mode enabled and a connected tunnel, but the device-targeted build attempts exited 70 before compilation because the phone stayed locked and the developer disk image could not mount (`kAMDMobileImageMounterDeviceLocked`). Install and launch were not attempted.

The fallback was a generic arm64 Debug iOS build, not an on-device build: `-destination generic/platform=iOS` succeeded and produced `/private/tmp/peakline-device-delivery/DerivedData/Build/Products/Debug-iphoneos/GymTracker.app`, bundle ID `com.noel.GymTracker`, Apple Development signature team `272AN3AJLF`.

Logs: `/private/tmp/peakline-device-delivery/build-generic.log`, `build.log`, `build-attempt2.log`, `device-details.txt`, `device-list.txt`.

Unlocking the phone is the remaining external requirement before the same CLI install/launch sequence can run. No haptics, ProMotion, HealthKit, camera, or backup/reinstall validation is claimed.

## Not rerun in this pass

Per the narrowed validation request, the canonical end-to-end verifier and the five-sample performance matrix were not rerun. **R21 acceptance measurement is unresolved; this record does not claim a performance pass.**

Retained route-timing history (Debug, large-history simulator fixtures):

| Run | today.coach | Preview deep route | workout.coach | Outcome |
| --- | ---: | ---: | ---: | --- |
| Prior route run | 405 ms | 493 ms | 81 ms | `performance_acceptance=PASS` |
| Later clean run | 347 ms | 550 ms | 992 ms | `performance_acceptance=FAIL` |

Route timing therefore remains unclosed and variable. The unchanged 300 ms warm/root and 500 ms deep-route budgets remain authoritative; no budget was relaxed or route reclassified.

## Outstanding limitations

- The full canonical verifier run is still required before this working tree is treated as release-ready.
- Physical-device behaviour (haptics, high-refresh-rate smoothness, camera, live HealthKit, Firebase reinstall recovery) is unverified here; see [Known issues](known-issues.md).

Stable budgets and the verifier contract live in [Performance](performance.md).
