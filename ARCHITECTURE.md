# Architecture

## Overview

Peakline is a SwiftUI and SwiftData iOS lifting tracker built around a personal Push/Pull/Legs workflow, progressive overload, workout history, progress charts, and local rule-based coaching.

The current architectural direction is:

- Keep workout start and set logging fast.
- Keep Coach, Workout Preview, and Splits aligned through shared services.
- Keep recommendations deterministic, explainable, and local.
- Keep visual polish in reusable SwiftUI components.
- Keep iCloud and external integrations out until local behavior is stable.

## Technical Stack

- Platform: iOS.
- UI: SwiftUI.
- Persistence: SwiftData.
- Charts: Swift Charts.
- Architecture style: feature-folder SwiftUI views, shared SwiftData models, and small business-logic services.
- Coaching strategy: deterministic rules, no AI APIs.
- Data strategy: local-first.

## App Entry

```text
GymTracker/App/
  GymTrackerApp.swift
  RootTabView.swift
```

`GymTrackerApp` creates the SwiftData `ModelContainer` and wraps the app in `AppThemeProvider`.

`RootTabView` owns the main tabs:

- Today.
- Workout.
- Splits.
- History.
- Settings.

Progress and Coach are reachable from Today and Settings instead of being primary tabs.

## Core Rule

Views should present state and collect input. They should not own progression or coaching decisions.

```text
Views = presentation and interaction
Services = coaching, targeting, filtering, summaries, calculations
Models = SwiftData persistence
Shared Views = reusable UI primitives
```

## Models

```text
GymTracker/Models/
  BodyweightLog.swift
  Enums.swift
  Exercise.swift
  ExerciseLog.swift
  Recommendation.swift
  SetLog.swift
  TrainingSplit.swift
  UserProfile.swift
  WorkoutSession.swift
```

Core relationships:

- `TrainingSplit` has many `SplitExercise` template rows.
- `Exercise` stores reusable exercise-library records.
- `WorkoutSession` has many `ExerciseLog` rows.
- `ExerciseLog` snapshots exercise name, targets, order, and set logs for one workout.
- `SetLog` stores weight, reps, RPE, completion, and set number.

Important workout fields:

- `startedAt` and `endedAt` store actual clock timestamps.
- History grouping uses the session start date, not finish date.
- `pausedAt` and `accumulatedPausedSeconds` support the live timer.
- `durationSeconds` stores exact active workout duration after finishing.
- `perceivedDifficulty` stores the post-workout rating.

## Services

```text
GymTracker/Services/
  CoachRecommendationEngine.swift
  ExerciseIconMapper.swift
  ExerciseSubstitutionService.swift
  HistoryFilterService.swift
  PlateCalculator.swift
  RestTimerManager.swift
  SeedDataService.swift
  SessionSummaryBuilder.swift
  TargetSuggestionService.swift
  WorkoutModePlanner.swift
  WorkoutSessionDateService.swift
```

### SeedDataService

Seeds the personal exercise library and Push/Pull/Legs split templates.

### CoachRecommendationEngine

Owns deterministic coaching logic:

- Next split recommendation.
- PPL rotation explanations.
- Weekly summary insights.
- Recovery and fatigue warnings.
- Missed split warnings.

### TargetSuggestionService

Returns reusable progression targets for Coach, Workout Preview, and Split rows:

- Last best set.
- Suggested weight and reps.
- Recommendation type.
- Short reason.
- Confidence.

### WorkoutModePlanner

Applies Full, Quick, Recovery, and Heavy mode adjustments:

- Exercise inclusion.
- Set counts.
- Duration estimate.
- Target messaging.

### SessionSummaryBuilder

Builds post-workout summary data:

- Duration.
- Completed exercises.
- Working sets.
- Rating.
- Coach-style takeaway.
- Suggested next split.

### HistoryFilterService

Filters sessions by split, exercise, rating, and date range.

### ExerciseIconMapper

Maps exercise names and muscle groups to `ExerciseIconKey`. Exact icon matches should be placed before broad generic fallbacks.

## Views

```text
GymTracker/Views/
  Coach/
  History/
  Progress/
  Settings/
  Shared/
  Splits/
  Today/
  Workout/
```

Key Workout views:

- `WorkoutPreviewView`.
- `WorkoutPreviewExerciseCard`.
- `WorkoutLoggerView`.
- `LiveWorkoutHeader`.
- `RestTimerView`.
- `PlateCalculatorView`.
- `WorkoutCelebrationOverlay`.
- `SessionSummaryView`.

Key Shared components:

- `AppTheme`.
- `FitnessCard`.
- `FitnessScreenHeader`.
- `MetricTile`.
- `MetricPill`.
- `CoachBadgeView`.
- `ExerciseTargetRow`.
- `ExerciseIconKey`.
- `ExerciseIconView`.
- `ExerciseIconTile`.
- `GlassCard`.
- `GlassIconBadge`.
- `ProgressArcView`.
- `SplitCardView`.
- `StepperValueControl`.
- `WorkoutModePicker`.

## Exercise Icon Pipeline

Source PNGs are intentionally kept outside the asset catalog:

```text
GymTracker/IconSource/ExerciseIcons/
```

The generated assets live here:

```text
GymTracker/Assets.xcassets/ExerciseIcons/
```

When a source PNG is added or replaced:

1. Add the filename to `ICON_MAP` in `Scripts/prepare_exercise_icons.py`.
2. Ensure `ExerciseIconKey` has the expected asset case.
3. Add or update matching rules in `ExerciseIconMapper`.
4. Run:

```bash
python3 Scripts/prepare_exercise_icons.py
```

5. Build the app and verify the icon appears in the relevant exercise rows.

Current exact mappings include Abdominal Crunch and Cable Lateral Raise.

## Theme System

```text
GymTracker/Views/Shared/AppTheme.swift
```

The theme system provides:

- Accent colour selection.
- System, Light, and Dark appearance.
- Semantic surface, border, text, success, warning, and danger colours.
- App-wide tint application.

Destructive actions should use standard destructive styling instead of the active accent.

## Persistence

The app currently uses local SwiftData only. iCloud/CloudKit is not enabled because it requires signing, capabilities, and an iCloud container.

Before adding stored model fields, test migration behavior in the simulator.

## Current Design Constraints

- Keep workout start fast.
- Avoid readiness forms and friction-heavy pre-workout questions.
- Keep Push/Pull/Legs as the core structure.
- Use kg by default.
- Keep set logging dense and direct.
- Keep chart rendering lazy.
- Keep coaching deterministic and explainable.
- Use exact PNG exercise icons when available.
- Do not copy Apple's exact Fitness screens, Activity Rings, icons, or branding.
