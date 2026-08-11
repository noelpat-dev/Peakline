# Architecture

Current file: `ARCHITECTURE.md`

## Overview

Peakline is a SwiftUI and SwiftData iOS app built around local workout logging, an editable ordered training rotation, deterministic coaching, progress history, sleep/recovery context, hydration, nutrition, encrypted Firebase backup/restore, and optional HealthKit bridges.

Core rule:

```text
Views present state and collect input.
Services own business rules, calculations, imports, exports, and coaching.
Models persist local source-of-truth data with SwiftData.
Shared views and theme tokens keep the UI consistent.
```

## Stack

- Platform: iOS 17+.
- UI: SwiftUI.
- Persistence: SwiftData.
- Charts: Swift Charts.
- Account backup: Firebase Auth and Cloud Firestore on the Firebase Spark plan.
- Backup security: compressed full-app JSON encrypted on device with a user passphrase before upload.
- Coaching: deterministic local rules, no AI APIs.
- Data posture: SwiftData is local source of truth; Firebase stores an encrypted latest-backup copy for account-linked restore after reinstall; imports remain reviewable and external-service failure is graceful.

## App Entry And Navigation

```text
GymTracker/App/
  GymTrackerApp.swift
  AppStartupView.swift
  RootTabView.swift
```

`GymTrackerApp` creates the SwiftData model container, configures Firebase when `GoogleService-Info.plist` is present, and installs the app theme provider. A wordmark-only `LaunchScreen.storyboard` and matching SwiftUI `PeaklineSplashView` provide one continuous branded launch surface. The in-app wordmark uses a one-shot Core Animation letter sequence on semantic theme colors, leaving SwiftUI free to prepare data without per-frame view invalidation.

`AppStartupView` owns the correctness-critical launch pipeline: inspect the local store, resolve account/restore state before seeding, seed missing defaults, run versioned local repairs, build bounded value snapshots for shared training and recovery state, build all four Preview modes for every active split, publish the Workout, Coach, Preview, bounded History, and Saved Foods warm state atomically, and only then reveal the root tabs. Existing local content never waits for Firebase; an empty signed-in store performs a metadata-only backup check and downloads encrypted chunks only after Restore is selected. Five seconds is the animation ceiling, never a minimum wait: readiness starts the 280 ms opacity-led reveal immediately. If preparation exceeds the ceiling, the wordmark settles and truthful stage progress appears. Account, restore, and error gates interrupt the splash immediately; later retry work uses a static progress state instead of replaying the cold animation.

`RootTabView` owns the primary tabs and starts non-critical backup and notification work only after critical readiness:

- Today.
- Workout.
- Splits.
- History.
- Settings.

Every root tab has a stable accessibility identifier. `RootTabContainer` owns an observation-isolated selection object and lets the native `TabView` switch immediately; root pages are not wrapped in a custom opacity, scale, slide, or broad animation transaction. This keeps the outer root's SwiftData-backed notification and Preview-warm signatures out of the selection invalidation path while preserving each tab's `NavigationStack`. Splits and History present their cached value snapshot first and defer freshness checks until after the selected tab's stable frame. Root-tab stable frames retain the 300 ms warm-route budget. Data-backed Coach and hydrated Workout Preview pushes remain deep routes with the existing 500 ms budget.

Coach, Progress, Nutrition, Sleep, Hydration, HealthKit settings, Backup/Export, Plate Calculator, Exercise Library, and templates are reached from those primary areas.

## Model Groups

```text
GymTracker/Models/
```

- Workout core: `WorkoutSession`, `ExerciseLog`, `SetLog`, `Exercise`, `TrainingSplit`, `UserProfile`, `BodyweightLog`, shared enums. `TrainingSplit.activeRotationIndex` is optional for migration safety; `isActive` controls programme membership.
- Coach and readiness: recommendation models, coach workout adjustment models, readiness models.
- Nutrition: food log/item models, import drafts, OCR/parse/comparison/insight models. `NutritionGoal.dailyFibreTarget` is optional for legacy preference and backup compatibility.
- Sleep and recovery: sleep, nap, recovery, and coaching-support models.
- HealthKit bridge: local models used to track sync state and review requirements.

Guardrails:

- Treat saved local data and user-confirmed snapshots as source of truth.
- Prefer optional/defaulted stored properties for migrations.
- Do not pass live SwiftData models across `await`; build value snapshots first.
- Preserve historical workout display even when exercises, splits, or templates change later.

## Service Groups

```text
GymTracker/Services/
```

- Workout planning and logging: `WorkoutModePlanner`, `WorkoutTemplateBuilder`, `WorkoutTemplateStore`, `WorkoutReuseBuilder`, `WorkoutSessionDateService`, `WorkoutSessionReopenService`, `SkippedExerciseReasonService`, `RestTimerManager`, `PlateCalculator`.
- Coaching and analytics: `TrainingRotationService`, `CoachRecommendationEngine`, `CoachIntelligenceService`, `ReadinessScoringService`, `ReadinessRefreshClock`, `CoachWorkoutAdjustmentService`, `WeeklyReviewBuilder`, `TargetSuggestionService`, `TrainingAnalyticsService`, `SessionSummaryBuilder`. `TrainingRotationService` owns ordering, index normalisation, legacy bootstrap, and the shared successor rule.
- History, exports, and backup: value-based History display snapshot building, `LocalBackupExportService`, `WorkoutCSVExporter`, `FullAppBackupService`, `BackupCoordinator`, `FirebaseFullAppBackupStore`, `FirebaseAccountService`, export models.
- Exercise helpers: `ExerciseIconMapper`, `ExerciseSubstitutionService`, note templates.
- Nutrition: exact-day SwiftData queries, calculator, barcode lookup, Open Food Facts, OCR, parser, comparison, insights, and data-integrity services. Historical days are browse-only and use `Calendar` day intervals for daylight-saving safety.
- Sleep and HealthKit: sleep scoring/recovery services plus HealthKit bridge services.
- Seed data: `SeedDataService` owns default exercise, split, and UI-test fixture setup.

Service guardrails:

- Keep recommendation reasons short and explainable.
- Keep external sources optional and non-destructive.
- Keep parser/OCR/barcode results editable before save.
- Keep expensive derived summaries out of hot SwiftUI `body` paths where possible.
- Preload bounded value snapshots rather than constructing every deep SwiftUI route or retaining complete histories at launch.
- Treat startup snapshot publication as one generation: Today, Workout, and Coach must not show a placeholder recommendation before resolving the active rotation.
- `WorkoutPreviewSnapshotBuilder` creates complete value-only `WorkoutPreviewPreparedSnapshot` payloads; it precomputes used exercise IDs once, traverses workout history once for substitution inputs, and calculates one base target per unique split input before applying mode adjustments. `WorkoutPreviewWarmStartStore` owns active rotation × four modes plus a bounded fallback/reuse LRU. Routes require an already-published prepared key and pin all four modes to one generation before pushing.
- A mounted Preview presents its prepared mode, session snapshot, Coach Brief, and primary Start action immediately. Its one border-only full-detail order mounts eagerly on the next rendered frame, while only the ancillary Add Exercise and duplicate footer Start sections remain lazy. Reorder-frame geometry installs after the order and before the first possible drag. Source-catalog and cache publication stay deferred until dismissal, so scrolling and mode changes cannot introduce a source-generation replacement.
- `NavigationInteraction` is the main-actor gate for programmatic pushes and sheets. It prepares haptics, rejects duplicate route requests, records tap-to-first-frame timing, and leaves animation to the native `NavigationStack` or sheet presenter.
- `WorkoutPreviewOrderReducer` is the pure route-local reorder boundary. Drag, Move Up/Down accessibility actions, and Move to Top/Bottom menus all use it; the prepared snapshot and split template remain immutable. Drag lift, finger offset, and the direction-correct insertion edge are transient view state derived from the already-installed row-frame preferences. They add no query, cache publication, persistence work, or per-move model mutation: the ordered ID list changes once on release inside the shared Preview settle transaction, and Reduce Motion removes spatial lift. `WorkoutLaunchDraft` then preserves that ordered value list into the live logger. A tap creates and inserts the lightweight session graph, pushes immediately, then saves after the logger's first frame so persistence never blocks the native transition.
- `ReadinessScore` contains `DailyCoachCheckInSnapshot`, never a live `DailyCoachCheckIn`. Today owns the canonical page-level `.sheet(item:)` host, and `DailyCheckInSheet` resolves a live model by UUID only while saving. Coach receives the prepared readiness result without mounting a duplicate Check-In entry.
- `ReadinessScoringService` is the pure deterministic aggregation boundary. `CoachIntelligenceService` first converts domain records into optional `ReadinessSignalEvidence` values, then the scorer applies the neutral 70 prior, 30/25/25/10/10 base weights, the 40% one-signal and 80% two-signal evidence ceilings, signal reliability, and bounded personal-baseline adjustments. `nil` means genuinely unavailable and contributes zero; `ReadinessFactor` retains raw score, calibrated score, reliability, effective weight, signed point contribution, and calibration adjustment for presentation and DEBUG diagnostics.
- Signal eligibility stays outside the pure scorer: overnight sleep must end on the evaluated local day, naps cannot create sleep evidence, training excludes future sessions and uses the preceding seven days, the check-in uses neutral-centred 1–5 anchors, hydration requires a same-day entry and phase reliability, and nutrition examines only the previous seven completed days with targets and qualification. Qualified nutrition is capped at a raw score of 95 and 10% aggregate influence. Weekly readiness calls the same daily scorer and excludes provisional results rather than manufacturing neutral trend points.
- Confidence is low/provisional when coverage or effective evidence is sparse, medium with at least two adequate signals, and high only with sleep, training, check-in, a qualified hydration/nutrition modifier, and at least 90% effective evidence. Provisional readiness is barred from independently selecting aggressive or recovery guidance; independent training-fatigue and muscle-fatigue evidence remains authoritative. Recommendation ranking filters unavailable factors before choosing reasons or impacts.
- `ReadinessRefreshClock` is one app-wide main-actor observable with a single cancellable boundary task. Its token includes the local calendar day, hydration pacing phase, and refresh generation. Today, Coach, Sleep, Hydration, and Nutrition append that token to their existing data signatures, so relevant writes, activation, calendar rollover, significant time changes, and the next 10:00/13:00/17:00/21:00 or midnight boundary refresh readiness without a repeating timer.
- Coach routes render from a complete `CoachRouteRenderSnapshot`, including intelligence, daily decision, the recommended value-only `WorkoutPreviewSplit`, derived metrics, sleep analytics, practical weekly summary, and `WeeklyReview`. The first frame is the real actionable Today's Call hero and installs no SwiftData query; supporting sections mount about 50 ms later from the same snapshot, then bounded live queries and observation attach. No empty or intermediate warm shell is mounted, the primary Preview action is usable immediately, and scene-phase changes never replace mounted Coach content with a placeholder.
- `WorkoutMotivationRotation` owns Logger transition copy. Its session-seeded deterministic order covers all 28 unique title/detail pairs before reuse, avoids an immediate rollover repeat, and keeps workout-completion copy outside the transition catalog.
- History renders its overview, filters, calendar aggregates, and rows from bounded immutable snapshots. The observing completed-session descriptor is reverse-date ordered and capped at 120 to match the visible history prefix. Scroll rows use flat surfaces, opacity-only press feedback, and no swipe actions so vertical scrolling does not compete with relationship traversal, shadows, or horizontal gestures.
- Saved Foods renders from an immutable `SavedFoodCatalogSnapshot` prepared during startup and addressed by a retained generation key. Its list rows are flat value views with native trailing delete actions; live `FoodItem` records are resolved by UUID only for edit, save, or confirmed deletion.
- Nutrition meal logs and Hydration logs share `SwipeRevealRow`, which owns one direct horizontal offset and one snap animation. A page-level active-row ID closes siblings without the transient `GestureState` reset that previously caused a double flick.
- `WorkoutLoggerView` owns Substitute presentation through a stable-ID `WorkoutSubstitutionRequest`; reusable exercise rows never own sheet state or query candidates during presentation.
- Workout completion is one explicit phase machine. A completion phase freezes the live logger subtree, clears hit testing before navigation, and prepares an immutable `SessionSummaryRenderSnapshot`, so rating, save, celebration, and Summary cannot leave an invisible logger-blocking layer or traverse SwiftData during the push. The internal `WorkoutCelebrationPresentation` maps rating, formatted duration, and that snapshot's prepared `PRRecord` values to copy, icon, and style: an empty PR list preserves the restrained rating-led completion, while genuine PRs select the one-shot trophy presentation without adding a query, persistence mutation, schema change, or analytics task.
- Keep Firebase backup payload download, HealthKit work, scanners, charts, notification refresh, and automatic backup outside the critical startup gate. The root remains non-interactive and accessibility-hidden until the reveal completes, and its deferred services start only after that point.
- Never upload unencrypted backup payloads.
- Never overwrite a non-empty remote backup with an empty local store.
- Require the backup passphrase again after reinstall when the cached key is unavailable.
- Do not back up credentials, HealthKit permission state, or device-only secrets.
- Preserve `activeRotationIndex` in version-2 encrypted backup and local-export split DTOs; continue decoding version-1 payloads and bootstrap their active order deterministically.

## View Groups

```text
GymTracker/Views/
```

- `Today/`: dashboard and quick actions.
- `Workout/`: start flow, preview, logger, rest timer, substitution, skipped reason, templates, completion, and session summary.
- `Splits/`: editable active-rotation programme card, stable ID detail routes, cached target calculations, exercise rows, status badges, and split editing.
- `History/`: minimal workout-day calendar markers, filters, selected-day summary, workout detail, and editing.
- `Progress/`: exercise progress, PR timeline, charts, and summaries.
- `Coach/`: coach dashboard and weekly review.
- `Nutrition/`: exact-day dashboard with read-only historical browsing, add-food flow for today, barcode/OCR import, comparison, insights, and review UI.
- `Sleep/`: sleep, naps, recovery, and related coaching surfaces.
- `Settings/`: compact Profile, Workout Tools, Appearance, library, HealthKit, backup/export, progress, and coach. The Plate Calculator is exposed as a metric workout tool and its live-set prefill relationship is explained in both entry points.
- `Shared/`: theme, motion, cards, buttons, metrics, icons, rows, chips, headers, and reusable controls.

The implemented presentation layer is owned centrally. `AppThemeProvider` resolves semantic Light and Dark palettes plus the selected accent; `AppTypography` maps hierarchy and workout-number roles onto Dynamic Type-backed system styles; and `FitnessScreen`, `FitnessCard`, `MetricTile`, `FitnessIconBadge`, shared button styles, and `AppMotion` provide the normal screen vocabulary. Content surfaces are solid semantic colours. Material remains native chrome or an isolated transient layer, with an opaque semantic fallback for Reduce Transparency. Major feature screens use at most one hero and reflow dense horizontal groups with `ViewThatFits` or accessibility-size stacking instead of clipping or aggressive scale reduction.

View guardrails:

- Prefer shared components over local one-off card styling.
- Keep normal content on solid semantic surfaces; do not reintroduce decorative glass, gradients, nested cards, repeated icon bubbles, or permanent glow.
- Use at most one hero for the screen's dominant task, recommendation, or metric. Supporting rows and metrics must remain visually quieter.
- Use one native navigation title per screen. `FitnessScreen` content headers are opt-in only for standalone surfaces that do not already own a navigation title.
- Use anchored `Menu` controls for compact row actions, sheets for substantial selection workflows, and alerts for costly destructive confirmation.
- Keep icon-only controls and compact steppers at the shared 44-point minimum hit target with explicit accessibility labels.
- Use `AppMotion` roles for local feedback, preserve immediate actions under Reduce Motion, and reserve the focused trophy starburst for prepared genuine PR completion only.
- Keep live workout logging dense and direct.
- Keep destructive actions red and scoped.
- Use stable IDs for navigation to saved/imported data rather than live model objects.

## Testing Setup

```text
GymTrackerTests/
GymTrackerUITests/
```

Current coverage includes rotation successor/migration behavior; Readiness v2 aggregate fixtures, evidence caps, eligibility, confidence, calibration, safeguards, trend filtering, provisional presentation, and immediate check-in refresh; broader Coach intelligence; snapshot-builder parity and bounded target work; reorder-reducer and launch-order invariants; motivation-catalog rotation; standard/single-PR/multi-PR completion presentation mapping; sleep recovery reliability; nutrition/export reliability; full-app backup reliability; Coach/Workout Preview performance and lifecycle UI; real drag-to-Logger continuity; a prior-lower-performance PR completion fixture through responsive Done and Summary retirement; Settings/Profile/Workout Tools/Appearance reachability; historical Nutrition navigation; five-day Splits editing; History navigation; and workout logging UI.

Useful UI-test launch arguments include in-memory storage and seeded fixtures handled by the app and `SeedDataService`. With the in-memory argument present, internal-only `-UITestAppearance light|dark|system` and `-UITestInitialTab today|workout|splits|history|settings` overrides make visual and root-surface evidence deterministic without changing production appearance or navigation state.

## Icon Pipeline

Source PNGs live outside the asset catalog:

```text
GymTracker/IconSource/ExerciseIcons/
```

Generated assets live here:

```text
GymTracker/Assets.xcassets/ExerciseIcons/
```

When adding or replacing an exact exercise icon:

1. Add the source filename to `ICON_MAP` in `Scripts/prepare_exercise_icons.py`.
2. Confirm the asset case in `ExerciseIconKey`.
3. Add exact-name mapping rules in `ExerciseIconMapper` before broad fallbacks.
4. Run `python3 Scripts/prepare_exercise_icons.py`.
5. Build and visually verify the exercise rows that should use the asset.

## Future Change Guardrails

- Keep the editable active rotation and fast set logging as the core product path.
- Do not reintroduce a multi-question readiness form.
- Keep coaching deterministic, local, and modest in certainty.
- Keep nutrition, barcode, OCR, HealthKit, and Open Food Facts data reviewable before it affects local truth.
- Add backup/export or migration tests before risky schema changes, and keep restore behavior safe for fresh installs versus existing local data.
- Keep charts lazy-loaded and large history screens performance-aware.
- Keep historical investigation material outside the public product tree; this document and the other canonical root docs define the active architecture.
