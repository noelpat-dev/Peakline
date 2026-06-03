# Architecture

Current file: `ARCHITECTURE.md`

## Overview

Peakline is a SwiftUI and SwiftData iOS app built around local workout logging, Push/Pull/Legs planning, deterministic coaching, progress history, sleep/recovery context, hydration, nutrition, and optional HealthKit bridges.

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
- Coaching: deterministic local rules, no AI APIs.
- Data posture: local-first, reviewable imports, graceful external-service failure.

## App Entry And Navigation

```text
GymTracker/App/
  GymTrackerApp.swift
  RootTabView.swift
```

`GymTrackerApp` creates the SwiftData model container and installs the app theme provider. `RootTabView` owns the primary tabs:

- Today.
- Workout.
- Splits.
- History.
- Settings.

Coach, Progress, Nutrition, Sleep, Hydration, HealthKit settings, Backup/Export, Plate Calculator, Exercise Library, and templates are reached from those primary areas.

## Model Groups

```text
GymTracker/Models/
```

- Workout core: `WorkoutSession`, `ExerciseLog`, `SetLog`, `Exercise`, `TrainingSplit`, `UserProfile`, `BodyweightLog`, shared enums.
- Coach and readiness: recommendation models, coach workout adjustment models, readiness models.
- Nutrition: food log/item models, import drafts, OCR/parse/comparison/insight models.
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
- Coaching and analytics: `CoachRecommendationEngine`, `CoachIntelligenceService`, `CoachWorkoutAdjustmentService`, `WeeklyReviewBuilder`, `TargetSuggestionService`, `TrainingAnalyticsService`, `SessionSummaryBuilder`.
- History and exports: `HistoryFilterService`, `LocalBackupExportService`, `WorkoutCSVExporter`, export models.
- Exercise helpers: `ExerciseIconMapper`, `ExerciseSubstitutionService`, note templates.
- Nutrition: calculator, barcode lookup, Open Food Facts, OCR, parser, comparison, insights, and data-integrity services.
- Sleep and HealthKit: sleep scoring/recovery services plus HealthKit bridge services.
- Seed data: `SeedDataService` owns default exercise, split, and UI-test fixture setup.

Service guardrails:

- Keep recommendation reasons short and explainable.
- Keep external sources optional and non-destructive.
- Keep parser/OCR/barcode results editable before save.
- Keep expensive derived summaries out of hot SwiftUI `body` paths where possible.

## View Groups

```text
GymTracker/Views/
```

- `Today/`: dashboard and quick actions.
- `Workout/`: start flow, preview, logger, rest timer, substitution, skipped reason, templates, completion, and session summary.
- `Splits/`: Push/Pull/Legs programme cards, stable ID detail routes, cached target calculations, exercise rows, status badges, and split editing.
- `History/`: calendar, filters, workout detail, and editing.
- `Progress/`: exercise progress, PR timeline, charts, and summaries.
- `Coach/`: coach dashboard and weekly review.
- `Nutrition/`: dashboard, add-food flow, barcode/OCR import, comparison, insights, and review UI.
- `Sleep/`: sleep, naps, recovery, and related coaching surfaces.
- `Settings/`: profile, themes, library, HealthKit, backup/export, progress, coach, and utilities.
- `Shared/`: theme, motion, cards, buttons, metrics, icons, rows, chips, headers, and reusable controls.

View guardrails:

- Prefer shared components over local one-off card styling.
- Keep live workout logging dense and direct.
- Keep destructive actions red and scoped.
- Use stable IDs for navigation to saved/imported data rather than live model objects.

## Testing Setup

```text
GymTrackerTests/
GymTrackerUITests/
```

Current coverage includes coach intelligence, workout reliability, sleep recovery reliability, nutrition/export reliability, coach workout preview UI, nutrition scanner navigation UI, Splits route/detail/add-sheet UI, and workout logging UI.

Useful UI-test launch arguments include in-memory storage and seeded fixtures handled by the app and `SeedDataService`.

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

- Keep Push/Pull/Legs and fast set logging as the core product path.
- Do not reintroduce a multi-question readiness form.
- Keep coaching deterministic, local, and modest in certainty.
- Keep nutrition, barcode, OCR, HealthKit, and Open Food Facts data reviewable before it affects local truth.
- Add backup/export or migration tests before risky schema changes.
- Keep charts lazy-loaded and large history screens performance-aware.
- Use the archive index for historical context; do not treat archived prompts as current architecture.
