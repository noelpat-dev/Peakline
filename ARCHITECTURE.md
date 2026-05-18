# Architecture

## Overview

GymTracker is a personal iOS lifting tracker built around a Push/Pull/Legs workflow, progressive overload, workout history, progress charts, and lightweight rule-based coaching. The app is local-first and designed for one primary user rather than a broad public audience.

The product direction is now:

- Keep the fast workout logger.
- Make Coach and Workout share the same target logic.
- Introduce workout modes instead of a multi-question readiness form.
- Refresh the UI with an Apple Fitness-inspired but original card-based design.
- Keep all recommendations deterministic, explainable, and local.

## Technical Stack

- Platform: iOS.
- UI: SwiftUI.
- Persistence: SwiftData.
- Charts: Swift Charts.
- Architecture style: feature-folder SwiftUI views with shared SwiftData models and small services.
- Coaching strategy: deterministic rule-based logic, no AI APIs.
- Data strategy: local-first SwiftData storage.

## App Entry

```text
GymTracker/App/
  GymTrackerApp.swift
  RootTabView.swift
```

`GymTrackerApp` creates the SwiftData `ModelContainer` and wraps the app in `AppThemeProvider`.

`RootTabView` owns the main tab structure:

- Today.
- Workout.
- Splits.
- History.
- Settings.

Progress and Coach are reachable through Today and Settings rather than being primary tabs. This keeps the bottom navigation focused and avoids iOS pushing extra tabs into More.

## Core Architectural Rule

Views should not own coaching decisions.

Use this separation:

```text
Views = presentation and user input
ViewModels = screen state and coordination when needed
Services = business logic and calculations
Models = SwiftData persistence
Shared Views = reusable UI components
```

## Data Model

```text
GymTracker/Models/
  UserProfile.swift
  TrainingSplit.swift
  Exercise.swift
  WorkoutSession.swift
  ExerciseLog.swift
  SetLog.swift
  BodyweightLog.swift
  Recommendation.swift
  Enums.swift
```

Core relationships:

- `TrainingSplit` has many `SplitExercise` records.
- `SplitExercise` stores split-template targets: exercise snapshot name, order, sets, rep range, rest, and notes.
- `Exercise` is the reusable exercise library source.
- `WorkoutSession` has many `ExerciseLog` records.
- `ExerciseLog` snapshots exercise targets for a specific workout.
- `ExerciseLog` has many `SetLog` records.
- `SetLog` stores weight, reps, RPE, completion, and set number.

Important `WorkoutSession` fields:

- `startedAt` and `endedAt` store clock timestamps.
- `pausedAt` and `accumulatedPausedSeconds` support pausing the live timer.
- `durationSeconds` stores exact active workout duration after finishing.
- `durationMinutes` remains for compatibility and summary use.
- `perceivedDifficulty` stores the post-workout facial rating score.

## Planned Model Additions

### WorkoutMode

Add an enum, ideally in `Enums.swift`:

```swift
enum WorkoutMode: String, Codable, CaseIterable {
    case full
    case quick
    case recovery
    case heavy
}
```

Store the selected mode on `WorkoutSession` as a raw string if needed for SwiftData compatibility.

Purpose:

- Replace the removed multi-question readiness flow.
- Let the user adapt the session in one tap.
- Help Coach explain why volume or targets changed.

### TargetSuggestion

This may be a non-persistent struct rather than a SwiftData model.

Suggested fields:

```swift
struct TargetSuggestion {
    let exerciseName: String
    let lastBestSetDescription: String?
    let suggestedWeight: Double?
    let suggestedReps: Int?
    let recommendationType: TargetRecommendationType
    let reason: String
    let confidence: Double
}
```

### TargetRecommendationType

Add enum:

```swift
enum TargetRecommendationType: String, Codable, CaseIterable {
    case baseline
    case addReps
    case repeatTarget
    case increaseLoad
    case reduceLoad
    case possiblePlateau
    case fatigueRisk
}
```

## Services

```text
GymTracker/Services/
  SeedDataService.swift
  CoachRecommendationEngine.swift
  TargetSuggestionService.swift      Planned
  WorkoutModePlanner.swift           Planned
  SessionSummaryBuilder.swift        Planned
  HistoryFilterService.swift         Planned
```

### SeedDataService

Seeds the personal exercise library and active Push/Pull/Legs split templates. It contains the current baseline exercises, rep ranges, target sets, and notes.

### CoachRecommendationEngine

Owns deterministic coaching logic outside views. It currently:

- Recommends the next Push/Pull/Legs day.
- Explains why that split is suggested.
- Produces exercise-level progression recommendations.
- Detects simple fatigue and weekly set-count warnings.
- Flags missed split frequency.
- Detects early plateau signals.
- Produces weekly summary insights.

Future role:

- Use `TargetSuggestionService` for exercise targets.
- Use `WorkoutModePlanner` to interpret Full/Quick/Recovery/Heavy.
- Output card-ready recommendation data.

### TargetSuggestionService

Planned shared service.

Responsibilities:

- Find the latest useful exercise history.
- Determine last best set.
- Apply progression rules.
- Return target suggestions for Coach, Workout Preview, and Splits.

This avoids duplicated logic across views.

### WorkoutModePlanner

Planned shared service.

Responsibilities:

- Adjust target set count by mode.
- Adjust target messaging by mode.
- Estimate duration.
- Prioritise exercises in Quick mode.
- Reduce volume in Recovery mode.
- Prioritise compounds in Heavy mode.

### SessionSummaryBuilder

Planned shared service.

Responsibilities:

- Build post-workout summary data.
- Identify PRs and best set improvements.
- Count working sets.
- Produce motivational message.
- Suggest next split after finishing.

### HistoryFilterService

Planned shared service.

Responsibilities:

- Filter workouts by split.
- Filter by exercise.
- Filter by rating.
- Filter by date range.

## Views

```text
GymTracker/Views/
  Today/
  Workout/
  Splits/
  History/
  Progress/
  Coach/
  Settings/
  Shared/
```

## Shared UI Components

Create reusable components before broad redesign.

Planned files:

```text
GymTracker/Views/Shared/
  FitnessCard.swift
  MetricTile.swift
  CoachBadgeView.swift
  ProgressArcView.swift
  SplitCardView.swift
  ExerciseTargetRow.swift
  LiveWorkoutHeader.swift
```

### FitnessCard

Reusable rounded card used in Today, Coach, Progress, History, and Summary.

### MetricTile

Large metric with title and caption.

Examples:

- Duration.
- Working sets.
- Best set.
- Weekly workouts.

### CoachBadgeView

Small badge for recommendation state:

- Increase.
- Repeat.
- Reduce.
- Plateau.
- Fatigue.
- Ready.

### ProgressArcView

Original GymTracker circular progress visual.

Do not copy Apple Activity Rings exactly.

### ExerciseTargetRow

Reusable row for Workout Preview, Splits, and Coach.

### LiveWorkoutHeader

Persistent workout controls:

- Timer.
- Pause/resume.
- Current exercise count.
- Finish.

## Today

The Today screen is the app's overview. It should answer:

- What should I train?
- Why?
- What is my week looking like?
- What is the fastest way to start?

Planned UI:

- Large suggested split card.
- Weekly progress arc/card.
- Recent workout summary.
- Coach shortcut.
- Progress shortcut.

## Workout

Workout contains the main session flow:

- Resume unfinished workout.
- Start from Push, Pull, or Legs.
- Select today's exercises manually.
- Preserve selected exercise order.
- Add optional Abdominal Crunch across split days.
- Log one current exercise at a time.
- Add sets with previous set/session values copied forward.
- Pause and resume the active workout timer.
- Finish with a facial workout rating.
- Show a motivational transition popup between exercises and after finishing.

Planned improvements:

- Add workout mode selector: Full, Quick, Recovery, Heavy.
- Add Workout Preview before live logging.
- Use `TargetSuggestionService` for target rows.
- Add persistent `LiveWorkoutHeader`.
- Add full Session Summary screen after finishing.

## Splits

Splits presents Push, Pull, and Legs as training days within the personal PPL programme.

Planned improvements:

- Present each split as a larger card.
- Show last performed date.
- Show exercise count.
- Show coach badge.
- Show per-exercise target sets, rep range, latest best set, and progression badge.

## History

History includes:

- Calendar with workout days highlighted.
- Completed workout list.
- Swipe-to-delete for previous workouts.
- Workout detail summaries.
- Historic workout editing without the live continue/motivation flow.
- Exact duration display when available.

Planned improvements:

- Filters by split, exercise, rating, and date range.
- More visual session cards.
- PR/improvement markers in workout detail.

## Progress

Progress includes:

- Exercise list.
- Per-exercise trend details.
- Swift Charts for estimated 1RM and best-set history.

Planned improvements:

- Weekly training overview.
- Split consistency trend.
- PR list.
- Muscle-group volume balance if enough metadata exists.

Keep chart rendering lazy to avoid performance issues.

## Coach

Coach uses `CoachRecommendationEngine` and currently shows:

- Next Workout card.
- Exercise Recommendations card.
- Recovery Warnings card.
- Weekly Summary card.

Planned improvements:

- Use `FitnessCard` styling.
- Pull exercise targets from `TargetSuggestionService`.
- Display action-focused cards rather than raw analytics.
- Explain every recommendation in one short sentence.
- Support workout mode context.

Readiness note:

- Do not bring back the multi-question readiness form.
- If recovery logic is needed, express it through workout mode and simple coach warnings.

## Settings

Settings owns:

- Training setup.
- Themes.
- Exercise library.
- Progress/Coach links.
- Safety copy.
- Profile and local data notes.

Planned improvements:

- Theme preview cards.
- UI style settings only if they do not complicate the product.
- Backup/export once data grows.

## Theme System

```text
GymTracker/Views/Shared/AppTheme.swift
```

The theme system provides:

- Accent colour selection.
- Light/Dark/System appearance.
- Environment access through `appTheme`.
- App-wide `.tint(...)` application.

Current Workout Green primary accent:

```text
#7CFC00
```

Planned theme improvement:

- Add semantic colour helpers.
- Add card background/border tokens.
- Add Fitness-inspired dark dashboard surfaces.
- Keep destructive actions explicitly `.tint(.red)`.

## Persistence

The app currently uses local SwiftData storage. iCloud/CloudKit sync is not enabled in code because it requires correct Apple signing, capabilities, and container setup.

Before adding new SwiftData models or stored enum fields, test migration behaviour in the simulator.

## Current Design Constraints

- Keep workout start fast.
- Avoid adding controls that slow down a real gym session.
- Keep Push/Pull/Legs as the core structure.
- Use kg by default.
- Keep set logging dense and direct.
- Keep chart rendering lazy.
- Use standard iOS destructive styling for deletion.
- Keep coaching deterministic and explainable.
- Do not copy Apple's exact Fitness/Activity Rings UI.

## Good Next Design Directions

- Add Apple Fitness-inspired shared card components.
- Add workout modes.
- Add a cleaner pre-workout preview showing selected exercises, prior bests, and suggested targets.
- Add a persistent live-session header with timer, pause, exercise count, and finish action.
- Add per-exercise progression badges: increase load, repeat, reduce, possible plateau.
- Add a session summary screen after finishing.
- Add richer history filtering by split day, exercise, and rating.
- Add rest timer and plate calculator after the core coaching UX is stable.
