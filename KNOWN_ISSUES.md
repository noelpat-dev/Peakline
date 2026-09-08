# Known Issues

Current file: `KNOWN_ISSUES.md`

## Deferred Cold-Entry Performance — 8 September 2026

Noel explicitly deferred this work and authorized delivery of the current UI/UX changes to `main` on 8 September. The performance gate is **not passing**; successful builds and functional tests do not close it.

Cold entry here means the first visit to a route after launching the app. These are Debug, large-history measurements on the iPhone 17 simulator, timed by the app from the navigation request to its stable-frame callback. They are not physical-iPhone timings or later warm visits.

| Route | Last recorded time | Limit | Follow-up |
| --- | ---: | ---: | --- |
| Coach / Readiness | 513 ms | 500 ms | First tap opened Coach after removing unnecessary test swipes; profile remaining first-frame work. |
| Workout Preview | 484 ms | 300 ms | Prepared cache hit, zero on-appear refreshes; profile rendering cost. |
| Nutrition | 308 ms | 300 ms | Earlier isolated result; remeasure against the delivered code. |
| Progress | 520 ms | 500 ms | Earlier isolated result; remeasure against the delivered code. |
| Hydration | 385 ms | 300 ms | Earlier isolated result; remeasure against the delivered code. |

Resume with these steps:

1. Reproduce the five isolated `testPerformanceAcceptanceDataRich*Route` tests in `GymTrackerUITests/CoachWorkoutPreviewUITests.swift`, using only iPhone 17 and one simulator destination at a time. Preserve the existing limits.
2. Profile before changing rendering or query ownership. Previous extra main-queue delays and broad lazy/type-erasure experiments did not establish reliable improvements. The native sampling attempts did not capture a route entry and are not profiling evidence.
3. Fix measured bottlenecks, then run `Scripts/verify_performance_acceptance.sh` in full. Keep functional checks separate from performance acceptance.
4. Complete on-device interaction and instrumented route-timing checks on Noel's iPhone, then update this record and the handoff with actual results.

Evidence retained locally under `/private/tmp/peakline-ui-ux-20260907/`: `readiness-without-preswipes`, `preview-consistency-cold`, and `nutrition-query-removal` logs/result bundles. This table preserves the outcomes even if those temporary artifacts are removed. The 208-unit-test run passed before the final logger-only changes; the latest logger set-entry, entered-counter, manual-timer, Finish, and History UI test and signed iPhone build passed. The latest build was installed and launched on Noel's iPhone. Full performance acceptance remains deferred.

## Xcode / Device Install

- Free Apple ID installs on a real iPhone usually expire after about 7 days.
- A paid Apple Developer account is still useful for longer-lived development builds, but the current backup path no longer requires paid iCloud, CloudKit, or Sign in with Apple capabilities.
- If Xcode cannot run on a real device, confirm the device is unlocked, trusts the Mac, has a valid signing team, and uses a unique bundle identifier.
- Physical-device installation cannot proceed while either the Mac login session or iPhone is locked.

## SwiftData Migration And Async Safety

- There is still no formal migration strategy for future schema changes.
- Add stored model fields carefully. Prefer optional fields with defaults, fixtures, and migration coverage before shipping.
- Do not pass live SwiftData `@Model`, `@Query`, or `ModelContext` values into async work that can suspend. Build value snapshots first.
- Use the performance acceptance verifier after changing Today, Coach, Workout Preview, root lifecycle, notifications, or HealthKit bridge code to catch `unsafeForcedSync` regressions early.
- Historical workout display should continue to tolerate changed or missing exercises, splits, templates, and UUID snapshots.

## Exercise Guide Coverage

- All starter, legacy and split/category icon keys now display new artwork. Some illustrations intentionally represent related movements: preacher-curl variants share a pose, and abdominal crunch uses weighted crunch. Representative image metadata must never overwrite the exercise's actual equipment, muscles or name.
- Exact catalogue details remain equipment-aware and separate from representative images. Name-only `Standing Calf Raise` remains excluded from exact guide matching because its seeded equipment differs from the catalogue.
- The source contains poses and metadata, not written technique instructions. Its generated illustrations have not been validated as a comprehensive exercise-technique reference.

## Nutrition Scanner And Imports

- 8 September UI/UX follow-up: Nutrition refreshes on re-entry, resolves only its three displayed recent foods, and avoids republishing identical snapshot content. Functional date navigation, scanner entry, saved-food deletion, and save-recovery checks pass. The cold-route budget remains open: after removing its redundant workout query and covering deletion/date-repair invalidation, the latest isolated large-history sample was 308 ms against 300 ms (earlier samples were 441 ms and 316 ms). The date-repair regression and focused History/Nutrition navigation checks pass; these variable timing results do not establish consistent acceptance.

- Protect the Today-to-Nutrition scanner route: Today quick actions to Nutrition, Add Food, Scan Label, Scan Barcode, review, save, and return-to-log.
- Barcode, Open Food Facts, OCR, parser, and source-comparison values must remain editable and explicitly saved before becoming local truth.
- Navigate to saved or imported foods by stable IDs rather than live SwiftData model objects.
- HealthKit sample write and read verification still requires a physical iPhone.
- Open Food Facts remains read-only from Peakline's side.

## HealthKit And Firebase Backup

- A real Firebase `GoogleService-Info.plist` is not committed to the repo; live account backup requires adding one from the Firebase project registered to the existing compatibility bundle identifier `com.noel.GymTracker`.
- If Firebase is not configured, the startup gate allows local-only use, but that data is not protected from app deletion until a real Firebase backup is saved.
- Email/Password Authentication and Cloud Firestore must be enabled in Firebase, with rules that restrict `users/{uid}` documents to that authenticated user.
- Forgetting the backup passphrase makes the encrypted remote backup unrecoverable after reinstall.
- Spark quotas can pause backup for the month if exceeded.
- Physical-device validation on Noel's iPhone is still required for sign in, create data, save backup, delete app, reinstall, sign in again, restore, and confirm data returns.
- HealthKit should remain optional and degrade gracefully when unavailable, denied, or revoked.
- Edited synced nutrition logs may need review rather than automatic overwrite or duplicate sync.

## Coach And Recovery

- 8 September Today/Coach validation: the Debug build, the 208-test unit run, Coach/Weekly Review background retention, and Preview cancel/apply/reset/start-original flow pass. Coach now owns and cancels its post-Preview catch-up task on disappearance. A clean route journey passed at Today-to-Coach 341 ms, Coach-to-Preview 221 ms, and Workout-tab return 165 ms. The full cold-route gate remains open: the last isolated large-history samples before the target-consistency follow-up were Coach 614/500 ms, Progress 520/500 ms, Hydration 385/300 ms, and Preview 470/300 ms (measured/limit). The automated first readiness tap failed after unnecessary preparatory swipes; skipping those when the target is already hittable allowed first-tap navigation in the follow-up cold run. Direct centered first-tap navigation also passed with the same large-history data. The 8 September build is installed and launched on Noel’s iPhone, and Noel confirmed that the Preview row follows the finger smoothly. Instrumented physical-device route timings remain unmeasured.
- Coach target-consistency follow-up: prepared and live Coach now share primary-target ranking and conservative numeric-target adjustment; cached Preview modes preserve their plans while applying those target guardrails. Evidence uses the final reason and recorded lift history. Four focused target tests, Preview mode-switch acceptance (291/300 ms), and drag-to-reorder through Logger pass. All 208 unit tests pass after this follow-up. The signed update, including removal of the logger’s separate Complete Set button and the live entered-working-set counter, is installed and launched on Noel’s iPhone. The focused set-entry, live-counter, manual-timer, finish, and History test passes. The follow-up cold Coach route opened on its first tap but measured 513/500 ms; cold Preview measured 484/300 ms with a warm-cache hit and zero on-appear refreshes. Performance acceptance remains open; the full cold-route gate has not been rerun.

- Coaching is deterministic and still evolving.
- Fatigue, plateau, deload, and recovery recommendations should not overstate certainty.
- Every recommendation needs a short reason.
- Preserve Readiness Score v2's missing-data rule: unavailable sleep, training, check-in, hydration, or nutrition is unknown, never 70, poor, or zero. A one-signal score remains provisional and cannot independently justify Push, Recovery Focus, deload urgency, or a low-readiness warning.
- Keep sleep tied to an overnight session ending on the evaluated day, reject future training/history records, exclude today from nutrition qualification, and retain the five-sample/28-day threshold plus ±8 cap for personal calibration. Relaxing these gates can make stale or repeated data look more certain than it is.
- Readiness refresh is calendar- and hydration-phase-sensitive. Preserve the one cancellable boundary task and recheck Provisional coverage, `Not included` rows, immediate Check-In refresh, midnight rollover, and pacing-boundary changes during the remaining physical-device acceptance pass.
- Do not reintroduce a multi-question readiness form. The workout mode choice remains the main lightweight user control.
- The Sleep rehaul now prevents provisional readiness from presenting Push/Recovery permission, but any future Sleep, Today, or Coach copy change must preserve that cross-surface rule. Sleep stages remain absent unless genuine stage data exists, and Apple Health must never be labelled connected solely from an import preference.

## UI And Design System

- The app-wide premium-athletic migration has simulator evidence across all five root tabs in Dark, representative Today/History/Settings surfaces in forced Light, and maximum accessibility text on Today and Settings. The redesigned populated Sleep dashboard was visually inspected on iPhone 17 and the dedicated Sleep suite exercised maximum accessibility text, contrast, Reduce Motion, and Reduce Transparency, but the Mac UI controller was locked and no smaller simulator was installed. Repeat Sleep's no-data, active, settings, editors, timer, morning, and detail matrix manually on Noel's unlocked physical iPhone in Light and Dark with VoiceOver.
- Preserve the single-title rule: a screen should not render both a native navigation title and a duplicate `FitnessScreenHeader` title.
- Keep row ellipsis actions anchored to the originating row. Do not reintroduce screen-level action dialogs for exercise or split row menus.
- Keep visible measurement copy on the shared notation (`60 kg × 8`, `350 mL`, `100 g`) and use plural-aware count helpers.
- Exact exercise icon mappings can drift if broad mapper rules run before exact-name rules.
- Destructive actions should remain semantic danger or system red, not the accent color.
- Nutrition and hydration delete swipe patterns share one direct-offset implementation. Do not reintroduce `@GestureState` plus a second settled offset, which produces a visible double flick when the gesture state resets.
- Native editor `Form` and `List` surfaces should use the shared grouped content background so they do not drift from the selected theme.
- Manually verify the five-day programme chips, one-border split icons, compact History calendar, responsive Settings rows, and historical Nutrition controls on Noel's physical iPhone with Dynamic Type, VoiceOver, Reduce Transparency, and both appearance modes.
- Manually verify the genuine-PR completion in Light, Dark, large Dynamic Type, and VoiceOver. Reduce Motion must show a static gold trophy with PR copy and no moving sparks, rings, or trophy pop; Done must remain immediately tappable in every mode.

## Performance And Charts

- Keep live workout logging fast and avoid heavy recomputation in hot logging views.
- Duration calibration must continue to reject future, unfinished, zero-working-set, under-10-minute, and four-hour-or-longer sessions. Explicitly accepted long workouts remain valid History records but must not influence later Preview estimates.
- Completed-duration correction must continue to preserve `startedAt` and accumulated paused time while synchronizing seconds, rounded minutes, and `endedAt`; backup/export compatibility relies on the existing fields rather than a new schema field.
- Today, Coach, Workout Preview, Splits, History, Nutrition, Sleep, and Progress remain performance-sensitive as history grows. History snapshot rebuilding must remain outside active scroll intervals; deletion stays in Workout Detail rather than on row swipe actions. Saved Foods must remain value-backed while mounted and resolve SwiftData models only for mutations.
- Active Workout Preview content is bounded to the active rotation × four modes, with eight fallback/reuse entries. If that cap changes, re-run physical-device memory and first-frame acceptance checks rather than expanding startup work without measurement.
- Keep Preview source-data and cache publication outside the entire mounted route, not merely active scroll intervals. Retain one eager border-only detailed order and dedicated-handle drag ownership; row-wide drag gestures, duplicated orders, or lazy variable-height detailed rows can reintroduce scroll-indicator jitter. The order currently mounts from the pinned snapshot about 50 ms after the actionable top frame, and frame publication follows at about 100 ms; do not move frame setup back to the first drag, because that makes the lifted row a no-op.
- Coach must retain its last complete route snapshot while inactive or backgrounded. Its first actionable hero and prepared “Why this?” card use the value-backed recommended Preview split with no warm-frame SwiftData query; deeper supporting sections and live observation attach afterward. Do not defer every supporting card or the route shows an avoidable blank lower viewport. Do not clear the destination for app-switcher privacy; Peakline's prepared health summary contains no credential or passphrase fields.
- Today-to-Workout must pass the startup `WorkoutStartFirstFrameSnapshot` into the pushed workout content. Falling back to a live-query-built first viewport recreates the visible delay reported on physical hardware.
- Root-tab selection must remain observation-isolated from timing bookkeeping and `RootTabView`'s SwiftData-backed warm signatures. Keep the native switch free of whole-screen animation; prepared Workout, Splits, and History values must be visible before live queries attach, and keep Settings in the native sheet opened from Today's profile menu.
- Keep Today re-entry comparison out of `onDisappear`; accepted presentation signatures are maintained while Today is visible so navigation and tab selection do no synchronous snapshot work.
- Keep charts lazy-loaded.
- Exercise charts still need at least two completed sessions for a useful trend; one-session states should explain that clearly.
- Protect the current acceptance thresholds:
  `today.route.appear coach` under 500ms in the verifier path, `root.notification.refresh` under 50ms in the interactive path, and one Preview `refresh onAppear` per open.
- Coach and hydrated Workout Preview are data-backed deep routes with a 500 ms navigation budget. Lightweight warm routes remain on the 300 ms budget; do not reclassify a route merely to hide a regression.
- Simulator performance remains thermally and service-load sensitive. Use independently booted route/root samples and report variance; do not weaken thresholds to accommodate an overloaded combined UI run. Physical-device first-frame and memory validation remains required for the expanded bounded startup payloads.
- The 22 August motion pass produced a green canonical UI run at Today-to-Coach 178 ms, Coach-to-Preview 209 ms, warmed root transition 186 ms, and a dedicated root-tab sequence of 290 ms, with two Preview warm-cache hits and zero mounted Preview refreshes. Keep the 300/500 ms thresholds unchanged and rerun the verifier after any Today disappearance, Coach first-frame, History reveal, or root-tab change.

## Data And Analytics

- The app currently emphasizes best-set volume because it is easier to read than raw total tonnage.
- Future analytics can add total tonnage, PR lists, split consistency, and weekly volume summaries, but should not replace current meaning without a strong product reason.
- Firebase account backup, local backup, and export should stay healthy before risky persistence changes.

## Validation

General:

```bash
git diff --check
xcodebuild -project GymTracker.xcodeproj \
  -scheme GymTracker \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

Performance-sensitive work:

```bash
Scripts/verify_performance_acceptance.sh
```

For documentation-only tasks, `git diff --check` is sufficient unless app or project files were accidentally changed.

Physical-device QA remains outstanding because no unlocked iPhone was available for this motion pass. Recheck all four root surfaces and the Settings sheet from Today's profile menu, Today changed/unchanged re-entry washes, Logger checkmark/rest urgency/stepper direction, deletion failure retention, sheet entrances, History/Progress/Sleep charts, genuine-PR and ordinary completion, Light/Dark, maximum practical Dynamic Type, VoiceOver, Reduce Motion, and Reduce Transparency on Noel's unlocked iPhone. The iPhone 17 simulator supplied Dark/forced-Light screenshots, maximum-text and Reduce Motion smoke checks, plus accessibility-tree evidence; haptics and exact animation smoothness still require hardware.
